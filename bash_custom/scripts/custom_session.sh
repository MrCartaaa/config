#!/usr/bin/bash
set -eo pipefail
set -m

# find options
kill=false
while getopts :k opt; do
  case $opt in
  # h)
  #   show_some_help
  #   exit
  #   ;;
  k) kill=true ;;
  :)
    echo "Missing argument for option -$OPTARG"
    exit 1
    ;;
  \?)
    echo "Unknown option -$OPTARG"
    exit 1
    ;;
  esac
done

# remove the parsed options from the positional params
shift $((OPTIND - 1))

allowed_projects="\n\tAllowed projects:\n\t\t- mae\n\t\t- merchant_service\n"
if [ -z "$1" ]; then
  printf "\nError: a project must be provided.\n"
  printf "%b" "$allowed_projects"
  exit 1
fi

project=$1

if [ "$project" == "mae_lib" ]; then

  if $kill; then

    tmux switch -t home
    # Clean up from the session
    # hide cursor
    tput civis
    clear
    echo "🐋  killing docker containers..."
    # once we exit, kill the docker sessions and make sure the tmux-session is killed
    docker kill $(docker ps --filter 'name=mae_service' --format '{{.ID}}') &>/dev/null || true
    tmux kill-session -t mae_session &>/dev/null || true
    clear
    echo "👋  Exited Mae Library Session."

    # show cursor
    tput cnorm
  else
    clear
    # hide cursor
    tput civis

    # Check if Docker is running
    ~/.zsh_custom/scripts/loading_spinner.sh "🐋  Starting Docker" ~/.zsh_custom/scripts/check_start_docker.sh
    wait
    printf "\n🐳  Docker is up and running."

    # switch to the tmux session
    ~/.zsh_custom/scripts/loading_spinner.sh "\n📘  Initializing Mae Library" ~/.zsh_custom/scripts/sessions/mae_library.sh
    #switch to session
    tput cnorm
    tmux switch -t mae_session
  fi
  exit 0
fi

if [ "$project" == "merchant_service" ]; then
  if $kill; then
    tmux switch -t home
    # Clean up from the session
    # hide cursor
    tput civis
    clear
    # once we exit, kill the docker sessions and make sure the tmux-session is killed
    ~/.zsh_custom/scripts/loading_spinner.sh "🐋  killing docker containers" sleep 3 &
    docker kill $(docker ps --filter 'name=merchant_service' --format '{{.ID}}') &>/dev/null || true
    tmux kill-session -t merchant_service_session &>/dev/null || true &
    # we're also going to kill Mae Session as we're depending on it
    docker kill $(docker ps --filter 'name=mae_service' --format '{{.ID}}') &>/dev/null || true &
    tmux kill-session -t mae_session &>/dev/null || true

    wait

    clear
    echo "👋  Exited Merchant Service Session."

    # show cursor
    tput cnorm
  else
    clear
    # hide cursor
    tput civis

    # Check if Docker is running
    ~/.zsh_custom/scripts/loading_spinner.sh "🐋  Starting Docker" ~/.zsh_custom/scripts/check_start_docker.sh
    wait
    printf "🐳  Docker is up and running.\n"

    # switch to the tmux session
    ~/.zsh_custom/scripts/loading_spinner.sh "\n💻  Initializing Merchant Service" ~/.zsh_custom/scripts/sessions/merchant_service.sh
    # switch to session
    tput cnorm
    tmux switch -t merchant_service_session
  fi
  exit 0
fi

if [ "$project" == "zsh_config" ]; then
  if $kill; then
    clear
    tmux switch -t home
    tmux kill-session -t zsh_session &>/dev/null || true
    clear
    echo "👋  Exited Zsh Configuration Session."
  else
    clear
    # hide cursor
    tput civis
    # switch to the tmux session
    ~/.zsh_custom/scripts/loading_spinner.sh "\n🛠️  Initializing Zsh Configuration Session" ~/.zsh_custom/scripts/sessions/zsh_session.sh
    # show cursor
    tput cnorm
    # switch to session
    tmux switch -t zsh_session
  fi
  exit 0
fi

if [ "$project" == "ng-statbook" ]; then
  if $kill; then
    clear
    tmux switch -t home
    tmux kill-session -t ng_statbook &>/dev/null || true
    clear
    echo "👋  Exited Statbook Angular Session."
  else
    clear
    tput civis
    ~/.zsh_custom/scripts/loading_spinner.sh "\n🛠️  Initializing Statbook Angular Session" ~/.zsh_custom/scripts/sessions/ng_statbook.sh
    tput cnorm
    tmux switch -t ng_statbook_session
  fi
  exit 0
fi

printf "\nError: a project must be provided.\n"
printf "%b" "$allowed_projects"
exit 1
