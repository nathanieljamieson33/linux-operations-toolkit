#!/usr/bin/env bash

# Manage a systemd service.
 # Usage: ./service-control.sh <start|stop|restart|status> <service>

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <start|stop|restart|status> <service>" >&2
    exit 2
    fi

action="$1"
service="$2"

case "$action" in
    start|stop|restart|status)
        systemctl "$action" -- "$service"
        ;;
    *)
        echo "Invalid action: $action" >&2
        echo "Valid actions: start, stop, restart, status" >&2
        exit 2
        ;;
esac
