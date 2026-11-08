# Changelog

## [0.2.0] - 2026-11-08

### Added
- **支持旧版 Hermes 布局**：上游在 v0.20 之前把 QQ 插件放在 `gateway/platforms/qqbot/`，
  之后才搬到 `plugins/platforms/qqbot/`。现在 `install.sh` / `uninstall.sh` 都会先探测目录，
  自动选择对应补丁：
  - `plugins/platforms/qqbot/` → `patches/qqbot-model-picker.patch`
  - `gateway/platforms/qqbot/` → `patches/qqbot-model-picker-legacy.patch`（新增）
- 新增 `patches/qqbot-model-picker-legacy.patch`（针对 v0.18.0 `6cffc37b5` 生成）：
  - 导入改为绝对路径 `from gateway.platforms.qqbot.keyboards import ...`
  - 通知改用旧版自带的 `send()`（旧版没有 `_text_sender`）
  - 新增 `_is_authorized_model_pick()`：先走上游的 `_is_authorized_interaction_for_session()`，
    再放宽私聊键的两种拼写（`c2c` / `dm`），**不改上游共享函数**，避免升级冲突

### Changed
- `install.sh` 打补丁前把两个文件备份到 `~/.hermes/qq-model-picker-backup/`（`*.preinstall.<stamp>`）
- 打补丁改为三级退让：严格 `git apply` → `git apply -C1 --recount` → GNU patch `--fuzz=3`，
  只有全部失败才报错，并打印「布局 + 版本号」
- 自检（self-check）路径改为按探测结果动态拼接；`QQAdapter` 的导入检查会区分
  「模块路径不对」与「缺第三方依赖」（后者只在输出里注明 missing dep，不算失败）
- `uninstall.sh` 同样自动识别布局；未找到插件时直接返回 0 而不是报错

### Verified
- v0.23.0（`981791d9`，`plugins/` 布局）：补丁 `git apply` 通过，自检通过
- v0.18.0（`6cffc37b5`，`gateway/` 布局）：`git apply` 通过、自检通过；另用 stub 适配器跑通
  「构建键盘 → 翻页 → 选择 → 鉴权拒绝 → 取消」全流程
- 上下文漂移场景（人为在插入点旁加行）：`-C1` / fuzz 兜底生效，上游新增行保留、结果仍可解析

## [0.1.2] - 2026-11-07

### Fixed
- **命名的自定义 provider 无法被识别为"当前"**：网关给出的 provider slug 是带作用域的
  `custom:gua`，而 config 里写的是 `custom`，精确比较会失败，导致
  - 当前模型所在的那一行不打 `✓`；
  - 标题里的"当前"退化成 `custom` 而不是真实名字 `gua`；
  - 该 provider 在排序里可能掉到 OpenRouter 后面。
  现在按「未作用域 slug 前缀」比较，并新增 `_resolve_current_item()` 把网关注入的
  `(provider, model)` 映射回真实列表项（先同 provider 同模型 → 同模型任意 provider → 同 provider 任意模型）。
- 排序改为优先使用适配器拿到的 `is_current` 标记，再退回 slug 匹配。

## [0.1.1] - 2026-11-07

### Fixed
- **选择器看不到供应商**：正文新增编号图例，每条为 `序号. 供应商 · 完整模型ID`，
  按钮使用同样的全局序号（`1.`–`8.`，翻页后接着编号），两者一一对应
- 第一版把 `供应商 · 模型` 直接塞进按钮，实测在 20 字符宽度下
  `claude-fable-5` 与 `claude-fable-5.1` 会被截断成一样的文案，反而无法区分——已回退该做法

### Changed
- 按钮标签统一为 `<序号>. <模型短名>`，当前项加 `✓`，最长 20 字符
- 正文标题带页码 `第 x/y 页`，并显示 `当前：供应商 · 模型ID`

## [0.1.0] - 2026-11-07

首个版本。

### Added
- QQ Bot 平台支持 `/model` 交互式模型选择器（inline keyboard）
  - 一页 8 个模型（QQ 键盘最多 5 行 / 每行 2 个）+ 翻页 + 取消
  - 当前模型 `✓` 标记，且当前 provider 的模型排在最前
  - 点击后按钮置灰（`click_limit=1`）
  - 复用插件现有 session key 鉴权，非本人点击无效
  - 异常自动降级为文本列表
- `install.sh` / `uninstall.sh`：打补丁、自检、可选重启网关
- `patches/qqbot-model-picker.patch`：纯新增 + 3 处插入，冲突面小

### Verified
- Hermes Agent `v0.23.0+607.g981791d`（upstream `981791d9`）
- 干净 checkout 上 `git apply --check` 通过；打补丁后自检通过
