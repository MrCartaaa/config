#!/usr/bin/bash
set -eo pipefail

# Start a new tmux session
tmux new-session -d -s merchant_service_session -c $MERCHANT_SERVICE_DIR "nvim ."
# Name the window
tmux rename-window -t merchant_service_session main

# Attach Mae Service
~/.zsh_custom/scripts/sessions/mae_library.sh >/dev/null
wait
tmux move-window -d -s mae_session:0 -t merchant_service_session

# Run the Sidecar for Merchant Service to Operate Properly
tmux new-window -t merchant_service_session: -n sidecar -c $MERCHANT_SERVICE_SIDECAR_DIR "bash scripts/init_db.sh && bash scripts/init_redis.sh && cargo run"

# wait for the sidecar to be up
until [ "$(
  curl -s -o /dev/null -w "%{http_code}" -X GET 127.0.0.1:8000/health_check || true
)" = "200" ]; do
  sleep 1
done

# initializing db
$MERCHANT_SERVICE_DIR/scripts/init_db.sh &>dev/null || true
wait

tmux select-window -t merchant_service_session:'main'
# Split the window vertically
tmux split-window -t merchant_service_session:'main'.0 -h -c $MERCHANT_SERVICE_DIR 'cargo watch -c -x check -x "test -- --show-output --nocapture"'
# Split the window horizontally
tmux split-window -t merchant_service_session:'main'.1 -v -c $MERCHANT_SERVICE_DIR

# Focus to nvim
tmux select-pane -t merchant_service_session:'main'.0

# make the nvim pane larger
tmux resize-pane -t merchant_service_session:'main'.0 -R 70
tmux resize-pane -t merchant_service_session:'main'.1 -D 15

tmux rename-window -t merchant_service_session:0 mae_lib

wait
exit 0
