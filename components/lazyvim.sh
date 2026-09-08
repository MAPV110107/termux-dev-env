# Phase 4 — LazyVim. No persistent LSP (vtsls et al) runs at all — that's
# the actual fix for the freezes/ghost-text/buftype bugs this project set
# out to solve, not a config toggle on top of the thing causing them.

[ -n "${TDE_LAZYVIM_LOADED:-}" ] && return 0
TDE_LAZYVIM_LOADED=1

# LazyVim/starter has no tagged releases — only 'main'. Our overrides
# (options.lua, plugins/example.lua removal, etc.) depend on its current
# file layout, so an upstream restructure could break this. Pinning to a
# specific commit would protect against that, but only after it's been
# verified on real hardware — pick a known-good SHA here once you have:
#   TDE_LAZYVIM_STARTER_REF="<commit-sha>"  # then: git clone ... && git checkout "$TDE_LAZYVIM_STARTER_REF"
TDE_LAZYVIM_STARTER_URL="https://github.com/LazyVim/starter"

phase4_ensure_neovim() {
  log_info "Installing neovim and editor-adjacent tools (ripgrep, fd, lazygit)"
  proot-distro login "$TDE_DISTRO_NAME" -- pacman -S --noconfirm --needed \
    neovim ripgrep fd lazygit || \
    log_fatal "Could not install neovim/ripgrep/fd/lazygit"
}

# The on-demand lint keymap (<leader>lc) runs tsc/eslint — neither exists
# just from installing nodejs/npm, they're separate global packages.
# Symlinked into /usr/local/bin (not exported via .zshrc) because neither
# Neovim's :! shell-outs nor a non-interactive `proot-distro login -- cmd`
# reliably source .zshrc — /usr/local/bin is on PATH unconditionally.
phase4_setup_npm_global() {
  local username npm_global
  username="$(state_get ARCH_USERNAME)"
  npm_global="/home/$username/.npm-global"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    npm config set prefix "$npm_global" || \
    log_fatal "Could not configure npm global prefix"

  log_info "Installing typescript and eslint globally (needed for <leader>lc)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    npm install -g typescript eslint || \
    log_warn "Global npm install of typescript/eslint failed — <leader>lc will not work until fixed manually"

  proot-distro login "$TDE_DISTRO_NAME" -- sh -c "
    ln -sf $npm_global/bin/tsc /usr/local/bin/tsc 2>/dev/null
    ln -sf $npm_global/bin/eslint /usr/local/bin/eslint 2>/dev/null
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
vim.diagnostic.config({ virtual_text = false })
-- Explicit, not inherited from $SHELL: the Ctrl-/ terminal and any :!
-- shell-out should use zsh regardless of what launched Neovim.
vim.opt.shell = "/usr/bin/zsh"' "--"
}

phase4_write_keymaps() {
  local nvim_dir
  nvim_dir="$(container_home "$(state_get ARCH_USERNAME)")/.config/nvim"
  idempotent_append "$nvim_dir/lua/config/keymaps.lua" "keymaps" '
-- Deliberate, user-triggered shell-out. No persistent LSP runs, so this
-- costs nothing while editing — only when you actually ask for it.
vim.keymap.set("n", "<leader>lc", function()
  vim.cmd("write")
  vim.cmd("!tsc --noEmit %")
end, { desc = "Lint/type check (on-demand)" })' "--"
}

phase4_write_autocmds_note() {
  local nvim_dir
  nvim_dir="$(container_home "$(state_get ARCH_USERNAME)")/.config/nvim"
  idempotent_append "$nvim_dir/lua/config/autocmds.lua" "autocmds" '
-- Rule for any autocmd added here: guard on buftype before touching a
-- buffer, so logic meant for real files never fires on special buffers
-- (oil.nvim, Lazy, Mason, terminal):
--   if vim.bo.buftype ~= "" then return end' "--"
}

phase4_write_plugin_overrides() {
  local plugins_dir
  plugins_dir="$(container_home "$(state_get ARCH_USERNAME)")/.config/nvim/lua/plugins"
  mkdir -p "$plugins_dir"

  cat > "$plugins_dir/no-lsp-completion.lua" << 'EOF'
return {
  { "neovim/nvim-lspconfig", enabled = false },
  { "williamboman/mason.nvim", enabled = false },
  { "williamboman/mason-lspconfig.nvim", enabled = false },
  {
    "saghen/blink.cmp",
    opts = {
      sources = { default = { "buffer", "path", "snippets" } },
      completion = {
        ghost_text = { enabled = false },
        menu = { auto_show = false },
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
# one-time compile delay. Non-fatal: auto-install still covers it if this
# fails, just with that delay.
phase4_install_treesitter_parsers() {
  local username
  username="$(state_get ARCH_USERNAME)"
  log_info "Pre-installing treesitter parsers (web dev + git + markdown + config)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "TSInstallSync bash lua vim vimdoc query javascript typescript tsx json jsonc html css scss markdown markdown_inline yaml toml gitcommit gitignore diff regex" -c "qa" || \
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
  log_info "=== Phase 4: LazyVim install and preconfiguration ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would install neovim+tools, configure npm global prefix + typescript/eslint, clone LazyVim starter, remove example.lua, disable LSP/Mason/neo-tree, add oil.nvim + on-demand lint, sync plugins (blocking), pre-install treesitter parsers, verify via lazy stats, treesitter cc check, and tsc/eslint reachability"
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
  nvim_dir="$(container_home "$username")/.config/nvim"
  [ -f "$nvim_dir/lua/config/options.lua" ] || return 1
  loaded="$(proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    nvim --headless -c "lua print(require('lazy').stats().loaded)" -c "qa" 2>/dev/null | tail -n1)"
  [[ "$loaded" =~ ^[0-9]+$ ]] && [ "$loaded" -gt 0 ] || return 1
  proot-distro login "$TDE_DISTRO_NAME" -- sh -c 'command -v tsc >/dev/null 2>&1 && command -v eslint >/dev/null 2>&1'
}
