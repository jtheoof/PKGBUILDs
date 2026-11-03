restic-backup(8)

# NAME

restic-backup - scheduled restic backups with hooks, a mount guard and status files

# SYNOPSIS

*restic-backup* *run* _job_++
*restic-backup* *status*++
*restic-backup* *exec* _command_ [_argument_...]++
*restic-backup* *shell*++
*restic-backup* [*-h*|*--help*] [*-V*|*--version*]

# DESCRIPTION

*restic-backup* runs restic on a schedule. It adds what restic does not do by
itself: a lock so that only one job runs at a time, a guard that refuses to run
when the repository disk is not mounted, user-defined hooks before and after each
job, and a small status file per job that other tools can read.

It does not replace restic. The repository, the password and every other restic
option are configured through the usual *RESTIC_\** environment variables, in
*/etc/restic/env*. See *restic-backup.conf*(5) for every setting and
*restic-backup-hooks*(7) for the hook interface.

The package installs three systemd services with timers, which are not enabled
automatically. They call *restic-backup run*.

# COMMANDS

*run* _job_
	Run one job as root. The job is one of *backup*, *prune* or *check*. The
	command loads the settings, checks that restic is installed, that a repository
	is configured and that *RESTIC_REQUIRE_MOUNT*, if set, is a mount point. It then
	takes the lock, runs the *pre-*_job_ hooks, runs restic, runs the *post-*_job_
	hooks and records the result. Post hooks run even if the job failed.

*status*
	Print the last result and time of each job. Exits with status 1 if any job
	last failed. Does not need root if the state directory is readable.

*exec* _command_ [_argument_...]
	Load the settings, check the mount guard and run _command_ with the restic
	environment. Typically *restic-backup exec restic snapshots*. Must run as root.

*shell*
	Check the mount guard and start a shell (*$SHELL*) with the restic environment
	loaded, so that plain *restic* commands work. Must run as root.

*-h*, *--help*, *help*
	Print a short usage text. *restic-backup run --help* and the same flag on the
	other commands print help for that command.

*-V*, *--version*
	Print the version.

# JOBS

*backup*
	Runs *restic backup* with *RESTIC_BACKUP_ARGS*, *--exclude-file* set to
	*RESTIC_EXCLUDE_FILE*, *--tag* set to *RESTIC_BACKUP_TAGS*, *--host* set to
	*RESTIC_HOST* and the paths in *RESTIC_BACKUP_PATHS*.

*prune*
	Runs *restic forget --prune* for *RESTIC_HOST* with *--keep-daily*,
	*--keep-weekly* and *--keep-monthly* set from *RESTIC_KEEP_DAILY*,
	*RESTIC_KEEP_WEEKLY* and *RESTIC_KEEP_MONTHLY*.

*check*
	Runs *restic check* with *--read-data-subset* set to *RESTIC_CHECK_SUBSET*.

# STATUS FILES

After every job, *restic-backup* writes _STATE_/status/_job_, where _STATE_ is
*RESTIC_STATE_DIR* (default */var/lib/restic-backup*). The file has one *key=value*
per line and is replaced atomically:

	job=backup++
	result=ok++
	exit=0++
	message=...++
	started=2026-11-03T03:30:00-05:00++
	finished=2026-11-03T03:41:12-05:00

*result* is one of:

*ok*
	restic exited with 0 and no hook failed.

*warning*
	A backup finished with restic exit status 3: the snapshot was created but some
	source data could not be read, for example a file that disappeared during the
	backup. The command still exits with 0.

*failed*
	restic failed, or a hook failed or was refused. *message* names the cause.

*exit* is restic's exit status, or 1 if restic was not run. *message* is present
only when there is something to say.

# EXIT STATUS

*0*
	The job finished with result *ok* or *warning*, or the command succeeded.

*1*
	The job failed, a guard refused, or *status* found a failed job.

*2*
	Usage error.

# FILES

_/etc/restic/env_
	Settings, read as shell. Overridden by *RESTIC_ENV_FILE*.

_/etc/restic/excludes_
	Exclude patterns for the backup job.

_/etc/restic/password_
	Repository password. The package creates it with a random value, mode 600, only
	if it does not exist. It is never overwritten.

_/etc/restic/hooks/_
	Hook directories, see *restic-backup-hooks*(7).

_/var/lib/restic-backup/_
	State: the lock, the status files and the staging directory for hooks.

_/var/cache/restic/_
	restic cache (*RESTIC_CACHE_DIR*).

# ENVIRONMENT

*RESTIC_ENV_FILE*
	Path of the settings file to use instead of */etc/restic/env*.

All other settings are read from the settings file, see *restic-backup.conf*(5).

# EXAMPLES

Start the first backup by hand and look at the result:

	sudo restic-backup run backup++
	restic-backup status

List the snapshots, or work interactively:

	sudo restic-backup exec restic snapshots++
	sudo restic-backup shell

Enable the schedule:

	sudo systemctl enable --now restic-backup.timer \\++
	  restic-backup-prune.timer restic-backup-check.timer

Change the time of the nightly backup:

	sudo systemctl edit restic-backup.timer

# SEE ALSO

*restic*(1), *restic-backup.conf*(5), *restic-backup-hooks*(7), *systemd.timer*(5)
