#!/usr/bin/bash
set -eo pipefail

# Start a new tmux session
tmux new-session -d -s mae_session -c $MAE_DIR "nvim ."
# Split the window vertically
tmux split-window -t mae_session:0.0 -h -c $MAE_DIR 'echo "Initializing DB..." && scripts/init_db.sh > /dev/null && cargo watch -c -x check -x "test -- --show-output --nocapture"'
# Split the window horizontally
tmux split-window -t mae_session:0 -v -c $MAE_DIR

# make the nvim pane larger
tmux resize-pane -t mae_session:0.0 -R 70
tmux resize-pane -t mae_session:0.1 -D 15

# focus to nvim
tmux select-window -t mae_session:0
tmux select-pane -t mae_session:0

wait
exit 0
