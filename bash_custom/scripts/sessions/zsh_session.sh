#!/usr/bin/bash
set -eo pipefail

# Start a new tmux session
tmux new-session -d -s zsh_session -c $ZSH_DIR "nvim ."

# Split the window vertically
tmux split-window -t zsh_session -h -c $ZSH_DIR
tmux resize-pane -t zsh_session.0 -R 70
# Focus to nvim
tmux select-pane -t zsh_session.0

wait
