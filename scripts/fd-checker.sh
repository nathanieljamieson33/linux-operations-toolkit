#!/bin/bash
#
# Purpose: Check and correct FD limits for processes matching
#          a specified process name.
#
# Usage:  ./fd-checker.sh [--apply] <process_name>
# Report: ./fd-checker.sh java                 # Print current and expected limits
# Apply:  sudo ./fd-checker.sh --apply java    # Change mismatched live limits

LIMITS_FILE="/etc/security/limits.conf"
EMAIL="youremail@domain.com"
HOST=$(hostname -s)

APPLY=0
if [[ ${1:-} == --apply ]]; then
    APPLY=1
    shift
fi

if [[ $# -ne 1 || -z ${1:-} || ${1:-} == -* ]]; then
    printf 'Usage: %s [--apply] <process_name>\n' "$0" >&2
    exit 2
fi

PROCNAME="$1"

if (( APPLY && EUID != 0 )); then
    printf 'ERROR: --apply must be run as root.\n' >&2
    exit 1
fi

# Counters
CHECKED=0
UPDATED=0
SKIPPED=0
FAILED=0
MISMATCHED=0
REPORT=""

if [[ ! -r "$LIMITS_FILE" ]]; then
    echo "ERROR: Cannot read $LIMITS_FILE"
    exit 1
fi

# Find processes by exact process name.
# Escape regex characters for a literal match against the Linux comm name.
PROCESS_PATTERN=$(printf '%s\n' "$PROCNAME" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
PID_OUTPUT=$(pgrep -x -- "$PROCESS_PATTERN")
PGREP_STATUS=$?

if (( PGREP_STATUS == 1 )); then
    echo "INFO: No processes found matching: $PROCNAME"
    exit 0
fi

if (( PGREP_STATUS != 0 )); then
    printf 'ERROR: pgrep failed for %s (exit %s).\n' "$PROCNAME" "$PGREP_STATUS" >&2
    exit 1
fi

mapfile -t PIDS <<< "$PID_OUTPUT"

echo "Found ${#PIDS[@]} process(es) matching: $PROCNAME"

# Read the effective value of the last matching entry
# for the specified user and limit type in limits.conf.
# This intentionally checks explicit per-user entries only.
get_limit() {
    local user="$1"
    local type="$2"

    awk -v user="$user" -v type="$type" '
        $1 == user && $2 == type && $3 == "nofile" {
            value = $4
        }
        END {
            if (value != "") print value
        }
    ' "$LIMITS_FILE"
}

# Iterate through every matching process.
for PID in "${PIDS[@]}"; do

    ((CHECKED++))

    # Ensure process still exists.
    if [[ ! -d "/proc/$PID" ]]; then
        echo "WARNING: PID $PID no longer exists."
        ((SKIPPED++))
        continue
    fi

    # Get process owner.
    PROCUSER=$(ps -o user= -p "$PID" | xargs)

    if [[ -z "$PROCUSER" ]]; then
        echo "WARNING: Unable to determine owner of PID $PID"
        ((FAILED++))
        continue
    fi

    # Get configured limits.
    SLIMIT=$(get_limit "$PROCUSER" soft)
    HLIMIT=$(get_limit "$PROCUSER" hard)

    # Validate configured limits.
    if [[ ! "$SLIMIT" =~ ^[0-9]+$ ]] ||
       [[ ! "$HLIMIT" =~ ^[0-9]+$ ]]; then

        echo "WARNING: Invalid/missing limits for $PROCUSER"
        ((SKIPPED++))
        continue
    fi

    if (( SLIMIT > HLIMIT )); then
        echo "WARNING: Soft limit exceeds hard limit for $PROCUSER"
        ((FAILED++))
        continue
    fi

    # Read process limits from /proc.
    LIMITS=$(awk '
        /^Max open files/ {
            print $4, $5
        }
    ' "/proc/$PID/limits" 2>/dev/null)

    read -r SPIDLIMIT HPIDLIMIT <<< "$LIMITS"

    if [[ ! "$SPIDLIMIT" =~ ^[0-9]+$ ]] ||
       [[ ! "$HPIDLIMIT" =~ ^[0-9]+$ ]]; then

        echo "WARNING: Unable to read numeric FD limits for PID $PID"
        ((FAILED++))
        continue
    fi

    echo "----------------------------------------"
    echo "PID: $PID | User: $PROCUSER"
    echo "Current:  soft=$SPIDLIMIT hard=$HPIDLIMIT"
    echo "Expected: soft=$SLIMIT hard=$HLIMIT"

    # Compare both soft and hard limits.
    if [[ "$SPIDLIMIT" != "$SLIMIT" ]] ||
       [[ "$HPIDLIMIT" != "$HLIMIT" ]]; then

        ((MISMATCHED++))

	if (( ! APPLY )); then
	    printf 'REPORT: PID %s differs from configured limits. No change made.\n' "$PID"
	    continue
        fi

        # Recheck the process owner and name before applying
        CURRENT_USER=$(ps -o user= -p "$PID" | xargs)
        CURRENT_NAME=$(cat "/proc/$PID/comm" 2>/dev/null)

        if [[ "$CURRENT_USER" != "$PROCUSER" ||
              "$CURRENT_NAME" != "$PROCNAME" ]]; then

            echo "WARNING: PID $PID changed or exited."
            ((FAILED++))
            continue
        fi

        if prlimit --pid "$PID" \
            --nofile="$SLIMIT:$HLIMIT"; then

            echo "SUCCESS: Updated FD limits for PID $PID"
            ((UPDATED++))

            REPORT+="PID: $PID
User: $PROCUSER
Previous: soft=$SPIDLIMIT hard=$HPIDLIMIT
Updated:  soft=$SLIMIT hard=$HLIMIT

"
        else
            echo "ERROR: Failed to update PID $PID"
            ((FAILED++))

            REPORT+="FAILED - PID: $PID User: $PROCUSER

"
        fi

    else
        echo "OK: FD limits already match."
        ((SKIPPED++))
    fi
done

echo "========================================"
echo "FD Limit Check Summary"
echo "Host: $HOST"
echo "Process: $PROCNAME"
echo "Checked: $CHECKED"
echo "Mismatched: $MISMATCHED"
echo "Updated: $UPDATED"
echo "Skipped: $SKIPPED"
echo "Failed: $FAILED"
echo "========================================"

# Send one email if updates or failures occurred.
if (( APPLY && (UPDATED > 0 || FAILED > 0) )); then
    {
        echo "FD Limit Check Report"
        echo "Host: $HOST"
        echo "Date: $(date -u '+%b %d %H:%M UTC')"
        echo "Process: $PROCNAME"
        echo
        echo "Checked: $CHECKED"
	echo "Mismatched: $MISMATCHED"
        echo "Updated: $UPDATED"
        echo "Skipped: $SKIPPED"
        echo "Failed: $FAILED"
        echo
        printf '%s\n' "$REPORT"
    } | mail -s \
        "$HOST - FD Limit Report for $PROCNAME" \
        "$EMAIL"
fi

if (( FAILED > 0 )); then
    exit 1
fi

exit 0
