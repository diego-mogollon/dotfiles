ZSH=$HOME/.oh-my-zsh

# You can change the theme with another one from https://github.com/robbyrussell/oh-my-zsh/wiki/themes
ZSH_THEME="robbyrussell"

# Useful oh-my-zsh plugins for Le Wagon bootcamps
plugins=(git gitfast last-working-dir common-aliases zsh-syntax-highlighting history-substring-search direnv)

# (macOS-only) Prevent Homebrew from reporting - https://github.com/Homebrew/brew/blob/master/docs/Analytics.md
export HOMEBREW_NO_ANALYTICS=1

# Disable warning about insecure completion-dependent directories
ZSH_DISABLE_COMPFIX=true

# Actually load Oh-My-Zsh
source "${ZSH}/oh-my-zsh.sh"
unalias rm # No interactive rm by default (brought by plugins/common-aliases)
unalias lt # we need `lt` for https://github.com/localtunnel/localtunnel

# Load rbenv if installed (to manage your Ruby versions)
export PATH="${HOME}/.rbenv/bin:${PATH}" # Needed for Linux/WSL
type -a rbenv > /dev/null && eval "$(rbenv init -)"

# Load pyenv (to manage your Python versions)
export PYENV_VIRTUALENV_DISABLE_PROMPT=1
type -a pyenv > /dev/null && eval "$(pyenv init -)" && eval "$(pyenv virtualenv-init - 2> /dev/null)" && RPROMPT+='[🐍 $(pyenv version-name)]'
export PYENV_AUTO_ACTIVATE=false

# Load nvm (to manage your node versions)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Call `nvm use` automatically in a directory with a `.nvmrc` file
autoload -U add-zsh-hook
load-nvmrc() {
  if nvm -v &> /dev/null; then
    local node_version="$(nvm version)"
    local nvmrc_path="$(nvm_find_nvmrc)"

    if [ -n "$nvmrc_path" ]; then
      local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")

      if [ "$nvmrc_node_version" = "N/A" ]; then
        nvm install
      elif [ "$nvmrc_node_version" != "$node_version" ]; then
        nvm use --silent
      fi
    elif [ "$node_version" != "$(nvm version default)" ]; then
      nvm use default --silent
    fi
  fi
}
type -a nvm > /dev/null && add-zsh-hook chpwd load-nvmrc
type -a nvm > /dev/null && load-nvmrc

# Rails and Ruby uses the local `bin` folder to store binstubs.
# So instead of running `bin/rails` like the doc says, just run `rails`
# Same for `./node_modules/.bin` and nodejs
export PATH="./bin:./node_modules/.bin:${PATH}:/usr/local/sbin"

# Store your own aliases in the ~/.aliases file and load the here.
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# Encoding stuff for the terminal
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

export BUNDLER_EDITOR=code
export EDITOR=code

# Set ipdb as the default Python debugger
export PYTHONBREAKPOINT=ipdb.set_trace
# The next line updates PATH for the Google Cloud SDK.
if [ -f '/usr/local/share/google-cloud-sdk/path.zsh.inc' ]; then . '/usr/local/share/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/usr/local/share/google-cloud-sdk/completion.zsh.inc' ]; then . '/usr/local/share/google-cloud-sdk/completion.zsh.inc'; fi
export BUNDLER_EDITOR="'/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl' -a"
export BUNDLER_EDITOR="'/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl' -a"
export GOOGLE_APPLICATION_CREDENTIALS=/Users/diego_mogollon/code/diego-mogollon/GCP/le-wagon-429301-29967d0fed2b.json 

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/opt/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/opt/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

export PATH="$HOME/.local/bin:$PATH"

# Start Claude Code from a clean main hub. The launcher hard-stops (loudly)
# if the hub is dirty or off-main instead of silently launching on a stale
# branch. See almia/scripts/zsh/almia-launch.sh.
cc()  { source ~/code/diego-mogollon/almia/scripts/zsh/almia-launch.sh && _almia_launch plain; }

# Start Claude Code in an isolated worktree for parallel terminal safety.
# Same hub guard as cc; only launches once the hub is verified clean main.
ccw() { source ~/code/diego-mogollon/almia/scripts/zsh/almia-launch.sh && _almia_launch worktree; }

# ─── almia-checkout-guard (shell-side belt-and-suspenders) ──────────────────
# Refuses `git checkout`/`git restore` that would discard uncommitted changes
# in a TRACKED file — for git commands you type yourself, the path the Claude
# Code PreToolUse hook (.claude/hooks/checkout-guard.sh) cannot see.
#
# That hook is the canonical, CI-tested implementation; this is its human-path
# twin. Kept self-contained (not sourced from the repo) so it works in every
# repo on this machine and survives the repo moving — the two copies are <3
# instances, below the DRY refactor threshold, and the divergence risk is noted
# here on purpose.
#
# FAIL-OPEN by design: any uncertainty or error falls through to real git, so
# this can never break your git. To deliberately discard, bypass the function:
#     command git checkout -- <file>
git() {
  emulate -L zsh

  local sub="${1:-}"
  # Instant passthrough for everything that isn't a working-tree restore.
  if [[ "$sub" != checkout && "$sub" != restore ]]; then
    command git "$@"; return
  fi
  command git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { command git "$@"; return }

  local -a operands=("${@[2,-1]}")   # everything after the subcommand
  local saw_dd=0 pre_path=0 expl_src=0 staged=0 worktree=0 skip=0 safe=0
  local -a cands=()
  local t
  for t in "${operands[@]}"; do
    if (( skip )); then skip=0; continue; fi
    if [[ "$t" == "--" ]]; then saw_dd=1; continue; fi
    if (( saw_dd )); then cands+="$t"; continue; fi
    case "$t" in
      -b|-B)        safe=1; break ;;                 # branch creation, not a restore
      --staged|-S)  staged=1 ;;
      --worktree|-W) worktree=1 ;;
      -s|--source)  expl_src=1; skip=1 ;;            # next operand is a tree-ish
      --source=*)   expl_src=1 ;;
      -*)           ;;                               # any other flag: ignore
      *)            pre_path=1; cands+="$t" ;;        # tree-ish or pathspec
    esac
  done

  (( safe )) && { command git "$@"; return }
  # `git restore --staged` without `--worktree` only rewrites the index — safe.
  [[ "$sub" == restore ]] && (( staged )) && (( ! worktree )) && { command git "$@"; return }
  # checkout from a named tree (`git checkout <tree> -- <paths>`) also overwrites staged work.
  [[ "$sub" == checkout ]] && (( saw_dd )) && (( pre_path )) && expl_src=1
  (( ${#cands} == 0 )) && { command git "$@"; return }

  local -a dirty=()
  local c rc
  for c in "${cands[@]}"; do
    command git ls-files --error-unmatch -- "$c" >/dev/null 2>&1 || continue   # not tracked → skip
    command git diff --quiet -- "$c" 2>/dev/null; rc=$?
    (( rc == 1 )) && { dirty+="$c"; continue }                                  # unstaged changes
    if (( expl_src )); then
      command git diff --cached --quiet -- "$c" 2>/dev/null
      (( $? == 1 )) && { dirty+="$c"; continue }                               # staged-but-uncommitted
    fi
    # rc>1 (an error) falls through unflagged: fail-open.
  done

  if (( ${#dirty} > 0 )); then
    print -u2 "CHECKOUT GUARD (shell): refused 'git $*'"
    print -u2 "  this would discard uncommitted changes in:"
    local f; for f in "${dirty[@]}"; do print -u2 "    $f"; done
    print -u2 "  keep them:   git stash push -- ${dirty[1]}   (recover with 'git stash pop')"
    print -u2 "  or commit:   git add <file> && git commit -m '...'"
    print -u2 "  discard anyway (bypass this guard):   command git $*"
    return 2
  fi

  command git "$@"
}
# ─── end almia-checkout-guard ───────────────────────────────────────────────
