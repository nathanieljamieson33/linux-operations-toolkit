#!/bin/bash
#
# Purpose: Check and correct FD limits for processes matching
#          a specified process name.
#
# Usage: ./check_fd_limits.sh <process_name>
# Example: ./check_fd_limits.sh java
#

LIMITS_FILE="/etc/security/limits.conf"
EMAIL="youremail@domain.com"
HOST=$(hostname -s)
PROCNAME="$1"

# Counters
CHECKED=0
UPDATED=0
SKIPPED=0
FAILED=0

REPORT=""

# Validate arguments.
if [[ -z "$PROCNAME" ]]; then
    echo "Usage: $0 <process_name>"
    exit 1
fi

# Require root.
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Script must be run as root."
    exit 1
fi

if [[ ! -r "$LIMITS_FILE" ]]; then
    echo "ERROR: Cannot read $LIMITS_FILE"
    exit 1
fi

# Find processes by exact process name.
# pgrep -x matches the process comm name, not its full
# command line. Linux comm names are limited to 15 bytes.
mapfile -t PIDS < <(pgrep -x -- "$PROCNAME")

if [[ ${#PIDS[@]} -eq 0 ]]; then
    echo "INFO: No processes found matching: $PROCNAME"
    exit 0
fi

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

        # Confirm PID still belongs to the same process.
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
echo "Updated: $UPDATED"
echo "Skipped: $SKIPPED"
echo "Failed: $FAILED"
echo "========================================"

# Send one email if updates or failures occurred.
if (( UPDATED > 0 || FAILED > 0 )); then

    {
        echo "FD Limit Check Report"
        echo "Host: $HOST"
        echo "Date: $(date -u '+%b %d %H:%M UTC')"
        echo "Process: $PROCNAME"
        echo
        echo "Checked: $CHECKED"
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
