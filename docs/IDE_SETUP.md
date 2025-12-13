# IDE Setup Guide

Configuration guides for popular IDEs and editors to work with DevStack Core, including VS Code, JetBrains IDEs, and Neovim.

## Table of Contents

- [Overview](#overview)
- [Visual Studio Code](#visual-studio-code)
- [IntelliJ IDEA / PyCharm](#intellij-idea-pycharm)
- [GoLand](#goland)
- [Neovim / Vim](#neovim-vim)
- [Common Tools](#common-tools)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide helps you configure your IDE for optimal development with the DevStack Core project. Each section covers:
- Required extensions/plugins
- Recommended settings
- Debugging configuration
- Language-specific setup

**Supported Languages:**
- Python (FastAPI)
- Go (Gin)
- JavaScript/TypeScript (Node.js, TypeScript)
- Rust (Actix-web)
- Shell scripts (Bash)

---

## Visual Studio Code

### Installation

```bash
# macOS
brew install --cask visual-studio-code

# Or download from https://code.visualstudio.com/
```

### Required Extensions

Install via VS Code Extensions marketplace or command line:

```bash
# Python
code --install-extension ms-python.python
code --install-extension ms-python.vscode-pylance
code --install-extension ms-python.black-formatter
code --install-extension charliermarsh.ruff

# Go
code --install-extension golang.go

# JavaScript/TypeScript/Node.js
code --install-extension dbaeumer.vscode-eslint
code --install-extension esbenp.prettier-vscode

# Rust
code --install-extension rust-lang.rust-analyzer
code --install-extension vadimcn.vscode-lldb

# Docker
code --install-extension ms-azuretools.vscode-docker

# YAML (docker-compose)
code --install-extension redhat.vscode-yaml

# Markdown
code --install-extension yzhang.markdown-all-in-one
code --install-extension DavidAnson.vscode-markdownlint

# Git
code --install-extension eamodio.gitlens

# Shell Script
code --install-extension timonwong.shellcheck
code --install-extension foxundermoon.shell-format

# HashiCorp (Vault)
code --install-extension hashicorp.hcl

# REST Client (for testing APIs)
code --install-extension humao.rest-client
```

### Workspace Settings

Create `.vscode/settings.json` in the project root:

```json
{
  // Python
  "python.defaultInterpreterPath": "/usr/local/bin/python3",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": false,
  "python.linting.flake8Enabled": true,
  "python.formatting.provider": "black",
  "python.analysis.typeCheckingMode": "basic",
  "python.analysis.autoImportCompletions": true,

  // Go
  "go.useLanguageServer": true,
  "go.lintTool": "golangci-lint",
  "go.lintOnSave": "package",
  "go.formatTool": "goimports",
  "go.testFlags": ["-v"],

  // JavaScript/TypeScript
  "typescript.tsdk": "node_modules/typescript/lib",
  "eslint.enable": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  },
  "editor.defaultFormatter": "esbenp.prettier-vscode",

  // Rust
  "rust-analyzer.checkOnSave.command": "clippy",
  "rust-analyzer.cargo.features": "all",

  // Docker
  "docker.showStartPage": false,

  // YAML
  "yaml.schemas": {
    "https://json.schemastore.org/docker-compose.json": "docker-compose.yml"
  },

  // Editor
  "editor.formatOnSave": true,
  "editor.rulers": [100, 120],
  "editor.tabSize": 4,
  "editor.insertSpaces": true,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,

  // File Associations
  "files.associations": {
    "*.env.example": "properties",
    "Dockerfile*": "dockerfile",
    "*.sh": "shellscript"
  },

  // Exclude from file explorer
  "files.exclude": {
    "**/__pycache__": true,
    "**/*.pyc": true,
    "**/.pytest_cache": true,
    "**/node_modules": true,
    "**/target": true
  }
}
```

### Debugging Configuration

Create `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Python: FastAPI (Code-First)",
      "type": "python",
      "request": "launch",
      "module": "uvicorn",
      "args": [
        "app.main:app",
        "--reload",
        "--host", "0.0.0.0",
        "--port", "8000"
      ],
      "cwd": "${workspaceFolder}/reference-apps/fastapi",
      "env": {
        "PYTHONPATH": "${workspaceFolder}/reference-apps/fastapi",
        "DEBUG": "true",
        "VAULT_ADDR": "http://localhost:8200",
        "VAULT_TOKEN": "${env:VAULT_TOKEN}"
      },
      "console": "integratedTerminal",
      "justMyCode": false
    },
    {
      "name": "Python: FastAPI (API-First)",
      "type": "python",
      "request": "launch",
      "module": "uvicorn",
      "args": [
        "app.main:app",
        "--reload",
        "--host", "0.0.0.0",
        "--port", "8001"
      ],
      "cwd": "${workspaceFolder}/reference-apps/fastapi-api-first",
      "env": {
        "PYTHONPATH": "${workspaceFolder}/reference-apps/fastapi-api-first",
        "DEBUG": "true",
        "VAULT_ADDR": "http://localhost:8200",
        "VAULT_TOKEN": "${env:VAULT_TOKEN}"
      },
      "console": "integratedTerminal"
    },
    {
      "name": "Go: API",
      "type": "go",
      "request": "launch",
      "mode": "debug",
      "program": "${workspaceFolder}/reference-apps/golang/cmd/api",
      "cwd": "${workspaceFolder}/reference-apps/golang",
      "env": {
        "DEBUG": "true",
        "VAULT_ADDR": "http://localhost:8200",
        "VAULT_TOKEN": "${env:VAULT_TOKEN}",
        "HTTP_PORT": "8002"
      },
      "showLog": true
    },
    {
      "name": "Node.js: API",
      "type": "node",
      "request": "launch",
      "program": "${workspaceFolder}/reference-apps/nodejs/src/index.js",
      "cwd": "${workspaceFolder}/reference-apps/nodejs",
      "env": {
        "DEBUG": "true",
        "VAULT_ADDR": "http://localhost:8200",
        "VAULT_TOKEN": "${env:VAULT_TOKEN}",
        "HTTP_PORT": "8003"
      },
      "console": "integratedTerminal"
    },
    {
      "name": "Rust: API",
      "type": "lldb",
      "request": "launch",
      "program": "${workspaceFolder}/reference-apps/rust/target/debug/devstack-core-rust-api",
      "cwd": "${workspaceFolder}/reference-apps/rust",
      "env": {
        "RUST_LOG": "debug",
        "VAULT_ADDR": "http://localhost:8200",
        "VAULT_TOKEN": "${env:VAULT_TOKEN}"
      },
      "preLaunchTask": "cargo build"
    },
    {
      "name": "Python: Attach to Container",
      "type": "python",
      "request": "attach",
      "connect": {
        "host": "localhost",
        "port": 5678
      },
      "pathMappings": [
        {
          "localRoot": "${workspaceFolder}/reference-apps/fastapi",
          "remoteRoot": "/app"
        }
      ]
    }
  ]
}
```

### Tasks Configuration

Create `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Start DevStack Core",
      "type": "shell",
      "command": "./devstack.sh start",
      "problemMatcher": [],
      "group": "build"
    },
    {
      "label": "Stop DevStack Core",
      "type": "shell",
      "command": "./devstack.sh stop",
      "problemMatcher": []
    },
    {
      "label": "Check Services Health",
      "type": "shell",
      "command": "./devstack.sh health",
      "problemMatcher": []
    },
    {
      "label": "Run All Tests",
      "type": "shell",
      "command": "./tests/run-all-tests.sh",
      "problemMatcher": [],
      "group": {
        "kind": "test",
        "isDefault": true
      }
    },
    {
      "label": "cargo build",
      "type": "shell",
      "command": "cargo",
      "args": ["build"],
      "cwd": "${workspaceFolder}/reference-apps/rust",
      "problemMatcher": ["$rustc"]
    },
    {
      "label": "Load Vault Token",
      "type": "shell",
      "command": "export VAULT_TOKEN=$(cat ~/.config/vault/root-token)",
      "problemMatcher": []
    }
  ]
}
```

### Snippets

Create `.vscode/snippets.code-snippets`:

```json
{
  "FastAPI Endpoint": {
    "prefix": "fastapi-endpoint",
    "body": [
      "@router.${1:get}(\"/${2:path}\")",
      "async def ${3:function_name}(",
      "    ${4:param}: ${5:str}",
      ") -> ${6:dict}:",
      "    \"\"\"",
      "    ${7:Description}",
      "    \"\"\"",
      "    ${8:# Implementation}",
      "    return {\"status\": \"success\"}",
      ""
    ],
    "description": "FastAPI endpoint template"
  },
  "Vault Secret Fetch": {
    "prefix": "vault-fetch",
    "body": [
      "credentials = await vault_client.get_secret(\"${1:service_name}\")",
      "${2:username} = credentials[\"${3:user}\"]",
      "${4:password} = credentials[\"${5:password}\"]"
    ],
    "description": "Fetch credentials from Vault"
  }
}
```

### Keyboard Shortcuts

Recommended shortcuts for productivity:

| Action | Shortcut |
|--------|----------|
| Open Command Palette | `Cmd+Shift+P` |
| Quick Open File | `Cmd+P` |
| Toggle Terminal | `Ctrl+`` |
| Start Debugging | `F5` |
| Run Tests | `Cmd+Shift+T` |
| Format Document | `Shift+Alt+F` |
| Go to Definition | `F12` |
| Find All References | `Shift+F12` |

---

## IntelliJ IDEA / PyCharm

### Installation

```bash
# IntelliJ IDEA Community Edition
brew install --cask intellij-idea-ce

# PyCharm Community Edition
brew install --cask pycharm-ce

# Or Professional versions
brew install --cask intellij-idea
brew install --cask pycharm
```

### Required Plugins

**Settings → Plugins → Marketplace:**

1. **Python** (PyCharm has built-in)
2. **Go** (if using IntelliJ IDEA)
3. **Docker**
4. **.env files support**
5. **Rust** (IntelliJ Rust)
6. **Markdown**
7. **Shell Script**
8. **YAML/Ansible**
9. **HashiCorp Terraform / HCL**

### Project Configuration

#### Python Interpreter Setup (PyCharm)

1. **File → Settings → Project → Python Interpreter**
2. Click gear icon → **Add**
3. Select **System Interpreter** → `/usr/local/bin/python3`
4. Or create **virtualenv** for each reference app:
   ```bash
   cd reference-apps/fastapi
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

#### Go SDK Setup (IntelliJ IDEA)

1. **File → Settings → Go → GOROOT**
2. Select Go SDK location: `/usr/local/go` or output of `which go`
3. **File → Settings → Go → GOPATH**
4. Add workspace: `~/go`

#### Project Structure

1. **File → Project Structure**
2. Mark directories:
   - `reference-apps/fastapi` → **Sources Root** (Python)
   - `reference-apps/golang` → **Sources Root** (Go)
   - `reference-apps/nodejs` → **Sources Root** (JavaScript)
   - `tests/` → **Test Sources Root**
   - `docs/` → **Excluded**

### Run/Debug Configurations

#### FastAPI Configuration

1. **Run → Edit Configurations → + → Python**
2. **Configuration:**
   - Name: `FastAPI Code-First`
   - Module: `uvicorn`
   - Parameters: `app.main:app --reload --host 0.0.0.0 --port 8000`
   - Working directory: `reference-apps/fastapi`
   - Environment variables:
     ```
     DEBUG=true
     VAULT_ADDR=http://localhost:8200
     VAULT_TOKEN=<from ~/.config/vault/root-token>
     ```

#### Go API Configuration

1. **Run → Edit Configurations → + → Go Build**
2. **Configuration:**
   - Name: `Go API`
   - Run kind: **Package**
   - Package path: `github.com/normbrandinger/devstack-core/reference-apps/golang/cmd/api`
   - Working directory: `reference-apps/golang`
   - Environment:
     ```
     DEBUG=true
     VAULT_ADDR=http://localhost:8200
     VAULT_TOKEN=<token>
     HTTP_PORT=8002
     ```

#### Node.js Configuration

1. **Run → Edit Configurations → + → Node.js**
2. **Configuration:**
   - Name: `Node.js API`
   - Node interpreter: `/usr/local/bin/node`
   - Working directory: `reference-apps/nodejs`
   - JavaScript file: `src/index.js`
   - Environment:
     ```
     DEBUG=true
     VAULT_ADDR=http://localhost:8200
     VAULT_TOKEN=<token>
     ```

### Code Style Settings

**File → Settings → Editor → Code Style**

**Python:**
- Line length: 100
- Use tabs: No (4 spaces)
- Follow PEP 8

**Go:**
- Use gofmt
- Line length: 120
- Use tabs: Yes

**JavaScript/TypeScript:**
- Line length: 100
- Indent: 2 spaces
- Use semicolons: Yes

### Docker Integration

1. **File → Settings → Build, Execution, Deployment → Docker**
2. Click **+** → **Docker for Mac**
3. Connection successful: Green checkmark
4. Now you can:
   - View running containers
   - View logs
   - Execute commands in containers
   - Manage docker-compose files

### Database Tool Window

1. **View → Tool Windows → Database**
2. **+ → Data Source → PostgreSQL**
3. Configure:
   - Host: `localhost`
   - Port: `5432`
   - Database: `dev_database`
   - User: `dev_admin`
   - Password: `<from Vault: vault kv get -field=password secret/postgres>`
4. Test Connection → OK
5. Repeat for MySQL (port 3306) and MongoDB (port 27017)

---

## GoLand

GoLand is JetBrains' dedicated Go IDE with excellent support.

### Installation

```bash
brew install --cask goland
```

### Configuration

Similar to IntelliJ IDEA Go setup above, but with enhanced Go-specific features:

1. **GOROOT**: Automatically detected
2. **GOPATH**: `~/go`
3. **Go Modules**: Enabled (project uses `go.mod`)
4. **Vendor mode**: Disabled (using modules)

### Debugging Go Services

1. Set breakpoint in code
2. **Run → Debug 'Go API'**
3. Debugger attaches to process
4. Inspect variables, step through code

### Go-Specific Features

- **Quick fixes** for common errors
- **Generate** test functions
- **Extract** functions/methods
- **Inline** variables
- **Rename** refactoring (safe across project)
- **Find usages** of symbols
- **Go to implementation**

---

## Neovim / Vim

For terminal-based development with modern features.

### Installation

```bash
# Neovim
brew install neovim

# Or build from source
git clone https://github.com/neovim/neovim.git
cd neovim && make CMAKE_BUILD_TYPE=Release
sudo make install
```

### Plugin Manager (packer.nvim)

```bash
git clone --depth 1 https://github.com/wbthomason/packer.nvim \
  ~/.local/share/nvim/site/pack/packer/start/packer.nvim
```

### Configuration (`~/.config/nvim/init.lua`)

```lua
-- Packer plugin manager
require('packer').startup(function(use)
  use 'wbthomason/packer.nvim'

  -- LSP
  use 'neovim/nvim-lspconfig'
  use 'williamboman/mason.nvim'
  use 'williamboman/mason-lspconfig.nvim'

  -- Autocompletion
  use 'hrsh7th/nvim-cmp'
  use 'hrsh7th/cmp-nvim-lsp'
  use 'hrsh7th/cmp-buffer'
  use 'hrsh7th/cmp-path'
  use 'L3MON4D3/LuaSnip'

  -- Treesitter
  use {'nvim-treesitter/nvim-treesitter', run = ':TSUpdate'}

  -- File explorer
  use 'nvim-tree/nvim-tree.lua'
  use 'nvim-tree/nvim-web-devicons'

  -- Fuzzy finder
  use {'nvim-telescope/telescope.nvim', requires = {'nvim-lua/plenary.nvim'}}

  -- Git integration
  use 'lewis6991/gitsigns.nvim'
  use 'tpope/vim-fugitive'

  -- Status line
  use 'nvim-lualine/lualine.nvim'

  -- Color scheme
  use 'folke/tokyonight.nvim'

  -- Go support
  use 'fatih/vim-go'

  -- Python
  use 'psf/black'

  -- Docker
  use 'ekalinin/Dockerfile.vim'
end)

-- LSP configuration
require('mason').setup()
require('mason-lspconfig').setup({
  ensure_installed = {
    'pyright',      -- Python
    'gopls',        -- Go
    'ts_ls',        -- TypeScript
    'rust_analyzer', -- Rust
    'bashls',       -- Bash
    'yamlls',       -- YAML
  }
})

local lspconfig = require('lspconfig')

-- Python
lspconfig.pyright.setup{}

-- Go
lspconfig.gopls.setup{
  settings = {
    gopls = {
      analyses = {
        unusedparams = true,
      },
      staticcheck = true,
    },
  },
}

-- TypeScript/JavaScript
lspconfig.ts_ls.setup{}

-- Rust
lspconfig.rust_analyzer.setup{}

-- Bash
lspconfig.bashls.setup{}

-- YAML
lspconfig.yamlls.setup{}

-- Basic settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 50
vim.opt.colorcolumn = "100"

-- Color scheme
vim.cmd[[colorscheme tokyonight]]

-- Key mappings
vim.g.mapleader = " "
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>")
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>")
```

### Language Servers Setup

```bash
# Install via Mason (inside neovim)
:Mason
# Then install: pyright, gopls, typescript-language-server, rust-analyzer, bash-language-server
```

### Key Bindings

| Action | Keybinding |
|--------|------------|
| File explorer | `Space + pv` |
| Find files | `Space + ff` |
| Live grep | `Space + fg` |
| Buffers | `Space + fb` |
| Go to definition | `gd` |
| Hover docs | `K` |
| Code actions | `Space + ca` |
| Format | `Space + f` |

---

## Common Tools

### Git Configuration

```bash
# Configure Git
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# GPG signing
git config --global user.signingkey <your-gpg-key-id>
git config --global commit.gpgsign true

# Default branch
git config --global init.defaultBranch main

# Editor
git config --global core.editor "code --wait"  # VS Code
# or
git config --global core.editor "nvim"  # Neovim
```

### Docker Desktop / Colima

```bash
# Check Docker is accessible
docker ps

# If using Colima
colima status

# Set context (if needed)
docker context use colima
```

### Vault CLI

```bash
# Set environment
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Add to ~/.zshrc or ~/.bashrc
echo 'export VAULT_ADDR=http://localhost:8200' >> ~/.zshrc
echo 'alias vault-token="export VAULT_TOKEN=\$(cat ~/.config/vault/root-token)"' >> ~/.zshrc
```

### Terminal Setup (zsh/bash)

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# DevStack Core aliases
alias ds-start="cd ~/devstack-core && ./devstack.sh start"
alias ds-stop="cd ~/devstack-core && ./devstack.sh stop"
alias ds-status="cd ~/devstack-core && ./devstack.sh status"
alias ds-health="cd ~/devstack-core && ./devstack.sh health"
alias ds-logs="cd ~/devstack-core && ./devstack.sh logs"

# Vault
alias vault-login="export VAULT_TOKEN=\$(cat ~/.config/vault/root-token)"
alias vault-pg="vault kv get secret/postgres"

# Docker
alias dc="docker compose"
alias dps="docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

---

## Troubleshooting

### Python Import Errors in VS Code

**Problem:** "Import could not be resolved"

**Solution:**
```bash
# Ensure Python path is set correctly
# In VS Code: Cmd+Shift+P → Python: Select Interpreter
# Choose the interpreter with installed packages

# Or install packages in current environment
cd reference-apps/fastapi
pip install -r requirements.txt
```

### Go Module Errors

**Problem:** "Could not import package"

**Solution:**
```bash
cd reference-apps/golang
go mod download
go mod tidy

# In VS Code/GoLand: reload Go modules
```

### Docker Connection Issues

**Problem:** "Cannot connect to Docker daemon"

**Solution:**
```bash
# Check Colima is running
colima status

# Start if stopped
colima start

# Set Docker context
docker context use colima
```

### Debugger Won't Attach

**Problem:** Breakpoints not hitting

**Solution:**
1. Ensure service is running in debug mode
2. Check port is correct in launch.json
3. For Python: ensure `debugpy` is installed
4. For Go: ensure `-gcflags="all=-N -l"` is set

### LSP Not Working (Neovim)

**Problem:** No autocompletion or diagnostics

**Solution:**
```bash
# Check LSP is running
:LspInfo

# Restart LSP
:LspRestart

# Reinstall language server
:Mason
# Select server → Uninstall → Install
```

---

## Additional Resources

- [VS Code Documentation](https://code.visualstudio.com/docs)
- [IntelliJ IDEA Help](https://www.jetbrains.com/help/idea/)
- [Neovim Documentation](https://neovim.io/doc/)
- [LSP Servers](https://microsoft.github.io/language-server-protocol/implementors/servers/)

---

## Quick Setup Script

Save as `setup-ide.sh`:

```bash
#!/bin/bash
# Quick IDE setup for DevStack Core

# VS Code extensions
if command -v code &> /dev/null; then
  echo "Installing VS Code extensions..."
  code --install-extension ms-python.python
  code --install-extension golang.go
  code --install-extension dbaeumer.vscode-eslint
  code --install-extension rust-lang.rust-analyzer
  code --install-extension ms-azuretools.vscode-docker
  code --install-extension redhat.vscode-yaml
fi

# Create .vscode directory
mkdir -p .vscode

# Set Vault token
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

echo "IDE setup complete!"
echo "Next steps:"
echo "1. Open project in your IDE"
echo "2. Configure Python/Go interpreters"
echo "3. Run 'Start DevStack Core' task"
echo "4. Start debugging!"
```

Run with:
```bash
chmod +x setup-ide.sh
./setup-ide.sh
```
