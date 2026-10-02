# sub-action.nvim

A submode-based, Blink-style UI for Neovim LSP code actions.

Press `gra` to see actions under the cursor and a diff beside the selected action.
Your source buffer keeps focus. The floats are display-only.

## Install

Requires **Neovim 0.11+** and an attached LSP that provides code actions.
The only required plugin dependency is
[`sirasagi62/nvim-submode`](https://github.com/sirasagi62/nvim-submode).

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "cotrin8672/sub-action.nvim",
  dependencies = {
    {
      "sirasagi62/nvim-submode",
      commit = "b427aef5da3a0ca3edab6ac0da9b66d454e2a52f",
    },
  },
  opts = {},
}
```

The dependency is pinned because its API is still developing. No call to
`nvim-submode.setup()` is needed.

![sub-action with Blink v2](assets/demo.png)

## Keys

| Key | Action |
| --- | --- |
| `gra` | Request code actions at the current cursor |
| `Tab` / `Shift-Tab` | Next / previous action, wrapping at the ends |
| `Enter` | Apply the selected action |
| `Esc` / `Ctrl-C` | Cancel |
| Characters | Build a shortcut; apply immediately when it becomes unique |
| `Backspace` | Remove the last shortcut character |

Normal-mode mappings, including `Tab`, keep their usual behavior outside the
submode. Moving the cursor, editing the source, switching windows or buffers,
or leaving Normal mode closes the session.

## Configuration

These are the defaults:

```lua
require("sub_action").setup({
  mapping = "gra", -- false to supply your own mapping
  color = nil, -- optional submode accent, e.g. "#E3A875"
  shortcut = { mode = "prefix" }, -- "prefix", "mnemonic", or "off"
  ui = {
    action = { max_width = 50, max_height = 8 },
    preview = { max_width = 70, max_height = 15 },
  },
  ranking = { frequency = true },
  client = { display = "name", icons = {} }, -- "name", "icon", or "none"
})
```

`require("sub_action").open()` opens the UI; `.close()` cancels it. `setup()`
installs the mapping. The plugin does not replace `vim.ui.select`.

`color` is available through `require("nvim-submode").get_submode_color()` while
the session is active. A statusline or cursor-color integration can use it.
For immediate UI refreshes, register a callback with
`require("nvim-submode").register_statusline(function() ... end)`.

In `prefix` mode, `Import Foo`, `Import Bar`, and `Implement members` receive
`if`, `ib`, and `im`. Typing `i` keeps the session open; the next character
chooses the action. Collisions expand the shortcut, and identical titles get
numeric suffixes. Non-ASCII titles receive generated ASCII shortcuts.

`mnemonic` assigns unique single letters or digits, preferring word initials.
There are 36 available shortcuts; additional candidates remain selectable
with Tab and Enter. `off` disables character shortcuts.

### Blink appearance

When Blink is already loaded, sub-action reuses **Blink's own window,
selection, and scrollbar implementation** (Blink v2). It inherits
the menu/documentation borders, transparency, highlights, padding, column
spacing, and scroll offset. Shortcut labels occupy Blink's kind column; action
titles and client names use `BlinkCmpLabel` and `BlinkCmpSource`.

Blink is optional. Without it, native Neovim floats use the same highlight
groups and default links (`Pmenu`, `PmenuSel`, and `NormalFloat`). Borders follow
Neovim's `winborder` option, with Blink's borderless menu and padded preview as
fallbacks. Both windows also accept `border`, `winblend`, and
`winhighlight` overrides:

```lua
require("sub_action").setup({
  ui = {
    action = { border = "rounded" },
    preview = { border = "rounded" },
  },
  client = {
    display = "icon",
    icons = { rust_analyzer = "🦀", lua_ls = "Lua" },
  },
})
```

Windows shrink to fit their contents and configured maxima. The action menu
opens below the cursor, moving above when needed; the preview prefers the
right, then the left. On terminals too narrow for a second window, the preview
is hidden and actions remain available.

### Preview and application

Only the selected action is resolved. Resolved actions are cached for that
session, and late responses cannot overwrite a newer selection. Previews use
unsaved buffer contents, Neovim's text-edit handling, the client's position
encoding, and a unified diff. Multiple documents are supported; file creation,
rename, and deletion appear as summaries without changing files.

Command-only actions remain selectable with `Preview unavailable`. Disabled
actions show their server-provided reason when applied. Applying uses
Neovim's workspace-edit and command APIs, including client-side LSP command
handlers. Actions from different clients are kept separately.

### Frequency

Successful applications are counted per filetype, kind, and exact title in
`stdpath("state")/sub-action.json`. Higher counts sort first; ties retain client
ID order and each server's response order. Saves use an atomic rename.
Concurrent Neovim processes use last-writer-wins. There is no frecency or title
normalization.

## Test

No test framework or language-server installation is needed. The check runs
two in-process LSP servers and real submode key input:

```sh
git clone https://github.com/sirasagi62/nvim-submode .deps/nvim-submode
git -C .deps/nvim-submode checkout b427aef5da3a0ca3edab6ac0da9b66d454e2a52f
nvim --headless -u NONE -l tests/run.lua
```

To use an existing dependency checkout, set `SUB_ACTION_SUBMODE` to its path.
Set `SUB_ACTION_BLINK` to a Blink checkout to also exercise its window backend;
Set `SUB_ACTION_BLINK_LIB` to its blink.lib dependency.

## Scope

This plugin handles code actions at the current cursor in Normal mode.
It does not add a fuzzy picker, diagnostic navigation, action deduplication,
or whole-file action discovery.

MIT license.
