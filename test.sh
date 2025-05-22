#!/bin/bash

start_spinner() {
  local msg="$1"
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local spin_i=0
  local interval=0.1

  SPINNER_MSG="$msg"
  printf "\r\e[2K" >&2

  {
    while [[ "$SPINNER_ACTIVE" -eq 1 ]]; do
      printf "\r\e[2K%s %b" "${frames[spin_i]}" "${YW}${SPINNER_MSG}${CL}" >&2
      spin_i=$(((spin_i + 1) % ${#frames[@]}))
      sleep "$interval"
    done
  } &

  SPINNER_PID=$!
  disown "$SPINNER_PID"
}

stop_spinner() {
  if [[ ${SPINNER_PID+v} && -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null
    sleep 0.1
    kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  SPINNER_ACTIVE=0
  unset SPINNER_PID
}

spinner_guard() {
  if [[ "$SPINNER_ACTIVE" -eq 1 ]] && [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_ACTIVE=0
    unset SPINNER_PID
  fi
}

spinner_guard
SPINNER_ACTIVE=1
start_spinner "Installing NetBox"
sleep 5
spinner_guard
SPINNER_ACTIVE=1
start_spinner "Installing NetBox1"
sleep 5
stop_spinner
