# Changelog

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
