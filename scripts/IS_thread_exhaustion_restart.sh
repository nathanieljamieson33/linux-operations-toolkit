#!/bin/bash
# Desc: Check if threads are exhausted and restart the Integration Server if so...
#####

set -u
set -o pipefail
SERVER_LOG="$HOME/IS/logs/server.log"
MATCH_STRING="Available Thread Pool Warning Threshold Exceeded: 0% available"
STATE_FILE="$HOME/tools/IS-thread-exhaustion.last"
LOCK_FILE="$HOME/tools/IS-thread-exhaustion.lock"
SCRIPT_LOG="$HOME/tools/IS-thread-monitor.log"
MAIL_TO="youremail@domain.com"
LOG_TAIL_LINES=200
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
exit 0
fi

log_message()
{
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$SCRIPT_LOG"
}

mail_on_restart()
{
  [[ -z "$MAIL_TO" ]] && return 0
  local tmp
  tmp=$(mktemp) || return 1
  {
    echo "Integration Server on $(hostname) for user $USER was restarted at $(date '+%Y-%m-%d %H:%M:%S')."
    echo "Thread pool warning: $WARNING_TIMESTAMP (old PID $IS_PID, started $PID_START_TEXT)"
    echo
    echo "===== Last $LOG_TAIL_LINES lines of $SERVER_LOG ====="
    tail -n "$LOG_TAIL_LINES" "$SERVER_LOG"
  } > "$tmp"
  mail -s "$(hostname) $USER IS restarted due to thread exhaustion" "$MAIL_TO" < "$tmp" \
  || log_message "ERROR: Failed to send mail to $MAIL_TO"
  rm -f "$tmp"
}

if [[ ! -r "$SERVER_LOG" ]]; then
  log_message "ERROR: Cannot read server log: $SERVER_LOG"
  exit 1
fi

# Capture wM IS pid and exit if none found
## **NOTE** Please update the grep if your instance has multiples IS profiles
IS_PID=$(ps -fu $USER|grep IntegrationServer|grep DWM_HOME|grep -v grep|awk '{print $2}')
if [[ -z "$IS_PID" ]]; then
  log_message "ERROR: Integration Server PID not found."
  exit 1
fi

PID_START_TEXT=$(ps -p "$IS_PID" -o lstart=)
if [[ -z "$PID_START_TEXT" ]]; then
  log_message "ERROR: Could not determine start time for PID $IS_PID"
  exit 1
fi

PID_START_EPOCH=$(date -d "$PID_START_TEXT" +%s 2>/dev/null)
if [[ ! "$PID_START_EPOCH" =~ ^[0-9]+$ ]]; then
  log_message "ERROR: Could not convert PID start time: $PID_START_TEXT"
  exit 1
fi

LAST_MATCH=$(grep -F "$MATCH_STRING" "$SERVER_LOG" | tail -n 1)
if [[ -z "$LAST_MATCH" ]]; then
  exit 0
fi

WARNING_TIMESTAMP=$(
  printf '%s\n' "$LAST_MATCH" |
    grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}([.,][0-9]+)?' | head -n 1 |
    sed -E 's/T/ /; s/[.,][0-9]+$//'
)
if [[ -z "$WARNING_TIMESTAMP" ]]; then
  log_message "ERROR: Found warning but could not parse its timestamp: $LAST_MATCH"
  exit 1
fi

WARNING_EPOCH=$(date -d "$WARNING_TIMESTAMP" +%s 2>/dev/null)
  if [[ ! "$WARNING_EPOCH" =~ ^[0-9]+$ ]]; then
  log_message "ERROR: Could not convert warning timestamp: $WARNING_TIMESTAMP"
  exit 1
fi

# Don't check against the last warning more than once
LAST_HANDLED_EPOCH=0
if [[ -r "$STATE_FILE" ]]; then
  read -r LAST_HANDLED_EPOCH < "$STATE_FILE"
  [[ "$LAST_HANDLED_EPOCH" =~ ^[0-9]+$ ]] || LAST_HANDLED_EPOCH=0
fi

if (( WARNING_EPOCH <= LAST_HANDLED_EPOCH )); then
  exit 0
fi

#Restart IS if PID time is older than warning message timestamp
if (( WARNING_EPOCH > PID_START_EPOCH )); then
  log_message "CRITICAL: Thread pool reached 0% at $WARNING_TIMESTAMP; current PID $IS_PID started at $PID_START_TEXT. Restarting Integration Server"
  timeout 30 jstack "$ID_PID" > "$HOME/tools/IS-thread-dump-$(date '+%Y%n%d-%H%M%S').log" 2>&1 || 
  log_message "ERROR: Failed to capture thread dump for PID $IS_PID"
  jstack "$IS_PID" > /tmp/wM.threaddump.
  kill -9 "$IS_PID"
  sleep 5
  $HOME/IS/bin/startup.sh 9>&-
  log_message "SUCCESS: Integration Server startup command completed."
  mail_on_restart
  exit 0
fi

# No action if IS PID is younger than warning message timestamp
printf '%s\n' "$WARNING_EPOCH" > "$STATE_FILE"
log_message "INFO: Ignoring warning from $WARNING_TIMESTAMP because PID $IS_PID started later at $PID_START_TEXT."
exit 0