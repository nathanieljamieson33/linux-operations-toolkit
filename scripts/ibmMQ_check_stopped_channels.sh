#!/bin/sh
# Author: Nathaniel Jamieson
# Report STOPPED channels on locally running IBM MQ queue managers.

export LC_ALL=C
recipient='youremail@domain.com'

qmgr_output=$(dspmq -n -o status 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
    printf 'dspmq failed (rc=%s):\n%s\n' "$rc" "$qmgr_output" >&2
    exit 1
fi

running_qmgrs=$(printf '%s\n' "$qmgr_output" |
    sed -n 's/^QMNAME(\([^)]*\))[[:space:]]*STATUS(Running)[[:space:]]*$/\1/p')

if [ -z "$running_qmgrs" ]; then
    printf '%s\n' 'No locally running queue managers to check.' >&2
    exit 0
fi

failed=0
report=
while IFS= read -r qmgr; do
    output=$(runmqsc "$qmgr" 2>&1 <<'MQSC'
DISPLAY CHSTATUS(*) WHERE(STATUS EQ STOPPED) STATUS
MQSC
    )
    rc=$?

    if [ "$rc" -ne 0 ]; then
        printf 'runmqsc failed for %s (rc=%s):\n%s\n' \
            "$qmgr" "$rc" "$output" >&2
        failed=1
        continue
    fi

    channels=$(printf '%s\n' "$output" | awk '
        /^[[:space:]]*AMQ[0-9][0-9][0-9][0-9][A-Z]?:/ {
            status_record = ($0 ~ /^[[:space:]]*AMQ8417I?:/)
        }
        status_record && match($0, /(^|[[:space:]])CHANNEL\([^)]*\)/) {
            channel = substr($0, RSTART, RLENGTH)
            sub(/^[[:space:]]*CHANNEL\(/, "", channel)
            sub(/\)$/, "", channel)
            print channel
        }
    ')

    if [ -n "$channels" ]; then
        report="${report}
Queue manager: $qmgr
$channels
"
    elif ! printf '%s\n' "$output" |
        grep -Eq '^[[:space:]]*AMQ8420I?:'; then
        printf 'Unexpected channel status output for %s:\n%s\n' \
            "$qmgr" "$output" >&2
        failed=1
    fi
done <<EOF
$running_qmgrs
EOF

if [ -n "$report" ]; then
    host=$(hostname 2>/dev/null) || host=unknown
    if ! printf '%s\n%s\n' \
        'Confirm whether these channels were stopped intentionally. Escalate unexpected stops.' \
        "$report" |
        mail -s "IBM MQ: stopped channels on $host" "$recipient"; then
        printf 'Could not send stopped-channel alert:%s\n' "$report" >&2
        failed=1
    fi
fi

exit "$failed"