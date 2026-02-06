#!/usr/bin/bash
set -eo pipefail
set -m

# Check if docker is running
response_code=$(
  curl -s -o /dev/null -w "%{http_code}" --unix-socket /var/run/docker.sock http://localhost/_ping || true
)
if [ "$response_code" == "000" ]; then
  docker_running=$(powershell.exe -nologo -command "Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'")
  until [ "$(
    curl -s -o /dev/null -w "%{http_code}" --unix-socket /var/run/docker.sock http://localhost/_ping || true
  )" = "200" ]; do
    sleep 1
  done

  # killing the kind container (used for Devops testing)
  docker ps --format '{{.ID}}' | xargs -r docker kill 2>/dev/null
fi

exit 0
