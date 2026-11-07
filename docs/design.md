# 设计说明

## 1. 上下游链路

```text
QQ 用户 ──"/model"──▶ 网关 gateway/slash_commands_model.py::_handle_model_command
                          │  无参数 → _model_listing_reply()
                          │
                          ├─ 适配器有 send_model_picker ? ── 是 ──▶ adapter.send_model_picker(...)
                          │                                        └─ 发带 keyboard 的消息
                          └─ 否 ──▶ 纯文本模型列表（本补丁要替换的降级路径）

QQ 用户 ──"点按钮"──▶ INTERACTION_CREATE ──▶ adapter._on_interaction()
                          │  ACK: PUT /interactions/{id}  (code 0)
                          └─ _default_interaction_dispatch(event)
                                └─ parse_model_pick_button_data(button_data)
                                      └─ _handle_model_pick_interaction(...)
                                            └─ on_model_selected(chat_id, model, provider)
                                                  └─ 网关 _perform_model_switch / _commit_model_switch
```

关键点：**网关只认适配器类上的 `send_model_picker` 方法是否存在**：

```python
# gateway/slash_commands_model.py
adapter = self._delivery_adapter_for(ctx.source)
if adapter is not None and getattr(type(adapter), "send_model_picker", None) is not None:
    ...
    if await self._send_model_picker(event, ctx.source, adapter, ctx.session_key, listing_kwargs, _on_model_selected):
        return None   # 选择器已发出，不再走文本列表
```

所以补丁不需要碰网关代码，只补适配器即可。

## 2. 适配器契约

```python
async def send_model_picker(
    self,
    chat_id: str,
    providers: list,          # [{"slug": str, "models": [model_id, ...], "is_current": bool, ...}, ...]
    current_model: str = "",
    current_provider: str = "",
    session_key: str = "",
    on_model_selected = None, # async (chat_id, model_id, provider_slug) -> str
    metadata: Optional[dict] = None,
) -> SendResult:              # 必须带 .success
```

行为约定：

- 返回 `SendResult(success=True)`：网关认为"选择器已发出"，**不再发送文本列表**；
- 返回 `success=False` 或抛异常：网关自动回落到原来的文本列表；
- `on_model_selected` 是网关注入的回调，内部会做真正的模型切换并返回一段给用户看的文本。

## 3. 键盘布局（QQ 的限制）

QQ 官方机器人 inline keyboard 的硬限制：**最多 5 行**。按每行 5 个按钮虽然能塞 25 个，
但模型名很长，5 个一行会被截断到看不懂，所以采用 **2 个/行**：

```text
行1  [ 模型1 ] [ 模型2 ]
行2  [ 模型3 ] [ 模型4 ]
行3  [ 模型5 ] [ 模型6 ]
行4  [ 模型7 ] [ 模型8 ]
行5  [ 下一页 ▸ ] [ 取消 ]        ← 最后一页只有 [ 取消 ]
```

- 一页 8 个模型（`_MODEL_PICKER_PAGE_SIZE = 8`），可在 `adapter.py` 里调整；
- 按钮标签：取模型 id 的最后一段（`anthropic/claude-fable-5.1` → `claude-fable-5.1`），截断到 24 字符；
- 当前模型加 `✓` 前缀；
- 所有按钮共享 `group_id="model_pick"`，配合 `click_limit=1` 实现"点一次即置灰"。

## 4. 排序：为什么必须把当前 provider 排前面

`list_picker_providers()` 返回的顺序按目录顺序（OpenRouter 常常第一个，动辄 50+ 个模型）。
一页只有 8 个，如果照原顺序排，用户**正在用的 provider 会被挤到第 6、7 页**，体验非常糟。

补丁里的排序键：

1. `slug == current_provider` 的 provider（当前路由）→ 最前
2. 模型列表里包含 `current_model` 的其它 provider
3. 其余

实测（某真实环境）：OpenRouter 58 个 + xiaomi 8 个 + custom 1 个 = 71 个模型，
排序后第一屏第一个按钮就是 `✓ deepseek-v4.1-flash-1017`。

## 5. 按钮数据格式

`button_data` 是纯字符串，用 `|` 分隔（模型 id 里可能有 `/`、`:`，所以**不用**冒号做分隔符）：

```text
model_pick:m|<provider_slug>|<model_id>|<session_key>   选中
model_pick:p|<page>|<session_key>                        翻页
model_pick:x|<session_key>                               取消
```

解析用前缀 `model_pick:` + 单字符 kind + 严格的分段数量校验，不匹配就返回 `None`，
交回原来的 dispatch 流程（所以不会和 `approve:` / `update_prompt:` 冲突）。

## 6. 鉴权

复用插件里已有的 `_is_authorized_interaction_for_session(event, session_key)`：

- C2C / DM：要求 `operator_openid == chat_id`
- 群 / 频道：要求点击者 openid 与会话里的 user_id 一致，且群 id 匹配

也就是说：**同一个群里，别人点你的模型按钮会被拒绝**（日志里记一条 warning），
与会话 key 里内嵌的 profile 命名空间无关，多方复用同一 bot 时不会串号。

## 7. 状态管理

`self._model_picker_pending: dict[session_key] -> {items, on_model_selected, chat_id, current, page}`

- 每个会话只保留最新一张卡片的上下文（旧的卡片点进去会提示"选择器已失效，请重新发送 /model"）；
- 选中或取消后从字典里删除，避免无限增长；
- 用 `getattr` 懒初始化，避免改动 `__init__` 造成更大的补丁冲突面。

## 8. 失败降级

`send_model_picker` 整体包在 try/except 里：任何异常都 `return SendResult(success=False, ...)`，
网关据此走文本列表。**最坏情况退化成打补丁之前的行为**，不会让 `/model` 不可用。

## 9. 与上游的关系

| 项 | 说明 |
|---|---|
| 代码归属 | 只在 `plugins/platforms/qqbot/` 内新增函数与 3 处插入 |
| 网关代码 | 未修改 |
| 其它平台 | 未修改 |
| 上游合并 | 已按上游其它适配器（Telegram/Discord/Slack/Matrix）的契约实现，理论上可直接 PR |

补丁规模：`keyboards.py` +85 行、`adapter.py` +145 行。

## 10. 实测环境

- Hermes Agent `v0.23.0+607.g981791d`（upstream `981791d9`），Linux，`systemctl --user` 托管网关
- 平台：QQ Bot（C2C）+ 元宝
- 验证方式：
  1. 在干净 checkout 上 `git apply` → 通过；
  2. 导入 `QQAdapter`，确认 `send_model_picker` 存在；
  3. 构造键盘 payload，确认 ≤5 行、`button_data` 往返解析正确；
  4. 重启网关，QQ 侧 `/model` 实际点击验证。
