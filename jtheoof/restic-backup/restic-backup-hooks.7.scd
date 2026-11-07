restic-backup-hooks(7)

# NAME

restic-backup-hooks - run your own commands before and after restic-backup jobs

# DESCRIPTION

restic has no hooks of its own. *restic-backup*(8) adds them: executable files that
it runs before and after each job. They are how you make a backup consistent for
anything restic cannot know about: dump a database, stop and start a service,
mount a snapshot, record the package list. *restic-backup* knows no particular
program, so any language and any tool works.

# LAYOUT

Hooks live in one directory per event, below *RESTIC_HOOKS_DIR* (default
*/etc/restic/hooks*):

	pre-backup.d/   post-backup.d/++
	pre-prune.d/    post-prune.d/++
	pre-check.d/    post-check.d/

An event runs the files of its directory in sorted order, so numeric prefixes
(*10-sqlite*, *90-start-service*) set the order.

# WHICH FILES RUN

A file runs if it is a regular file, is executable, and its name consists only of
letters, digits, underscore and hyphen. A name containing a dot is skipped, so
*10-x.pacnew*, *10-x.bak* and editor backup files never run. Files that are not
executable are skipped, which is a simple way to disable a hook.

# SAFETY

Hooks run as root. *restic-backup* refuses to run a hook, or any hook of an event,
if the event directory or the file is not owned by root or can be written by its
group or by others. A refusal counts as a hook failure.

# THE JOB LIFECYCLE

. Take the lock, so that only one job runs at a time.
. Run the *pre-*_job_ hooks.
. Run restic. (Skipped if *RESTIC_HOOKS_STRICT=1* and a pre-hook failed.)
. Run the *post-*_job_ hooks. They always run, so a service stopped in a pre-hook
  is started again even if the backup failed.
. Write the status file.

The mount guard (*RESTIC_REQUIRE_MOUNT*) is checked before step 1: no hook runs if
the repository disk is missing.

# ENVIRONMENT

Hooks start with the working directory */*, standard input from */dev/null*, and
standard output and error going to the journal. They inherit every setting from
*/etc/restic/env* (see *restic-backup.conf*(5)), notably *RESTIC_STAGING_DIR*, and
get:

*RESTIC_JOB*
	*backup*, *prune* or *check*.

*RESTIC_JOB_STATUS*, *RESTIC_JOB_EXIT*
	Post hooks only: what restic did (*ok*, *warning* or *failed*) and its exit
	status. These describe restic, not other hooks.

# FAILURE

A hook fails if it exits with a non-zero status or is refused for safety. The
failure is recorded and the job's result becomes *failed*, with the hook named in the
status file's *message*. By default the job still runs restic after a failing
pre-hook, so the rest of your data is still backed up. With *RESTIC_HOOKS_STRICT=1*
restic is not run. Post hooks run in either case. A failing post-hook also fails
the job.

# STAGING

Hooks that produce files, such as database dumps, should write them below
*RESTIC_STAGING_DIR* (default */var/lib/restic-backup/staging*, mode 700), which a
backup of */* includes. Remove copies you no longer want yourself: nothing cleans the
directory.

# SQLITE DATABASES IN WAL MODE

Opening a SQLite database that is in WAL mode and that no program has open creates a
*-wal* and a *-shm* file next to it, even for a read-only copy (*sqlite3 -readonly*).
When a hook runs as root, SQLite gives the *-shm* file to the database's owner, so the
service that owns the database can still use it. The copy fails if those files cannot
be created, which happens when the job runs in a unit with a read-only filesystem
(for example *ProtectSystem=strict*) and the database is idle. Either add the
database's directory to *ReadWritePaths=* or do not sandbox the job. The units
shipped by the package are not sandboxed.

# EXAMPLES

A hook that copies SQLite databases consistently:

```
# /etc/restic/hooks/pre-backup.d/10-sqlite
#!/bin/sh
set -eu
for db in /var/lib/myapp/*.db; do
  [ -f "$db" ] || continue
  dest=$RESTIC_STAGING_DIR$db
  mkdir -p "$(dirname "$dest")"
  sqlite3 -readonly "$db" ".backup '$dest'"
done
```

Stop a service during the backup and start it again afterwards:

	# pre-backup.d/10-stop-myapp++
	systemctl stop myapp.service++
	# post-backup.d/90-start-myapp++
	systemctl start myapp.service

Working examples are in */usr/share/doc/restic-backup/examples/hooks/*. They are not
executable, so they do nothing until you copy one into a hook directory, make it
executable and edit it. Copy it under a name without a dot.

# SEE ALSO

*restic-backup*(8), *restic-backup.conf*(5)
