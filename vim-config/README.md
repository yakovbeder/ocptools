# Vim Configuration Setup

This directory contains Vim configuration files and setup instructions.

## Installation Steps

### 1. Install Pathogen (Plugin Manager for Vim)

```bash
mkdir -p ~/.vim/autoload ~/.vim/bundle && \
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
```

### 2. Install Plugins

```bash
cd ~/.vim/bundle
git clone https://github.com/dense-analysis/ale.git          # linting
git clone https://github.com/pearofducks/ansible-vim.git     # Ansible syntax
git clone https://github.com/Yggdroot/indentLine.git         # indent guides
git clone https://github.com/morhetz/gruvbox.git             # colorscheme
git clone https://github.com/pedrohdz/vim-yaml-folds.git     # YAML folding
```

### 3. Install yamllint

```bash
pip3 install --user yamllint
```

Make sure `~/.local/bin` is on your PATH (add to `~/.bashrc` or `~/.zshrc`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 4. Configure Vim

Copy the `vimrc` file to your home directory:

```bash
cp vimrc ~/.vimrc
```

### 5. Configure yamllint

Copy the `yammlint-config` file to the yamllint configuration directory:

```bash
mkdir -p ~/.config/yamllint
cp yammlint-config ~/.config/yamllint/config
```

## Files Included

- `vimrc` - Vim configuration file
- `yammlint-config` - yamllint configuration file
- `README.md` - This setup guide
