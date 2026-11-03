restic-backup.conf(5)

# NAME

restic-backup.conf - settings of restic-backup

# DESCRIPTION

*/etc/restic/env* is a shell fragment read by *restic-backup*(8) with every
variable exported. Lines are plain *NAME=value* assignments and may use shell
quoting. Variables named *RESTIC_\** that restic itself reads, such as
*RESTIC_REPOSITORY*, *RESTIC_PASSWORD_FILE*, *RESTIC_COMPRESSION* or
*RESTIC_PACK_SIZE*, reach restic unchanged. The settings below belong to
*restic-backup*. The file is listed in *backup=()*, so pacman keeps local edits and
writes a *.pacnew* file when the packaged default changes.

Lists (*RESTIC_BACKUP_PATHS*, *RESTIC_BACKUP_ARGS*, *RESTIC_BACKUP_TAGS*) are separated
by whitespace and cannot contain quoted spaces.

# REPOSITORY

*RESTIC_REPOSITORY*
	Where the repository is: a path, *sftp:user@host:/path*, *s3:...*, *rest:...*,
	anything restic accepts. Required unless *RESTIC_REPOSITORY_FILE* is set.

*RESTIC_PASSWORD_FILE*
	File with the repository password. Default in the packaged file:
	*/etc/restic/password*.

*RESTIC_CACHE_DIR*
	restic cache. Default in the packaged file: */var/cache/restic*.

*RESTIC_HOST*
	Host name stored in snapshots and used to select them when pruning, so that
	several machines can share a repository. Restic reads this variable itself.
	Default: the output of *uname -n*.

*RESTIC_REQUIRE_MOUNT*
	A path that must be a mount point, or the job and *exec* and *shell* refuse
	to run. Use it when the repository is on a disk that is not always mounted, so
	that a missing disk cannot make restic write a repository into an empty
	directory on the root filesystem. Default: no check.

# BACKUP JOB

*RESTIC_BACKUP_PATHS*
	What to back up. Default: */*.

*RESTIC_BACKUP_ARGS*
	Extra arguments for *restic backup*. Default: *--one-file-system --exclude-caches*.
	Setting it replaces the default.

*RESTIC_BACKUP_TAGS*
	Tags added to snapshots. Default: *scheduled*. Empty for none.

*RESTIC_EXCLUDE_FILE*
	Exclude pattern file. Default: */etc/restic/excludes*. Set it empty to use none.
	If it is set and cannot be read, the job fails without running restic.

# PRUNE AND CHECK JOBS

*RESTIC_KEEP_DAILY*, *RESTIC_KEEP_WEEKLY*, *RESTIC_KEEP_MONTHLY*
	Retention for *restic forget*. Defaults: 7, 4 and 6. A snapshot is kept if any
	of the three rules keeps it. Periods count snapshots, not calendar time, so a
	long outage of the backup does not expire old snapshots. *0* disables a rule.

*RESTIC_CHECK_SUBSET*
	Share of the repository data that *restic check* re-reads, for example *10%* or
	*1/12*. Default: *10%*.

# HOOKS AND STATE

*RESTIC_HOOKS_DIR*
	Directory holding the hook directories. Default: */etc/restic/hooks*. See
	*restic-backup-hooks*(7).

*RESTIC_HOOKS_STRICT*
	*0* (default): a failing pre-hook is recorded and the job still runs restic.
	*1*: restic is not run after a failing pre-hook. Post hooks run in both cases.

*RESTIC_STAGING_DIR*
	Directory where hooks write dumps and copies. Default:
	*$RESTIC_STATE_DIR/staging*, mode 700. It is inside */var/lib*, so a backup of */*
	includes it. Add it to *RESTIC_BACKUP_PATHS* if you do not back up */*.

*RESTIC_STATE_DIR*
	State directory (lock and status files). Default: */var/lib/restic-backup*
	(under systemd, *$STATE_DIRECTORY*).

# VARIABLES SET FOR HOOKS

Hooks receive every variable above, and also:

*RESTIC_JOB*
	*backup*, *prune* or *check*.

*RESTIC_JOB_STATUS*, *RESTIC_JOB_EXIT*
	Post hooks only: the result (*ok*, *warning* or *failed*) of restic and its exit
	status.

# EXCLUDE FILE

Patterns follow *restic backup --exclude-file*. A restore should reproduce the
machine, so exclude only what regenerates by itself. For system directories exclude
the contents (*/var/log/journal/\**), not the directory, so that the directory and
its owner and mode are restored. Other filesystems need no entry when
*--one-file-system* is in use.

# SCHEDULE

The timers use the system time zone. To change a schedule use
*systemctl edit restic-backup.timer* and set *OnCalendar=* after clearing it with an
empty *OnCalendar=* line. Defaults: backup every day at 03:30, prune on Saturdays at
04:00, check on the 15th of each month at 04:00. The timers are *Persistent*: a job
missed while the machine was off runs after the next boot.

# SEE ALSO

*restic-backup*(8), *restic-backup-hooks*(7), *restic*(1)
