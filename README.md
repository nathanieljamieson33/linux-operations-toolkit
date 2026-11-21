# Linux Operations Toolkit

Bash, POSIX shell, and Expect scripts for Linux production support and middleware operations. The examples cover IBM MQ channel monitoring, SFTP login checks, live file descriptor limits, and webMethods Integration Server recovery.

## Scripts

| Script | What it does | Requirements |
| --- | --- | --- |
| [IBM MQ channel monitor](scripts/ibmMQ_check_stopped_channels.sh) | Checks locally running queue managers for stopped channels and emails a report when it finds any. An operator can then confirm whether the stops were intentional. | IBM MQ CLI (`dspmq`, `runmqsc`), permission to query local queue managers, and `mail` |
| [SiteScope SFTP login check](scripts/sitescope_sftp_check.exp) | Verifies password authentication and confirms that an SFTP session opens. Returns distinct exit codes for connection or login failure, timeout, and local setup errors. | Expect, OpenSSH `sftp`, a trusted host key in `known_hosts`, and a password file |
| [File descriptor limit checker](scripts/fd-checker.sh) | Compares running processes’ soft and hard `nofile` limits with explicit per-user entries in `/etc/security/limits.conf`. Reports differences by default. `--apply` changes live limits. | Linux with `/proc`, Bash, and `pgrep`. Apply mode requires root and `prlimit`, and uses `mail` for notifications. |
| [Integration Server thread exhaustion recovery](scripts/IS_thread_exhaustion_restart.sh) | Looks for a 0% thread availability warning newer than the running webMethods Integration Server process and attempts to capture a thread dump and restart the server. | A webMethods Integration Server installation, Bash, `flock`, and JDK `jstack` |
| [systemd service control](scripts/service-control.sh) | Wraps `systemctl` for `status`, `start`, `stop`, and `restart`, preserving the command’s exit code. | Linux with systemd, Bash, and permission to manage the target unit |

## Quick start

From the repository root, check file descriptor limits for processes named `java` or inspect an installed systemd service:

```bash
./scripts/fd-checker.sh java
./scripts/service-control.sh status nginx


The FD checker prints the current and configured limits and counts mismatches. It reads explicit per-user entries from /etc/security/limits.conf. For a systemd-managed service, check the unit’s LimitNOFILE setting before treating a difference as a configuration error. Use sudo ./scripts/fd-checker.sh --apply java only when you intend to change the limits of matching running processes. Apply mode leaves persistent configuration files untouched.

For the SFTP check, provision the verified server host key in known_hosts for the account running the check. Store the password on one line in a file readable only by that account:

./scripts/sitescope_sftp_check.exp sftp.example.com 22 monitor /path/to/password-file

The check opens a session without transferring files. Exit codes are 0 for success, 1 for connection or login failure, 2 for timeout, and 3 for invalid input or local setup errors.

Environment-specific setup

Set the mail recipient before using the IBM MQ monitor, FD checker in apply mode, or Integration Server recovery script. The recovery script assumes an installation under $HOME/IS and uses $HOME/tools for its state, lock, and logs.

The Integration Server recovery example is under validation. Its restart path currently references an undefined PID variable and can exit before restarting the service.
