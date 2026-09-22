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
  local username nvim_dir
  username="$(state_get ARCH_USERNAME)"
  nvim_dir="$(container_home "$username")/.config/nvim"

  # Checks the real post-condition (cloned AND cleaned up), not just that
  # the directory exists — a crash between clone and cleanup would
  # otherwise make every future run skip the cleanup forever.
  if [ -d "$nvim_dir" ] && [ ! -d "$nvim_dir/.git" ] && [ ! -f "$nvim_dir/lua/plugins/example.lua" ]; then
    log_info "nvim config already present and cleaned, skipping starter clone"
    return 0
  fi

  # A partial clone from a crashed previous attempt would make git clone
  # refuse to run (target directory not empty) — clear it first so retry
  # actually retries instead of failing on a stale half-state.
  [ -d "$nvim_dir" ] && rm -rf "$nvim_dir"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    git clone --depth 1 "$TDE_LAZYVIM_STARTER_URL" "/home/$username/.config/nvim" || \
    log_fatal "Could not clone LazyVim starter"

  rm -rf "$nvim_dir/.git"
  rm -f "$nvim_dir/lua/plugins/example.lua"
}

phase4_write_options_overrides() {
  local nvim_dir
  nvim_dir="$(container_home "$(state_get ARCH_USERNAME)")/.config/nvim"
  idempotent_append "$nvim_dir/lua/config/options.lua" "options" '
vim.opt.emoji = false
vim.opt.ambiwidth = "single"
vim.diagnostic.config({
  virtual_text = { spacing = 4, prefix = "●" },
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})
-- Explicit shell: every terminal session, :! command, and Ctrl-/ uses zsh
vim.opt.shell = "/usr/bin/zsh"' "--"
}

phase4_write_keymaps() {
  local nvim_dir
  nvim_dir="$(container_home "$(state_get ARCH_USERNAME)")/.config/nvim"
  idempotent_append "$nvim_dir/lua/config/keymaps.lua" "keymaps" '
-- On-demand lint/type check keymap
vim.keymap.set("n", "<leader>lc", function()
  vim.cmd("write")
  vim.cmd("!tsc --noEmit %")
end, { desc = "Lint/type check (on-demand)" })

-- Explicit keymap for floating/split zsh terminal
vim.keymap.set({ "n", "t" }, "<C-/>", function()
  if Snacks and Snacks.terminal then
    Snacks.terminal(nil, { shell = "/usr/bin/zsh" })
  else
    vim.cmd("terminal")
  end
end, { desc = "Toggle ZSH Terminal" })' "--"
}

phase4_write_autocmds_note() {
  local nvim_dir
  nvim_dir="$(container_home "$(state_get ARCH_USERNAME)")/.config/nvim"
  idempotent_append "$nvim_dir/lua/config/autocmds.lua" "autocmds" '
-- Guard on buftype before touching a buffer:
--   if vim.bo.buftype ~= "" then return end' "--"
}

phase4_write_plugin_overrides() {
  local plugins_dir
  plugins_dir="$(container_home "$(state_get ARCH_USERNAME)")/.config/nvim/lua/plugins"
  mkdir -p "$plugins_dir"

  # Remove legacy no-lsp file if present
  rm -f "$plugins_dir/no-lsp-completion.lua"

  cat > "$plugins_dir/lsp.lua" << 'EOF'
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

  cat > "$plugins_dir/terminal.lua" << 'EOF'
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

  cat > "$plugins_dir/file-explorer.lua" << 'EOF'
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
phase4_install_treesitter_parsers() {
  local username
  username="$(state_get ARCH_USERNAME)"
  log_info "Pre-installing treesitter parsers (web dev + bash + python + rust + c/cpp + go + kotlin + git + markdown + config)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "TSInstallSync bash lua vim vimdoc query javascript typescript tsx python rust c cpp go kotlin html css scss markdown markdown_inline yaml toml json jsonc gitcommit gitignore diff regex" -c "qa" || \
    log_warn "Some treesitter parsers failed to pre-install — they will still auto-install on first use of that filetype"
}

phase4_verify_lazy() {
  local username loaded
  username="$(state_get ARCH_USERNAME)"
  loaded="$(proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "lua print(require('lazy').stats().loaded)" -c "qa" 2>&1 | tail -n1)"
  log_info "Lazy plugins loaded: ${loaded:-unknown}"
}

phase4_verify_treesitter_cc() {
  local username output
  username="$(state_get ARCH_USERNAME)"
  output="$(proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "checkhealth nvim-treesitter" -c "qa" 2>&1)"
  echo "$output" >> "$TDE_LOG_FILE"
  if echo "$output" | grep -q "cc.*executable found"; then
    log_info "C compiler found inside the container — treesitter can build parsers"
  else
    log_warn "No C compiler detected by :checkhealth — treesitter parser installs may fail"
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
phase4_lazyvim_ok() {
  local username nvim_dir loaded
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1
  nvim_dir="$(container_home "$username")/.config/nvim"
  [ -f "$nvim_dir/lua/config/options.lua" ] || return 1
  loaded="$(proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "lua print(require('lazy').stats().loaded)" -c "qa" 2>/dev/null | tail -n1)"
  [[ "$loaded" =~ ^[0-9]+$ ]] && [ "$loaded" -gt 0 ] || return 1
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c 'command -v nvim >/dev/null 2>&1'
}
