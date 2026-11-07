# hermes-qq-model-picker

> 给 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 的 **QQ 机器人**补上 `/model` 的**可点击模型选择器**。

在 QQ 里发 `/model`，不再是"给你一段文字列表、然后自己手打 `/model <model> --provider <slug>`"，
而是直接弹出一张**带按钮的卡片**：点一下就切模型，当前模型带 ✓，支持翻页和取消，
**每条都标了所属供应商**。

```text
🧠 选择模型（第 1/2 页）

当前：Custom endpoint · `deepseek-v4.1-flash-1017`

1. Custom endpoint · `deepseek-v4.1-flash-1017` ✓
2. OpenRouter · `anthropic/claude-fable-5.1`
3. OpenRouter · `anthropic/claude-fable-5`
4. OpenRouter · `anthropic/claude-opus-5.5`
5. OpenRouter · `anthropic/claude-opus-5`
6. OpenRouter · `anthropic/claude-opus-4.8`
7. OpenRouter · `anthropic/claude-sonnet-5.5`
8. OpenRouter · `anthropic/claude-sonnet-5`

点下面的数字按钮切换：

[ ✓1. deepseek-v4.1-f… ] [ 2. claude-fable-5.1 ]
[ 3. claude-fable-5    ] [ 4. claude-opus-5.5  ]
[ 5. claude-opus-5     ] [ 6. claude-opus-4.8  ]
[ 7. claude-sonnet-5.5 ] [ 8. claude-sonnet-5  ]
[ 下一页 ▸ ]             [ 取消 ]
```

> **为什么按钮上不直接写供应商？**
> QQ 的按钮文案宽度很窄（本实现按 20 字符排版）。硬拼成 `OpenRouter · claude-fable-5.1` 会被截断成
> `OpenRouter · claude-fab…`，`claude-fable-5` 和 `claude-fable-5.1` 反而显示成一模一样。
> 所以采用**编号 + 正文图例**：正文里 `1.`–`8.` 列出完整的「供应商 · 模型 ID」，
> 按钮上是同样的编号 + 尽可能长的模型名，点哪个编号就是对哪一行。

---

## 为什么需要它

Hermes 的 `/model`（不带参数）本来会尝试发交互式选择器，但**前提是当前平台适配器实现了 `send_model_picker`**。
上游仓库里实现了的只有：

| 平台 | 交互式选择器 |
|---|---|
| Telegram | ✅ |
| Discord | ✅ |
| Slack | ✅ |
| Matrix | ✅ |
| **QQ Bot** | ❌ 没有 → 回落到纯文本列表 |

QQ 官方机器人 API 其实**支持 inline keyboard**，插件里也已经有完整的键盘实现（审批按钮、"是否更新"按钮都在用），
只是没有接到 `/model` 上。本项目就是把这块补齐。

## 特性

- **供应商可见**：正文图例里每条都是 `供应商 · 模型ID`（`Custom endpoint · deepseek-v4.1-flash-1017`、
  `OpenRouter · anthropic/claude-fable-5.1`），按钮用同样的编号对应
- **点选即切换**：一页 8 个模型（4 行 × 2 个）+ 1 行操作区，正好压满 QQ 的 5 行键盘上限
- **当前模型优先**：`✓` 标记当前模型，并且**把当前 provider 的模型排在最前面**
  （这点很关键：如果你的账号里接了 OpenRouter 的 58 个模型，不排序的话你正在用的模型会被挤到第 7 页）
- **翻页 / 取消**：`下一页 ▸`、`取消`，正文显示 `第 x/y 页`
- **点过即置灰**：`click_limit=1`，避免重复点击造成多次切换
- **操作人鉴权**：复用插件自带的 session key 校验，别人在你群里点按钮无效
- **失败自动降级**：任何异常都会让适配器返回失败，网关自动回落到原来的文字列表——不会把 `/model` 弄坏

## 安装

### 方式一：一键（已 clone 本仓库）

```bash
git clone https://github.com/<you>/hermes-qq-model-picker.git
cd hermes-qq-model-picker
./install.sh                 # 只打补丁 + 自检
./install.sh --restart       # 打补丁 + 重启网关
```

### 方式二：手动

```bash
cd ~/.hermes/hermes-agent
git apply /path/to/patches/qqbot-model-picker.patch
hermes gateway restart        # 或: systemctl --user restart hermes-gateway.service
```

Windows 上 Hermes 的安装目录通常是 `%USERPROFILE%\.hermes\hermes-agent`，
重启用 `hermes gateway restart`（或相应服务命令）。

### 验证

```bash
cd ~/.hermes/hermes-agent
venv/bin/python -c "from plugins.platforms.qqbot.adapter import QQAdapter; print(hasattr(QQAdapter,'send_model_picker'))"
# 期望输出 True
```

然后在 QQ 里发 `/model`，应该直接收到带按钮的卡片。

## 卸载 / 回滚

```bash
./uninstall.sh              # git checkout 还原两个文件
./uninstall.sh --restart    # 还原并重启网关
```

## ⚠️ 升级注意

补丁改的是 hermes-agent **仓库里的插件文件**，`hermes update` 会用上游版本覆盖它们。
升级之后重新执行一次 `./install.sh` 即可（安装脚本会先检查是否已应用）。

如果上游改了 `plugins/platforms/qqbot/adapter.py` 的上下文导致补丁打不上：

```bash
cd ~/.hermes/hermes-agent
git apply --3way /path/to/patches/qqbot-model-picker.patch   # 三方合并，冲突处手动解
```

## 兼容性

- 在 **Hermes Agent v0.23.0+607.g981791d**（upstream `981791d9`）上开发并实测
- 补丁只动两个文件，纯新增函数 + 3 处插入，冲突面很小：
  - `plugins/platforms/qqbot/keyboards.py`（+85 行）
  - `plugins/platforms/qqbot/adapter.py`（+145 行）
- 依赖 `plugins/platforms/qqbot/keyboards.py` 里已有的 `InlineKeyboard` / `INTERACTION_CREATE` 交互链路

## 已知限制

- QQ 键盘最多 5 行、每行最多 5 个按钮 → 一页 8 个模型，更多靠翻页
- QQ 按钮文案宽度有限（本实现按 20 字符排版）→ 按钮只能放 `编号 + 模型名`，
  供应商在正文图例里（见上文说明）；模型名过长会被 `…` 截断
- QQ 不支持**编辑已发送消息**，所以翻页是"再发一条新卡片"，旧卡片的按钮仍可点（点击后按当前状态处理）
- 只有 C2C / 群聊支持键盘（频道/guild 不支持，会自动回落到文字列表）
- 模型数量很多时（例如 OpenRouter 全量），翻页会比较多；可以在 `adapter.py` 里调 `_MODEL_PICKER_PAGE_SIZE`

## 原理

详见 [docs/design.md](docs/design.md)。一句话版：

> 网关在 `/model` 无参数时检查 `getattr(type(adapter), "send_model_picker", None)`；
> 我们给 `QQAdapter` 加了这个方法（发键盘 + 记住待选状态），
> 并在 `_default_interaction_dispatch` 里处理 `model_pick:...` 的按钮回调，转交给网关的切换逻辑。

按钮数据格式（`button_data`）：

```text
model_pick:m|<provider_slug>|<model_id>|<session_key>   # 选中模型
model_pick:p|<page>|<session_key>                       # 翻页
model_pick:x|<session_key>                              # 取消
```

## License

MIT — 见 [LICENSE](LICENSE)。

本项目只包含**补丁与安装脚本**，不包含 Hermes Agent 的任何源码；
Hermes Agent 本身遵循其上游仓库的许可证。

---

## English summary

Hermes Agent's `/model` command only shows an interactive picker on platforms whose
adapter implements `send_model_picker` — currently Telegram, Discord, Slack and Matrix.
On QQ the command falls back to a plain text list, forcing users to type
`/model <model> --provider <slug>`.

The QQ Bot plugin already ships a complete inline-keyboard implementation (used by the
approval buttons), so this repo adds the missing picker:

- 8 models per page (QQ allows at most 5 keyboard rows) + `下一页` / `取消`
- **every entry shows its provider**: the message body renders a numbered legend
  (`1. Custom endpoint · deepseek-v4.1-flash-1017`), and the buttons carry the same
  global index (`1.`–`8.`, continuing across pages). Putting `provider · model` on
  the button itself does not fit QQ's ~20-char label width and made
  `claude-fable-5` / `claude-fable-5.1` render identically.
- current model marked with `✓`, and the **active provider's models sorted first**
  (otherwise a 58-model OpenRouter catalog pushes your own model to page 7)
- `click_limit=1` so a tapped button greys out; clicks are authorized against the
  session key so other members of the group cannot switch your model
- any failure returns `success=False` so Hermes falls back to the old text list

Install: `./install.sh --restart` (apply patch + self-check + restart gateway).
Uninstall: `./uninstall.sh --restart`.

Note: the patch touches files inside the hermes-agent checkout, so `hermes update`
overwrites it — re-run `./install.sh` after an upgrade.

