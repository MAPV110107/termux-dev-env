# Phase 4 — LazyVim. Full Language Server Protocol (LSP) integration
# with mason.nvim and nvim-lspconfig for Bash, Markdown, Python,
# TypeScript/JavaScript, Rust, C++, Go, Kotlin, HTML, and CSS.

[ -n "${TDE_LAZYVIM_LOADED:-}" ] && return 0
TDE_LAZYVIM_LOADED=1

TDE_LAZYVIM_STARTER_URL="https://github.com/LazyVim/starter"

# Headless nvim inside the container as the target user. TDE_SKIP_TS_ENSURE=1
# switches LazyVim's own startup parser install off for installer-driven
# runs (see phase4_write_plugin_overrides), so only one thing ever builds
# parsers at a time.
_tde_nvim_headless() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" --env TDE_SKIP_TS_ENSURE=1 -- nvim --headless "$@"
}

# Number of plugins lazy.nvim reports as loaded ("" if it can't be read).
# Written with io.stdout:write, not print(): in --headless mode Neovim
# sends print()/:echo output to stderr, so a check that discards stderr
# (2>/dev/null) sees nothing at all — which made phase4_lazyvim_ok fail
# with E403 even though LazyVim was installed and lazy reported 6 plugins
# loaded. Falls back to reading print() from stderr for older builds.
_tde_lazy_loaded() {
  local loaded
  loaded="$(_tde_nvim_headless -c "lua io.stdout:write(tostring(require('lazy').stats().loaded) .. '\\n') io.stdout:flush()" -c "qa" 2>/dev/null | grep -E '^[0-9]+$' | tail -n1)" || true
  if [ -z "$loaded" ]; then
    loaded="$(_tde_nvim_headless -c "lua print(require('lazy').stats().loaded)" -c "qa" 2>&1 | grep -E '^[0-9]+$' | tail -n1)" || true
  fi
  echo "$loaded"
}

# .count is every plugin lazy.nvim's spec registered, whether or not it
# has loaded yet (most of a LazyVim setup is lazy-loaded on a filetype/
# command/event that a bare headless run with no buffer never triggers —
# see phase4_lazyvim_ok's comment on why .loaded alone stays a low bar).
# A low .count means the starter clone or one of this project's own
# plugin override files failed to parse, which .loaded alone can't tell
# apart from "just hasn't loaded anything lazy yet".
_tde_lazy_count() {
  local count
  count="$(_tde_nvim_headless -c "lua io.stdout:write(tostring(require('lazy').stats().count) .. '\\n') io.stdout:flush()" -c "qa" 2>/dev/null | grep -E '^[0-9]+$' | tail -n1)" || true
  echo "$count"
}

phase4_ensure_neovim() {
  log_info "Installing neovim and editor-adjacent tools (ripgrep, fd, lazygit)"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed \
    neovim ripgrep fd lazygit || \
    log_fatal_code 430 "Could not install neovim/ripgrep/fd/lazygit"
}

# Configures global npm prefix and installs language servers and linters.
# Symlinked into /usr/local/bin so all tools are available on PATH unconditionally.
phase4_setup_npm_global() {
  local username npm_global
  username="$(state_get ARCH_USERNAME)"
  npm_global="/home/$username/.npm-global"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    npm config set prefix "$npm_global" || \
    log_fatal_code 431 "Could not configure npm global prefix"

  # npm 10+ blocks install-scripts on global installs by default (a real
  # security default, not a bug) — core-js (a transitive dep of several
  # of these) has a no-op postinstall that's safe to allow explicitly,
  # which silences the "1 package had install scripts blocked" warning
  # without disabling the protection for anything else.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    npm config set allow-scripts=core-js --location=user || \
    log_warn "Could not set npm allow-scripts — harmless, just leaves a 'blocked install scripts' warning in the log"

  log_info "Installing global language servers and tools via npm (typescript, eslint, bashls, html/css, vtsls, pyright)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    npm install -g typescript eslint bash-language-server vscode-langservers-extracted @vtsls/language-server pyright || \
    log_warn "Global npm install of some language servers had warnings — Mason will manage remaining servers"

  proot-distro login "$TDE_DISTRO_NAME" -- sh -c "
    mkdir -p /usr/local/bin
    [ -f \"$npm_global/bin/tsc\" ] && ln -sf \"$npm_global/bin/tsc\" /usr/local/bin/tsc
    [ -f \"$npm_global/bin/eslint\" ] && ln -sf \"$npm_global/bin/eslint\" /usr/local/bin/eslint
    [ -f \"$npm_global/bin/bash-language-server\" ] && ln -sf \"$npm_global/bin/bash-language-server\" /usr/local/bin/bash-language-server
    [ -f \"$npm_global/bin/vscode-html-language-server\" ] && ln -sf \"$npm_global/bin/vscode-html-language-server\" /usr/local/bin/vscode-html-language-server
    [ -f \"$npm_global/bin/vscode-css-language-server\" ] && ln -sf \"$npm_global/bin/vscode-css-language-server\" /usr/local/bin/vscode-css-language-server
    [ -f \"$npm_global/bin/vtsls\" ] && ln -sf \"$npm_global/bin/vtsls\" /usr/local/bin/vtsls
    [ -f \"$npm_global/bin/pyright\" ] && ln -sf \"$npm_global/bin/pyright\" /usr/local/bin/pyright
  "
}

phase4_clone_lazyvim_starter() {
  local username
  username="$(state_get ARCH_USERNAME)"

  # Checked and cleaned up from inside the container (not a host-side
  # path via container_home) — see docs/TROUBLESHOOTING.md's ".zshrc
  # missing" section for why. This one matters more than most: a false
  # negative here doesn't just skip a step, it falls through to `rm -rf`
  # the whole nvim config and re-clone from scratch on every single run,
  # which would silently destroy any customization the person made to
  # their own LazyVim setup.
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       sh -c '[ -d ~/.config/nvim ] && [ ! -d ~/.config/nvim/.git ] && [ ! -f ~/.config/nvim/lua/plugins/example.lua ]' 2>/dev/null; then
    log_info "nvim config already present and cleaned, skipping starter clone"
    return 0
  fi

  # A partial clone from a crashed previous attempt would make git clone
  # refuse to run (target directory not empty) — clear it first so retry
  # actually retries instead of failing on a stale half-state. Absolute
  # path, not ~/... — bare, a tilde here would be expanded by THIS
  # (Termux-side) shell before proot-distro ever runs, silently
  # rm -rf-ing Termux's own $HOME/.config/nvim (if any) instead of the
  # container's — see docs/TROUBLESHOOTING.md's "silently checked the
  # wrong home" section.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- rm -rf "/home/$username/.config/nvim" 2>/dev/null

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    git clone --depth 1 "$TDE_LAZYVIM_STARTER_URL" "/home/$username/.config/nvim" || \
    log_fatal_code 432 "Could not clone LazyVim starter"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    sh -c 'rm -rf ~/.config/nvim/.git; rm -f ~/.config/nvim/lua/plugins/example.lua'
}

phase4_write_options_overrides() {
  local username
  username="$(state_get ARCH_USERNAME)"
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".config/nvim/lua/config/options.lua" "options" '
-- Declares the Nerd Font this project installs (see nerdfonts.sh) so
-- plugins that only draw ASCII fallbacks without it (mini.icons,
-- bufferline, lualine) draw real glyphs instead. termguicolors is
-- required for any of that to render in color at all inside Termux.
vim.g.have_nerd_font = true
vim.opt.termguicolors = true
vim.opt.emoji = false
vim.opt.ambiwidth = "single"
vim.diagnostic.config({
  virtual_text = { spacing = 4, prefix = "●" },
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})
-- Explicit shell: every terminal session, :! command, and Ctrl-/ uses zsh
vim.opt.shell = "/usr/bin/zsh"' "--" || log_warn "Could not write options.lua overrides"
}

phase4_write_keymaps() {
  local username
  username="$(state_get ARCH_USERNAME)"
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".config/nvim/lua/config/keymaps.lua" "keymaps" '
-- On-demand lint/type check keymap
vim.keymap.set("n", "<leader>lc", function()
  vim.cmd("write")
  vim.cmd("!tsc --noEmit %")
end, { desc = "Lint/type check (on-demand)" })

-- Explicit keymap for floating/split zsh terminal
vim.keymap.set({ "n", "t" }, "<C-/>", function()
  if package.loaded["snacks"] and Snacks and Snacks.terminal then
    Snacks.terminal(nil, { shell = "/usr/bin/zsh" })
  else
    vim.cmd("terminal /usr/bin/zsh")
  end
end, { desc = "Toggle ZSH Terminal" })' "--" || log_warn "Could not write keymaps.lua overrides"
}

phase4_write_autocmds_note() {
  local username
  username="$(state_get ARCH_USERNAME)"
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".config/nvim/lua/config/autocmds.lua" "autocmds" '
-- Guard on buftype before touching a buffer:
--   if vim.bo.buftype ~= "" then return end' "--" || log_warn "Could not write autocmds.lua note"
}

phase4_write_plugin_overrides() {
  local username
  username="$(state_get ARCH_USERNAME)"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c '
    mkdir -p ~/.config/nvim/lua/plugins
    rm -f ~/.config/nvim/lua/plugins/no-lsp-completion.lua
  ' || log_fatal_code 433 "Could not prepare nvim plugins directory"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    tee "/home/$username/.config/nvim/lua/plugins/lsp.lua" > /dev/null << 'EOF'
return {
  -- Language Server Protocol configuration for common languages
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        underline = true,
        update_in_insert = false,
        virtual_text = {
          spacing = 4,
          source = "if_many",
          prefix = "●",
        },
        severity_sort = true,
      },
      servers = {
        bashls = {},
        marksman = {},
        pyright = {},
        ts_ls = {},
        vtsls = {},
        rust_analyzer = {},
        clangd = {},
        gopls = {},
        kotlin_language_server = {},
        html = {},
        cssls = {},
      },
    },
  },

  -- Mason package manager for language servers, formatters, and linters
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "bash-language-server",
        "marksman",
        "pyright",
        "typescript-language-server",
        "rust-analyzer",
        "clangd",
        "gopls",
        "kotlin-language-server",
        "html-lsp",
        "css-lsp",
      },
    },
  },

  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      ensure_installed = {
        "bashls",
        "marksman",
        "pyright",
        "ts_ls",
        "rust_analyzer",
        "clangd",
        "gopls",
        "kotlin_language_server",
        "html",
        "cssls",
      },
      -- automatic_installation was removed in mason-lspconfig v2 (no
      -- longer compatible with native vim.lsp.config()); its replacement,
      -- automatic_enable, only auto-*enables* an already-installed
      -- server, it doesn't install one. Installing still happens via
      -- ensure_installed above — but mason-lspconfig deliberately does
      -- NOT run that in `nvim --headless` (upstream #175, added
      -- specifically to stop a headless run racing its own install
      -- against something like this project's own treesitter
      -- pre-install and getting killed mid-build by `-c "qa"`), so
      -- these installs land the first time the person opens nvim for
      -- real, not during ./core.sh itself. That's expected, not a bug.
      automatic_enable = true,
    },
  },

  -- Fast autocompletion with LSP source support
  {
    "saghen/blink.cmp",
    opts = {
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      completion = {
        ghost_text = { enabled = true },
        menu = { auto_show = true },
      },
    },
  },
}
EOF

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    tee "/home/$username/.config/nvim/lua/plugins/terminal.lua" > /dev/null << 'EOF'
return {
  -- Ensure snacks terminal uses zsh explicitly
  {
    "folke/snacks.nvim",
    opts = {
      terminal = {
        shell = "/usr/bin/zsh",
      },
    },
  },
}
EOF

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    tee "/home/$username/.config/nvim/lua/plugins/file-explorer.lua" > /dev/null << 'EOF'
return {
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },
  {
    "stevearc/oil.nvim",
    lazy = false,
    opts = {
      default_file_explorer = true,
      view_options = { show_hidden = true },
    },
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
    },
  },
}
EOF

  # LazyVim's nvim-treesitter (main branch) installs its own default
  # parser list (bash, c, lua, python, ... ) on EVERY startup. The
  # installer also pre-installs parsers, in the same nvim process —
  # two concurrent builds of the same parser to the same parser.so
  # ("Are you running multiple processes building to the same output
  # location?", seen on a real device). While the installer runs it sets
  # TDE_SKIP_TS_ENSURE=1 so exactly one installer (ours) is active; in
  # normal use the variable is unset and LazyVim behaves as usual,
  # including for any extras added later.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    tee "/home/$username/.config/nvim/lua/plugins/treesitter.lua" > /dev/null << 'EOF'
return {
  "nvim-treesitter/nvim-treesitter",
  opts = function(_, opts)
    if vim.env.TDE_SKIP_TS_ENSURE == "1" then
      opts.ensure_installed = {}
    end
  end,
}
EOF
}

# 'sync' spawns background jobs; wait = true is what actually blocks until
# they finish. Without it, +qa can quit before plugins finish installing —
# the same class of async race this project keeps running into elsewhere.
phase4_sync_plugins() {
  local username
  username="$(state_get ARCH_USERNAME)"
  log_info "Syncing LazyVim plugins (downloads everything on first run)"
  _tde_nvim_headless -c "lua require('lazy').sync({wait = true})" -c "qa" || \
    log_fatal_code 434 "Lazy plugin sync failed"
}

# Parsers to pre-build: LazyVim's own defaults (so its first real startup
# has nothing left to compile) plus the extra languages this project
# targets. One list, one installer, one process — see the
# TDE_SKIP_TS_ENSURE override written by phase4_write_plugin_overrides.
TDE_TS_PARSERS="bash c diff html javascript jsdoc json lua luadoc luap markdown markdown_inline printf python query regex toml tsx typescript vim vimdoc xml yaml rust cpp go kotlin css scss jsonc gitcommit gitignore"

# Pre-installs parsers instead of leaving them to on-demand install —
# otherwise the first file of each type opened pays a one-time compile.
#
# TSInstallSync belonged to nvim-treesitter's frozen 'master' branch;
# LazyVim pins 'main', which removed the TSInstall* ex-commands
# ("E492: Not an editor command") — this uses main's Lua API.
#
# Not just "run install and hope": on a phone some parser builds fail
# transiently (timeouts, low memory, an interrupted earlier run leaving a
# half-built ~/.cache/nvim/tree-sitter-<lang>/). So this checks
# get_installed() afterwards, clears the stale build dir of anything
# missing, retries just those once, and reports exactly what is still
# missing instead of an unhelpful "some failed".
phase4_install_treesitter_parsers() {
  local username lua_file lua_list p out missing
  username="$(state_get ARCH_USERNAME)"
  lua_file="/home/$username/.cache/tde/ts_install.lua"

  lua_list=""
  for p in $TDE_TS_PARSERS; do lua_list="${lua_list}'${p}',"; done

  log_info "Pre-installing treesitter parsers ($(echo "$TDE_TS_PARSERS" | wc -w) languages — this can take several minutes on a phone)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    mkdir -p "/home/$username/.cache/tde" || {
      log_warn "Could not create the parser-install helper directory — parsers will install on first use instead"
      return 0
    }
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    tee "$lua_file" > /dev/null << EOF || { log_warn "Could not write the parser-install helper — parsers will install on first use instead"; return 0; }
local want = { ${lua_list} }
local ts = require('nvim-treesitter')

local function missing()
  local have = {}
  for _, l in ipairs(ts.get_installed()) do have[l] = true end
  local m = {}
  for _, l in ipairs(want) do
    if not have[l] then m[#m + 1] = l end
  end
  return m
end

local ok, err = pcall(function() ts.install(want):wait(600000) end)
if not ok then io.stderr:write('treesitter install error: ' .. tostring(err) .. '\\n') end

local m = missing()
if #m > 0 then
  for _, l in ipairs(m) do
    vim.fn.delete(vim.fn.stdpath('cache') .. '/tree-sitter-' .. l, 'rf')
  end
  pcall(function() ts.install(m):wait(300000) end)
  m = missing()
end

io.stdout:write('TS_MISSING=' .. table.concat(m, ',') .. '\\n')
io.stdout:flush()
EOF

  out="$(_tde_nvim_headless -c "luafile $lua_file" -c "qa" 2>>"$TDE_LOG_FILE" | grep '^TS_MISSING=' | tail -n1)" || true
  missing="${out#TS_MISSING=}"
  if [ -z "$out" ]; then
    log_warn "Could not confirm which treesitter parsers installed (see $TDE_LOG_FILE) — they will still auto-install on first use of that filetype"
  elif [ -n "$missing" ]; then
    log_warn "Treesitter parsers still missing after a retry: $missing — they will auto-install on first use of that filetype (needs network then)"
  else
    log_info "All treesitter parsers installed"
  fi
}

phase4_verify_lazy() {
  local loaded
  loaded="$(_tde_lazy_loaded)"
  log_info "Lazy plugins loaded: ${loaded:-unknown}"
}

phase4_verify_treesitter_cc() {
  local username
  username="$(state_get ARCH_USERNAME)"
  # Checks for the compiler directly (command -v gcc/cc) instead of
  # grepping :checkhealth's text — that text is nvim-treesitter's own
  # UI copy, free to change across versions (and did change materially
  # moving from the 'master' to 'main' branch's rewrite), so matching it
  # is inherently fragile regardless of what the exact current wording
  # is. This also can't be confused by a genuinely missing compiler vs.
  # a PATH difference between the login session and whatever
  # :checkhealth resolves internally.
  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       sh -c 'command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1'; then
    log_info "C compiler found inside the container — treesitter can build parsers"
  else
    log_warn "No C compiler (gcc/cc) found in PATH for '$username' — treesitter parser installs may fail"
  fi
}

phase4_verify_editor_tools() {
  local username tool
  username="$(state_get ARCH_USERNAME)"
  for tool in nvim rg fd lazygit; do
    if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- command -v "$tool" >/dev/null 2>&1; then
      log_info "  OK    $tool found"
    else
      log_warn "  WARN  $tool not found — some editor features may not work"
    fi
  done
}

phase4_lazyvim_run() {
  log_info "=== Phase 4: LazyVim install and preconfiguration (with LSP & ZSH terminal) ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install neovim+tools, configure npm global prefix + language servers (bash/ts/py/html/css), clone LazyVim starter, enable LSPs in mason/lspconfig, configure zsh terminal, sync plugins (blocking), pre-install treesitter parsers, verify via lazy stats, treesitter cc check, and tool reachability"
    return 0
  fi

  phase4_ensure_neovim
  phase4_setup_npm_global
  phase4_clone_lazyvim_starter
  phase4_write_options_overrides
  phase4_write_keymaps
  phase4_write_autocmds_note
  phase4_write_plugin_overrides
  phase4_sync_plugins
  phase4_install_treesitter_parsers
  phase4_verify_lazy
  phase4_verify_treesitter_cc
  phase4_verify_editor_tools
  log_info "LazyVim installed and preconfigured"
}

# Post-condition, checked by core.sh before marking PHASE4_LAZYVIM.
# options.lua is checked from inside the container (proot-distro login
# --user), not a host-side path via container_home — see
# docs/TROUBLESHOOTING.md's ".zshrc missing" section for why.
#
# loaded > 0 (not a higher fixed number) is deliberate: this call is a
# bare 'nvim --headless' with no buffer ever opened, and most of a
# LazyVim setup's plugins are lazy-loaded on a specific filetype/command/
# keymap event that never fires in that situation — only the handful
# marked lazy=false or an early event like VeryLazy report as loaded
# here. A "realistic interactive session loads ~20+" baseline doesn't
# apply to a headless smoke test with nothing open, so a fixed floor
# like >=10 would be guessing at a number this project can't actually
# justify without instrumenting a real device's headless output — >0
# alongside nvim itself resolving is the part that's actually checkable
# from a bare headless run.
phase4_lazyvim_ok() {
  local username loaded count ok=1
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || { log_warn "post-check: no ARCH_USERNAME in state"; return 1; }

  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f "/home/$username/.config/nvim/lua/config/options.lua" 2>/dev/null; then
    log_warn "post-check: ~/.config/nvim/lua/config/options.lua is missing inside the container"
    ok=0
  fi
  # .count (every plugin lazy's spec registered) catches a broken starter
  # clone or a plugin-override file that failed to parse; .loaded alone
  # can't, since a bare headless run with no buffer never triggers most
  # of a LazyVim setup's filetype/command/event-based lazy loading — a
  # low .loaded is expected there, not a sign anything is wrong.
  count="$(_tde_lazy_count)"
  if ! { [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -ge 10 ]; }; then
    log_warn "post-check: lazy.nvim only registered ${count:-0} plugins (expected the full LazyVim spec, well over 10) — the starter clone or a plugin override file likely failed to parse"
    ok=0
  fi
  loaded="$(_tde_lazy_loaded)"
  if ! { [[ "$loaded" =~ ^[0-9]+$ ]] && [ "$loaded" -gt 0 ]; }; then
    log_warn "post-check: could not read a plugin count from lazy.nvim (got '${loaded:-nothing}') — nvim failed to start or lazy.nvim is not installed"
    ok=0
  fi
  if ! proot-distro login "$TDE_DISTRO_NAME" -- sh -c 'command -v nvim >/dev/null 2>&1'; then
    log_warn "post-check: nvim is not on PATH inside the container"
    ok=0
  fi

  [ "$ok" = "1" ]
}
