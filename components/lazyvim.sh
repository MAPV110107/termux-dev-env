# Phase 4 — LazyVim. Full Language Server Protocol (LSP) integration
# with mason.nvim and nvim-lspconfig for Bash, Markdown, Python,
# TypeScript/JavaScript, Rust, C++, Go, Kotlin, HTML, and CSS.

[ -n "${TDE_LAZYVIM_LOADED:-}" ] && return 0
TDE_LAZYVIM_LOADED=1

TDE_LAZYVIM_STARTER_URL="https://github.com/LazyVim/starter"

phase4_ensure_neovim() {
  log_info "Installing neovim and editor-adjacent tools (ripgrep, fd, lazygit)"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed \
    neovim ripgrep fd lazygit || \
    log_fatal "Could not install neovim/ripgrep/fd/lazygit"
}

# Configures global npm prefix and installs language servers and linters.
# Symlinked into /usr/local/bin so all tools are available on PATH unconditionally.
phase4_setup_npm_global() {
  local username npm_global
  username="$(state_get ARCH_USERNAME)"
  npm_global="/home/$username/.npm-global"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    npm config set prefix "$npm_global" || \
    log_fatal "Could not configure npm global prefix"

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
  # actually retries instead of failing on a stale half-state.
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- rm -rf ~/.config/nvim 2>/dev/null

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    git clone --depth 1 "$TDE_LAZYVIM_STARTER_URL" "/home/$username/.config/nvim" || \
    log_fatal "Could not clone LazyVim starter"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    sh -c 'rm -rf ~/.config/nvim/.git; rm -f ~/.config/nvim/lua/plugins/example.lua'
}

phase4_write_options_overrides() {
  local username
  username="$(state_get ARCH_USERNAME)"
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".config/nvim/lua/config/options.lua" "options" '
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
  ' || log_fatal "Could not prepare nvim plugins directory"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    tee ~/.config/nvim/lua/plugins/lsp.lua > /dev/null << 'EOF'
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
    "williamboman/mason.nvim",
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
    "williamboman/mason-lspconfig.nvim",
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
      automatic_installation = true,
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
    tee ~/.config/nvim/lua/plugins/terminal.lua > /dev/null << 'EOF'
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
    tee ~/.config/nvim/lua/plugins/file-explorer.lua > /dev/null << 'EOF'
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
}

# 'sync' spawns background jobs; wait = true is what actually blocks until
# they finish. Without it, +qa can quit before plugins finish installing —
# the same class of async race this project keeps running into elsewhere.
phase4_sync_plugins() {
  local username
  username="$(state_get ARCH_USERNAME)"
  log_info "Syncing LazyVim plugins (downloads everything on first run)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "lua require('lazy').sync({wait = true})" -c "qa" || \
    log_fatal "Lazy plugin sync failed"
}

# Pre-installs parsers instead of leaving them to LazyVim's on-demand
# auto-install — otherwise the first file of each type opened pays a
# one-time compile delay.
#
# TSInstallSync belonged to nvim-treesitter's old (now frozen) 'master'
# branch. LazyVim's starter pins nvim-treesitter to 'main', which
# removed the TSInstall* ex-commands entirely in its leaner rewrite —
# using it there is "E492: Not an editor command: TSInstallSync", which
# both breaks parser pre-install AND drags down phase4_lazyvim_ok's
# loaded-plugin count, since the failing headless command can abort the
# session before other startup work finishes. This uses 'main's actual
# Lua API instead. :wait(300000) caps it at 5 minutes — long enough for
# ~25 parsers to compile on a slow phone, short enough to not hang
# forever if something is actually stuck.
phase4_install_treesitter_parsers() {
  local username
  username="$(state_get ARCH_USERNAME)"
  log_info "Pre-installing treesitter parsers (web dev + bash + python + rust + c/cpp + go + kotlin + git + markdown + config)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "lua require('nvim-treesitter').install({ 'bash', 'lua', 'vim', 'vimdoc', 'query', 'javascript', 'typescript', 'tsx', 'python', 'rust', 'c', 'cpp', 'go', 'kotlin', 'html', 'css', 'scss', 'markdown', 'markdown_inline', 'yaml', 'toml', 'json', 'jsonc', 'gitcommit', 'gitignore', 'diff', 'regex' }):wait(300000)" -c "qa" || \
    log_warn "Some treesitter parsers failed to pre-install — they will still auto-install on first use of that filetype"
}

phase4_verify_lazy() {
  local username loaded
  username="$(state_get ARCH_USERNAME)"
  loaded="$(proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "lua print(require('lazy').stats().loaded)" -c "qa" 2>&1 | grep -E '^[0-9]+$' | tail -n1)"
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
  local username loaded
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f ~/.config/nvim/lua/config/options.lua 2>/dev/null || return 1
  loaded="$(proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "lua print(require('lazy').stats().loaded)" -c "qa" 2>/dev/null | grep -E '^[0-9]+$' | tail -n1)"
  [[ "$loaded" =~ ^[0-9]+$ ]] && [ "$loaded" -gt 0 ] || return 1
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c 'command -v nvim >/dev/null 2>&1'
}
