# hermes-qq-model-picker

[中文](README.md) | **English**

> A **clickable model picker** for the `/model` command of the [Hermes Agent](https://github.com/NousResearch/hermes-agent) **QQ bot**.

Send `/model` in QQ and instead of getting "here is a text list, now type
`/model <model> --provider <slug>` yourself", you get a **card with buttons**:
tap one to switch models, the current model carries a ✓, with paging and cancel,
and **every entry shows which provider it belongs to**.

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

(The picker's own UI strings are Chinese: `选择模型` = "choose a model", `当前` = "current",
`下一页` = "next page", `取消` = "cancel".)

> **Why doesn't the button itself carry the provider?**
> QQ button labels are very narrow (this implementation wraps at 20 characters). Forcing
> `OpenRouter · claude-fable-5.1` onto a button truncates it to
> `OpenRouter · claude-fab…`, which makes `claude-fable-5` and `claude-fable-5.1` look
> identical. So the design is **index + legend in the body**: the message body lists the
> full `provider · model-id` for `1.`–`8.`, and each button carries the same index plus as
> much of the model name as fits. Tapping an index selects that line.

---

## Why this is needed

Hermes' `/model` (without arguments) does try to send an interactive picker — but **only if
the current platform adapter implements `send_model_picker`**. In the upstream repository
only these do:

| Platform | Interactive picker |
|---|---|
| Telegram | ✅ |
| Discord | ✅ |
| Slack | ✅ |
| Matrix | ✅ |
| **QQ Bot** | ❌ none → falls back to a plain text list |

The official QQ bot API does **support inline keyboards**, and the plugin already ships a
complete keyboard implementation (the approval buttons and the "update available" buttons
use it) — it just was never wired up to `/model`. This project fills that gap.

## Features

- **Provider is visible**: every line of the legend is `provider · model-id`
  (`Custom endpoint · deepseek-v4.1-flash-1017`,
  `OpenRouter · anthropic/claude-fable-5.1`), and the buttons use the same numbering
- **Tap to switch**: 8 models per page (4 rows × 2) + 1 action row, exactly filling QQ's
  5-row keyboard limit
- **Current model first**: the current model is marked `✓`, and **models of the active
  provider are sorted to the front** (this matters: with 58 OpenRouter models attached to
  your account, an unsorted list pushes the model you are using onto page 7)
- **Paging / cancel**: `下一页 ▸` (next page) and `取消` (cancel); the body shows `第 x/y 页`
  (page x of y)
- **Greys out after one tap**: `click_limit=1`, so a tap cannot trigger repeated switches
- **Click authorization**: reuses the plugin's existing session-key check, so someone else
  tapping in your group has no effect
- **Automatic fallback**: any exception makes the adapter report failure, and the gateway
  falls back to the old text list — `/model` never breaks

## Install

### Option 1: one-liner (repository already cloned)

```bash
git clone https://github.com/<you>/hermes-qq-model-picker.git
cd hermes-qq-model-picker
./install.sh                 # apply patch + self-check only
./install.sh --restart       # apply patch + restart gateway
```

### Option 2: manual

```bash
cd ~/.hermes/hermes-agent
git apply /path/to/patches/qqbot-model-picker.patch
hermes gateway restart        # or: systemctl --user restart hermes-gateway.service
```

On Windows, Hermes is usually installed at `%USERPROFILE%\.hermes\hermes-agent`;
restart with `hermes gateway restart` (or the equivalent service command).

### Verify

```bash
cd ~/.hermes/hermes-agent
venv/bin/python -c "from plugins.platforms.qqbot.adapter import QQAdapter; print(hasattr(QQAdapter,'send_model_picker'))"
# expected output: True
```

Then send `/model` in QQ and you should receive a card with buttons right away.

## Uninstall / rollback

```bash
./uninstall.sh              # git checkout to restore the two files
./uninstall.sh --restart    # restore and restart the gateway
```

## ⚠️ Upgrade caveat

The patch modifies **plugin files inside the hermes-agent checkout**, and `hermes update`
overwrites them with the upstream versions. Just re-run `./install.sh` after an upgrade
(the installer first checks whether the patch is already applied).

If upstream changed the context around `plugins/platforms/qqbot/adapter.py` so the patch no
longer applies:

```bash
cd ~/.hermes/hermes-agent
git apply --3way /path/to/patches/qqbot-model-picker.patch   # three-way merge, resolve conflicts by hand
```

## Compatibility

- Developed and tested against **Hermes Agent v0.23.0+607.g981791d** (upstream `981791d9`)
- The patch touches only two files, with purely additive functions + 3 insertion points, so
  the conflict surface is small:
  - `plugins/platforms/qqbot/keyboards.py` (+85 lines)
  - `plugins/platforms/qqbot/adapter.py` (+145 lines)
- Relies on the existing `InlineKeyboard` / `INTERACTION_CREATE` interaction path in
  `plugins/platforms/qqbot/keyboards.py`

## Known limitations

- A QQ keyboard allows at most 5 rows of at most 5 buttons → 8 models per page, more via paging
- QQ button labels are narrow (this implementation wraps at 20 characters) → buttons can only
  carry `index + model name`, with the provider in the body legend (see above); overlong
  model names are truncated with `…`
- QQ cannot **edit an already-sent message**, so paging sends a new card and the old card's
  buttons remain tappable (they are handled against the current state)
- Only C2C and group chats support keyboards (channels/guilds do not; they fall back to the
  text list automatically)
- With a very large model catalog (e.g. all of OpenRouter) paging gets long; tune
  `_MODEL_PICKER_PAGE_SIZE` in `adapter.py`

## How it works

See [docs/design.md](docs/design.md) (Chinese). One-sentence version:

> When `/model` is called without arguments, the gateway checks
> `getattr(type(adapter), "send_model_picker", None)`; we add that method to `QQAdapter`
> (send the keyboard + remember the pending selection) and handle `model_pick:...` button
> callbacks in `_default_interaction_dispatch`, handing them to the gateway's switching
> logic.

Button data format (`button_data`):

```text
model_pick:m|<provider_slug>|<model_id>|<session_key>   # select a model
model_pick:p|<page>|<session_key>                       # page
model_pick:x|<session_key>                              # cancel
```

## License

MIT — see [LICENSE](LICENSE).

This project contains only **a patch and install scripts**; it includes no Hermes Agent
source code. Hermes Agent itself is licensed under its upstream repository's terms.
