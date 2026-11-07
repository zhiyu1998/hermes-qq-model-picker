# Changelog

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
