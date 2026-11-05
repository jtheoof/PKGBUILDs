# restic-backup

Scheduled [restic](https://restic.net) backups for Arch Linux: nightly backup,
weekly forget/prune and monthly check through systemd timers, a lock so that only
one job runs at a time, a guard against a missing repository disk, **hooks** before
and after each job, and a status file per job.

It does not replace restic and knows no particular database or service: you
configure restic through the usual `RESTIC_*` variables and put your own commands
in hooks.

## Quick start

```sh
sudoedit /etc/restic/env              # set RESTIC_REPOSITORY
sudo restic-backup init              # new repository only
sudo restic-backup run backup         # first backup, by hand
restic-backup status
sudo systemctl enable --now restic-backup.timer restic-backup-prune.timer restic-backup-check.timer
```

The install script creates `/etc/restic/password` with a random value if it does
not exist. **Store a copy in a password manager**: without it the repository
cannot be opened.

## Commands

| | |
|---|---|
| `restic-backup run backup\|prune\|check` | run a job (what the timers call) |
| `restic-backup status` | last result of each job |
| `restic-backup snapshots`, `ls`, `restore`, ... | any other command runs restic with the environment loaded (not `backup`, `prune`, `check`, `forget`: use `run`) |
| `restic-backup exec COMMAND...` | run any command with the restic environment |
| `restic-backup shell` | shell with the restic environment loaded |

## Documentation

- `man 8 restic-backup`: commands, jobs, status files, exit status
- `man restic-backup.conf`: every setting in `/etc/restic/env`
- `man restic-backup-hooks`: the hook interface
- `/usr/share/doc/restic-backup/examples/hooks/`: example hooks
- `/usr/share/doc/restic-backup/examples/recovery/restore.sh`: restore script for a
  machine that has nothing else (live USB); keep it on an encrypted recovery stick
  with the repository password and an SSH key

## Tests

`tests/test.sh` runs the script against a fake restic, as a pseudo-root
(`unshare -r`), without touching the system.
