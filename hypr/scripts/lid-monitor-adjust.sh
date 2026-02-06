#!/usr/bin/env bash
set -euo pipefail

# Requires: jq
# Detect internal and external monitors from Hyprland JSON
internal="$(hyprctl monitors -j | jq -r '.[] | select(.name | test("^eDP")) | .name' | head -n1)"
target_external="$(hyprctl monitors -j | jq -r '.[] | select(.name | test("^eDP") | not) | .name' | head -n1)"

is_docked=false
if [[ -z "${internal}" && -n "${target_external}" ]]; then
  is_docked=true
fi

if [[ "${is_docked}" == "true" ]]; then
  # Lid closed / internal panel gone: move workspaces to the external monitor
  hyprctl dispatch moveworkspacetomonitor 1 "${target_external}"
  hyprctl dispatch moveworkspacetomonitor 2 "${target_external}"
  hyprctl dispatch moveworkspacetomonitor 3 "${target_external}"

  # Docked gaps
  hyprctl keyword general:gaps_in 2
  hyprctl keyword general:gaps_out 6
else
  # Lid open (or no external): if internal exists, move primary workspace back
  if [[ -n "${internal}" ]]; then
    hyprctl dispatch moveworkspacetomonitor 1 "${internal}"
  fi

  # Laptop gaps
  hyprctl keyword general:gaps_in 6
  hyprctl keyword general:gaps_out 20
fi
