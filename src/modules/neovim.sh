# Phase 4, step 4 — LazyVim installation, Nerd Font UI tuning, dynamic LSP configuration,
# and Treesitter parser pre-compilation (supports TDE_TREESITTER_FULL=1).

[ -n "${TDE_MODULE_NEOVIM_LOADED:-}" ] && return 0
TDE_MODULE_NEOVIM_LOADED=1

TDE_LAZYVIM_STARTER_URL="https://github.com/LazyVim/starter"

TDE_TS_PARSERS_CORE="lua bash python markdown markdown_inline json typescript tsx javascript html css yaml toml vim vimdoc query regex"
TDE_TS_PARSERS_FULL="$TDE_TS_PARSERS_CORE c cpp rust go gomod gosum dockerfile git_config gitcommit gitignore sql xml"

_tde_resolve_ts_parsers() {
  if [ "${TDE_TREESITTER_FULL:-0}" = "1" ]; then
    echo "$TDE_TS_PARSERS_FULL"
  else
    echo "${TDE_TS_PARSERS:-$TDE_TS_PARSERS_CORE}"
  fi
}

_tde_nvim_headless() {
  local username
  username="$(state_get ARCH_USERNAME)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" --env TDE_SKIP_TS_ENSURE=1 -- nvim --headless "$@"
}

_tde_lazy_loaded() {
  local loaded
  loaded="$(_tde_nvim_headless -c "lua io.stdout:write(tostring(require('lazy').stats().loaded) .. '\n') io.stdout:flush()" -c "qa" 2>/dev/null | grep -E '^[0-9]+$' | tail -n1)" || true
  if [ -z "$loaded" ]; then
    loaded="$(_tde_nvim_headless -c "lua print(require('lazy').stats().loaded)" -c "qa" 2>&1 | grep -E '^[0-9]+$' | tail -n1)" || true
  fi
  echo "$loaded"
}

_tde_lazy_count() {
  local count
  count="$(_tde_nvim_headless -c "lua io.stdout:write(tostring(require('lazy').stats().count) .. '\n') io.stdout:flush()" -c "qa" 2>/dev/null | grep -E '^[0-9]+$' | tail -n1)" || true
  echo "$count"
}

phase4_setup_npm_global() {
  local username npm_global
  username="$(state_get ARCH_USERNAME)"
  npm_global="/home/$username/.npm-global"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c "
    npm config set prefix \"$npm_global\"
    npm config set allow-scripts=core-js --location=user 2>/dev/null || true
  " || log_fatal_code 431 "Could not configure npm global prefix"

  if [ "${TDE_PREINSTALL_NPM_LSP:-0}" = "1" ]; then
    log_info "Pre-installing global language servers via npm"
    proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
      npm install -g typescript eslint bash-language-server vscode-langservers-extracted @vtsls/language-server pyright || \
      log_warn "Global npm LSP pre-install had warnings — Mason will manage remaining servers"
  fi
}

phase4_clone_lazyvim_starter() {
  local username
  username="$(state_get ARCH_USERNAME)"

  if proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
       sh -c '[ -d ~/.config/nvim ] && [ ! -d ~/.config/nvim/.git ] && [ ! -f ~/.config/nvim/lua/plugins/example.lua ]' 2>/dev/null; then
    log_info "LazyVim config already present and clean, skipping starter clone"
    return 0
  fi

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- rm -rf "/home/$username/.config/nvim" 2>/dev/null || true
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    git clone --depth 1 "$TDE_LAZYVIM_STARTER_URL" "/home/$username/.config/nvim" || \
    log_fatal_code 432 "Could not clone LazyVim starter"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    sh -c 'rm -rf ~/.config/nvim/.git; rm -f ~/.config/nvim/lua/plugins/example.lua'
}

phase4_write_nvim_configs() {
  local username
  username="$(state_get ARCH_USERNAME)"

  # 1. Options tuned specifically for Termux Nerd Font rendering & UTF-8 alignment
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".config/nvim/lua/config/options.lua" "options" '
vim.g.have_nerd_font = true
vim.opt.termguicolors = true
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"
vim.opt.emoji = false
vim.opt.ambiwidth = "single"
vim.diagnostic.config({
  virtual_text = { spacing = 4, prefix = "●" },
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})
vim.opt.shell = "/usr/bin/zsh"' "--" || log_warn "Could not write options.lua overrides"

  # 2. Keymaps
  idempotent_append_container "$TDE_DISTRO_NAME" "$username" ".config/nvim/lua/config/keymaps.lua" "keymaps" '
vim.keymap.set("n", "<leader>lc", function()
  vim.cmd("write")
  vim.cmd("!tsc --noEmit %")
end, { desc = "Lint/type check (on-demand)" })

vim.keymap.set({ "n", "t" }, "<C-/>", function()
  if package.loaded["snacks"] and Snacks and Snacks.terminal then
    Snacks.terminal(nil, { shell = "/usr/bin/zsh" })
  else
    vim.cmd("terminal /usr/bin/zsh")
  end
end, { desc = "Toggle ZSH Terminal" })' "--" || log_warn "Could not write keymaps.lua overrides"

  # 3. Dynamic LSP list: only pulls heavy language servers if requested or installed
  local extra_servers="" extra_mason="" extra_mlsp=""
  if [ "${TDE_WITH_RUST:-0}" = "1" ] || proot-distro login "$TDE_DISTRO_NAME" -- command -v rustc >/dev/null 2>&1; then
    extra_servers="${extra_servers}        rust_analyzer = {},\n"
    extra_mason="${extra_mason}        \"rust-analyzer\",\n"
    extra_mlsp="${extra_mlsp}        \"rust_analyzer\",\n"
  fi
  if [ "${TDE_WITH_CLANG:-0}" = "1" ] || proot-distro login "$TDE_DISTRO_NAME" -- command -v clang >/dev/null 2>&1; then
    extra_servers="${extra_servers}        clangd = {},\n"
    extra_mason="${extra_mason}        \"clangd\",\n"
    extra_mlsp="${extra_mlsp}        \"clangd\",\n"
  fi
  if [ "${TDE_WITH_GO:-0}" = "1" ] || proot-distro login "$TDE_DISTRO_NAME" -- command -v go >/dev/null 2>&1; then
    extra_servers="${extra_servers}        gopls = {},\n"
    extra_mason="${extra_mason}        \"gopls\",\n"
    extra_mlsp="${extra_mlsp}        \"gopls\",\n"
  fi

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c '
    mkdir -p ~/.config/nvim/lua/plugins
    rm -f ~/.config/nvim/lua/plugins/no-lsp-completion.lua
  ' || log_fatal_code 433 "Could not prepare nvim plugins directory"

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    tee "/home/$username/.config/nvim/lua/plugins/lsp.lua" > /dev/null << EOF
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        underline = true,
        update_in_insert = false,
        virtual_text = { spacing = 4, source = "if_many", prefix = "●" },
        severity_sort = true,
      },
      servers = {
        bashls = {},
        marksman = {},
        pyright = {},
        ts_ls = {},
        vtsls = {},
        html = {},
        cssls = {},
        clangd = {
          mason = false,
          enabled = vim.fn.executable("clangd") == 1,
        },
$(printf '%b' "$extra_servers")      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ui = { border = "rounded" },
      ensure_installed = {
        "bash-language-server",
        "marksman",
        "pyright",
        "typescript-language-server",
        "html-lsp",
        "css-lsp",
$(printf '%b' "$extra_mason")      },
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
        "html",
        "cssls",
$(printf '%b' "$extra_mlsp")      },
      automatic_enable = true,
    },
  },
  {
    "saghen/blink.cmp",
    opts = {
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      completion = { ghost_text = { enabled = true }, menu = { auto_show = true } },
    },
  },
}
EOF

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- sh -c '
    cat > ~/.config/nvim/lua/plugins/terminal.lua << "EOF"
return {
  {
    "folke/snacks.nvim",
    opts = { terminal = { shell = "/usr/bin/zsh" } },
  },
}
EOF
    cat > ~/.config/nvim/lua/plugins/file-explorer.lua << "EOF"
return {
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },
  {
    "stevearc/oil.nvim",
    lazy = false,
    opts = { default_file_explorer = true, view_options = { show_hidden = true } },
    keys = { { "-", "<cmd>Oil<cr>", desc = "Open parent directory" } },
  },
}
EOF
    cat > ~/.config/nvim/lua/plugins/treesitter.lua << "EOF"
return {
  "nvim-treesitter/nvim-treesitter",
  opts = function(_, opts)
    if vim.env.TDE_SKIP_TS_ENSURE == "1" then
      opts.ensure_installed = {}
    end
  end,
}
EOF
  '
}

phase4_sync_plugins() {
  log_info "Syncing LazyVim plugins (headless)"
  _tde_nvim_headless -c "lua require('lazy').sync({wait = true})" -c "qa" || \
    log_fatal_code 434 "Lazy plugin sync failed"
}

phase4_install_treesitter_parsers() {
  local username lua_file lua_list="" p out missing parsers_to_install
  username="$(state_get ARCH_USERNAME)"
  lua_file="/home/$username/.cache/tde/ts_install.lua"
  parsers_to_install="$(_tde_resolve_ts_parsers)"

  for p in $parsers_to_install; do lua_list="${lua_list}'${p}',"; done

  log_info "Pre-installing Treesitter parsers ($(echo "$parsers_to_install" | wc -w) languages)"
  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- mkdir -p "/home/$username/.cache/tde" || return 0

  proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- \
    tee "$lua_file" > /dev/null << EOF || return 0
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

pcall(function() ts.install(want):wait(600000) end)

local m = missing()
if #m > 0 then
  for _, l in ipairs(m) do
    vim.fn.delete(vim.fn.stdpath('cache') .. '/tree-sitter-' .. l, 'rf')
  end
  pcall(function() ts.install(m):wait(300000) end)
  m = missing()
end

io.stdout:write('TS_MISSING=' .. table.concat(m, ',') .. '\n')
io.stdout:flush()
EOF

  out="$(_tde_nvim_headless -c "luafile $lua_file" -c "qa" 2>>"$TDE_LOG_FILE" | grep '^TS_MISSING=' | tail -n1)" || true
  missing="${out#TS_MISSING=}"
  if [ -z "$out" ]; then
    log_warn "Could not confirm Treesitter parser status — remaining parsers will auto-install on first file open"
  elif [ -n "$missing" ]; then
    log_warn "Treesitter parsers deferred to on-demand install: $missing"
  else
    log_info "All configured Treesitter parsers installed"
  fi
}

phase4_lazyvim_run() {
  log_info "=== Phase 4, step 4: LazyVim & LSP preconfiguration ==="

  if [ "${TDE_DRY_RUN:-0}" = "1" ]; then
    log_info "[dry-run] would configure npm global prefix, clone LazyVim starter, write Nerd Font-tuned options/keymaps/LSP specs, sync plugins, and compile Treesitter parsers"
    return 0
  fi

  phase4_setup_npm_global
  phase4_clone_lazyvim_starter
  phase4_write_nvim_configs
  phase4_sync_plugins
  phase4_install_treesitter_parsers
  log_info "LazyVim installed and preconfigured (loaded plugins: $(_tde_lazy_loaded))"
}

phase4_lazyvim_ok() {
  local username loaded count ok=1
  username="$(state_get ARCH_USERNAME)"
  [ -n "$username" ] || return 1

  if ! proot-distro login "$TDE_DISTRO_NAME" --user "$username" -- test -f "/home/$username/.config/nvim/lua/config/options.lua" 2>/dev/null; then
    log_warn "post-check: ~/.config/nvim/lua/config/options.lua missing"
    ok=0
  fi
  count="$(_tde_lazy_count)"
  if ! { [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -ge 10 ]; }; then
    log_warn "post-check: lazy.nvim registered only ${count:-0} plugins (expected >= 10)"
    ok=0
  fi
  loaded="$(_tde_lazy_loaded)"
  if ! { [[ "$loaded" =~ ^[0-9]+$ ]] && [ "$loaded" -gt 0 ]; }; then
    log_warn "post-check: could not read loaded plugin count from lazy.nvim"
    ok=0
  fi
  if ! proot-distro login "$TDE_DISTRO_NAME" -- sh -c 'command -v nvim >/dev/null 2>&1'; then
    log_warn "post-check: nvim binary not found on PATH"
    ok=0
  fi
  [ "$ok" = "1" ]
}