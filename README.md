# Linux Operations Toolkit

Small Bash utilities and troubleshooting runbooks for Linux operations.

This repository contains practical exercises in service management,
automation, and production troubleshooting.

## Service control

`scripts/service-control.sh` starts, stops, restarts, or checks a
systemd service.

### Requirements

- Linux running systemd
- Bash
- An existing service to manage
- Appropriate permissions for service changes

### Usage

```bash
./scripts/service-control.sh <start|stop|restart|status> <service>
```

Examples using Nginx, if installed:

```bash
./scripts/service-control.sh status nginx
sudo ./scripts/service-control.sh start nginx
sudo ./scripts/service-control.sh restart nginx
sudo ./scripts/service-control.sh stop nginx
```

Use a local test service when practicing. Stopping or restarting a service
can interrupt applications that depend on it.

### Behavior

- Requires exactly two arguments.
- Rejects unsupported actions.
- Prints systemctl output directly.
- Returns systemctl's exit code for supported actions.
- Returns exit code 2 for invalid arguments.

An inactive service can return a nonzero status code; this is expected.

### Basic checks

Check Bash syntax:

```bash
bash -n scripts/service-control.sh
```

Check argument validation:

```bash
./scripts/service-control.sh
echo $?
# Expected: usage message, then 2

./scripts/service-control.sh invalid nginx
echo $?
# Expected: invalid action message, then 2
```

## Scope

This is a learning project. The service-control script is a small wrapper
around systemctl, intended to demonstrate Bash argument handling,
case statements, and exit codes.
