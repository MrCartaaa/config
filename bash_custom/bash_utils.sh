
# --- SSH agent (prompt once per login) ---
# Uses keychain to start/reuse ssh-agent across terminals.
if [[ $- == *i* ]]; then
  if command -v keychain >/dev/null 2>&1; then
    # Use your GitHub key; add more keys if needed.
    eval "$(keychain --eval --quiet ~/.ssh/github ~/.ssh/main-server ~/.ssh/ai-machine)"
  fi
fi

# completion
[[ -r /usr/share/bash-completion/bash_completion ]] && \
  . /usr/share/bash-completion/bash_completion

# WARN: eval direnv and zoxide OVERRIDE our eval starship; this causes bugs preventing starship from rendering at each prompt
# keep these evals above out starship ble.sh handling
# env
eval "$(direnv hook bash)"

# cd
eval "$(zoxide init bash)"

# Load ble.sh (do not attach yet)
if [[ -r /usr/share/blesh/ble.sh ]]; then
  source /usr/share/blesh/ble.sh --noattach
fi

# Init starship
eval "$(starship init bash)"

# Attach ble after starship
if declare -F ble-attach >/dev/null; then
  ble-attach
fi

# fzf
source /usr/share/fzf/key-bindings.bash
source /usr/share/fzf/completion.bash
