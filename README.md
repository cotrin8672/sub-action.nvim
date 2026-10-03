# sub-action.nvim

Blink-style LSP code actions in a Normal-mode submode. Your source buffer keeps
focus; actions and a diff appear beside the cursor.

![sub-action.nvim in WezTerm](assets/demo.png)

## Installation

Requires Neovim **0.11+** and an LSP with code actions. With
[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "cotrin8672/sub-action.nvim",
  dependencies = { "sirasagi62/nvim-submode" },
  keys = {
    { "gra", function() require("sub_action").open() end, desc = "Code actions" },
  },
}
```

Native floats match Blink v2's spacing, selection, scrollbars, and theme
highlights. Blink is neither required nor loaded. No `nvim-submode.setup()`
call is needed.

The plugin registers no Normal-mode mappings. Without lazy.nvim, use
`vim.keymap.set("n", "gra", require("sub_action").open)`.

## Usage

| Key | Action |
| --- | --- |
| `gra` (configured above) | Open code actions |
| `Tab` / `Shift-Tab` | Next / previous action |
| `Enter` | Apply and leave the submode |
| `Esc` | Cancel |
| Characters / `Backspace` | Build / shorten a shortcut |

Prefix input accepts both title prefixes and abbreviated shortcuts, ignoring
case and spaces: with `Import Foo` and `Import Bar`, `import b`, `i b`, and `ib`
all select Bar. Actions apply as soon as the combined matches become unique.
Unmatched input stays available for correction with `Backspace`. Matched title
characters highlight in place, including word initials for abbreviations;
no shortcut column is shown. Ordinary mappings resume on exit.
Moving or editing the source, switching windows, or leaving Normal mode cancels.
The menu opens immediately with a centered spinner while LSP responses are pending.
During loading it uses the action window's configured `max_width` and
`max_height`, constrained to the screen. Once ready, it sizes to the actions
within those limits.
`Esc` cancels during loading; selection, apply, and shortcut input wait until all
clients have replied. The same window then shows the actions and preview.
Bindings belong to `keymap` below. `Esc` can only map to `close` and cannot be
disabled because nvim-submode always handles it as cancel. Other disabled and
unmapped keys are ignored inside the submode.

## Configuration

Shared settings belong in `setup()` (or lazy.nvim's `opts`). Defaults:

```lua
require("sub_action").setup({
  color = "#E3A875", -- false disables the submode accent
  shortcut = { mode = "prefix" }, -- "prefix", "mnemonic", "off"
  keymap = {
    ["<Tab>"] = "next",
    ["<S-Tab>"] = "prev",
    ["<CR>"] = "apply",
    ["<BS>"] = "backspace",
    ["<Esc>"] = "close",
  },
  ui = {
    action = { max_width = 50, max_height = 8, scrollbar = true },
    preview = { max_width = 70, max_height = 15, scrollbar = true },
  },
  ranking = { frequency = false }, -- enable explicitly to rank and save history
  client = { display = "auto", icons = {} }, -- "auto", "name", "icon", "none"
})
```

Set a binding to `false` to disable it, e.g.
`keymap = { ["<Tab>"] = false, ["<C-n>"] = "next" }`.
`open()` uses shared settings without calling `setup()`. A call may override
only the shortcut: `open({ shortcut = { mode = "mnemonic" } })`.
`close()` cancels. Unknown options and invalid values are errors.

For nonstandard actions, set `preview = function(action, context) ... end` in
`setup()` or `opts`. Return a list of display lines, or `nil` to use the native
WorkspaceEdit preview. The callback receives the action after resolve (when
supported), plus `context.client` and `context.bufnr`. Results are cached per
action. Preview callbacks must not edit buffers or mutate the action; applying
still executes the original edit and command. The default is `preview = false`.

Window `winhighlight` uses `BlinkCmpMenu`, `BlinkCmpMenuBorder`, and
`BlinkCmpMenuSelection` for actions; `BlinkCmpDoc` and `BlinkCmpDocBorder` for
previews. These theme groups fall back to native highlights. Omitted
`border` and `winblend` inherit Neovim's global `winborder` and `winblend` when
opened; explicit values override them. An empty `winborder` uses Blink's defaults:
`none` for actions, `padded` for previews. Missing client icons are omitted.
`auto` shows client names only when multiple clients return actions.
Client names use `SubActionClient` (linked to `Comment`); typed matches use
`BlinkCmpLabelMatch`. Both highlights can be overridden with `nvim_set_hl`.
The accent is exposed through
`require("nvim-submode").get_submode_color()` for statuslines and cursor colors.
If lualine is already loaded, code actions temporarily apply the accent to the
theme's `a`/`z` backgrounds and `b`/`y` foregrounds, including their separators.
The original theme returns on exit. No lualine configuration change is needed;
custom component colors remain in control. `color = false` disables this too.
Diff file headers display the shortest distinct path suffix: usually just the
filename, with parent directories retained for moves or files with the same
name. `/dev/null` stays visible for creation/deletion. This applies to native
and custom previews without changing their original lines or action data.

## Performance

Setup loads only the entry point, even without lazy.nvim. Selection reuses the
menu and cached diffs; rapid input coalesces preview work. Actions resolve ahead
of apply, and confirming releases input immediately. Source edits during a
pending resolve cancel that action.

When enabled, frequency is kept per filetype, kind, and title. Saves are batched
asynchronously and flushed on normal exit to `stdpath("state")/sub-action.json`.
Concurrent processes use last-writer-wins.

## Development

Set `SUB_ACTION_SUBMODE` to a dependency checkout, or clone it to `.deps/nvim-submode`.

```sh
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -i NONE -l tests/bench.lua
```

For lualine integration checks, also set `SUB_ACTION_LUALINE` to its checkout
and run `nvim --headless -u NONE -i NONE -l tests/lualine.lua`.

Benchmarks report local processing times in µs, excluding LSP transport and
terminal rendering. Set `SUB_ACTION_BENCH_PHASE=setup` to measure startup only.

[MIT](LICENSE).
