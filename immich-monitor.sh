#!/bin/bash
set -euo pipefail

NAME=$(basename "$0" .sh)

# Configuration
CONTAINER_FILTER="immich"
IDLE_DURATION=20            # Seconds to stay under CPU threshold
CHECK_INTERVAL=0.250        # Interval between checks (seconds)
PORT_WAKEUP=2283            # Port to watch for wake-up activity
CPU_THRESHOLD=1             # Below this CPU usage is considered idle

# Internal
frozen=false

# Permission check
if [[ "$EUID" -ne 0 ]]; then
  echo "$NAME: [ERROR] This script must be run as root"
  exit 1
fi

# Wait until docker is available
start_time=$(date +%s)
while ! docker info > /dev/null 2>&1; do
  if (( $(date +%s) - start_time >= 600 )); then
    echo "$NAME: [ERROR] timeout: docker not available after 10 minutes."
    exit 1
  fi
  sleep "$CHECK_INTERVAL"
done

# Redirect all stdout and stderr to /dev/kmsg for kernel log visibility
exec > /dev/kmsg 2>&1

cpuavg() {
  docker ps -q --filter "name=$CONTAINER_FILTER" | xargs -r -I {} \
    docker stats {} --no-stream --format "{{.CPUPerc}}" | sed 's/%//' \
    | awk '{sum += int($1)} END {print (NR > 0 ? sum : 0)}'
}

freeze() {
  echo "$NAME: [INFO] $CONTAINER_FILTER containers: freeze"
  docker ps --filter "name=$CONTAINER_FILTER" --format "{{.Names}}" | sort -r | while read -r name; do
    docker pause "$name" > /dev/null
  done
  frozen=true
}

resume() {
  echo "$NAME: [INFO] $CONTAINER_FILTER containers: resume"
  docker ps --filter "name=$CONTAINER_FILTER" --format "{{.Names}}" | sort | while read -r name; do
    docker unpause "$name" > /dev/null
  done
  frozen=false
}

wakeup() {
  netstat -tn | awk -v port="$PORT_WAKEUP" '$6 == "ESTABLISHED" && $4 ~ ":"port"$"' | grep -q .
}

(
trap resume EXIT
echo "$NAME: [INFO] $CONTAINER_FILTER containers: looker"

idle_start=""

while true; do
  if wakeup; then
    if $frozen; then
      resume
    fi
    idle_start=""
  elif ! $frozen; then
    cpu_usage=$(cpuavg)
    current_time=$(date +%s)

    if [[ "$cpu_usage" -lt "$CPU_THRESHOLD" ]]; then
      if [[ -z "$idle_start" ]]; then
        idle_start=$current_time
      elif (( current_time - idle_start >= IDLE_DURATION )); then
        freeze
      fi
    else
      idle_start=""
    fi
  fi

  sleep "$CHECK_INTERVAL"
done
) &
