#!/bin/bash
# Tests for restic-backup, run against a fake restic in a scratch directory.
# The script runs as a pseudo-root (unshare -r): nothing real is touched.
# Usage: tests/test.sh      (set KEEP_TMP=1 to keep the scratch directory)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$HERE/../restic-backup
PASS=0; FAIL=0

check() { # description, command...
  local d=$1; shift
  if "$@"; then PASS=$((PASS + 1)); printf 'ok   %s\n' "$d"
  else FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$d"; fi
}
has()     { [[ $1 == *"$2"* ]]; }
hasnt()   { [[ $1 != *"$2"* ]]; }
is()      { [[ $1 == "$2" ]]; }

if [[ ${RB_TEST_INNER:-} != 1 ]]; then
  # Outer phase, as the real unprivileged user: the root requirement.
  out=$("$SCRIPT" run backup 2>&1); rc=$?
  check "refuses to run as non-root" has "$out" "must run as root"
  check "non-root exit status is 1" is "$rc" 1
  out=$("$SCRIPT" snapshots 2>&1); rc=$?
  check "a passed command also needs root" has "$out" "must run as root"
  check "a passed command as non-root exits 1" is "$rc" 1
  RB_OUTER_PASS=$PASS RB_OUTER_FAIL=$FAIL RB_TEST_INNER=1 exec unshare -rm "$0" "$@"
fi
PASS=${RB_OUTER_PASS:-0}; FAIL=${RB_OUTER_FAIL:-0}

T=$(mktemp -d "${TMPDIR:-/tmp}/restic-backup-test.XXXXXX")
[[ -z ${KEEP_TMP:-} ]] && trap 'rm -rf -- "$T"' EXIT
N=0

setup() { # fresh case directory, fake restic, default env
  N=$((N + 1)); C=$T/case$N
  mkdir -p "$C/bin" "$C/hooks" "$C/state"
  LOG=$C/restic.log; ENVF=$C/env
  cat > "$C/bin/restic" <<'EOT'
#!/bin/sh
echo "ARGS: $*" >> "$RB_LOG"
echo "ENV: HOST=${RESTIC_HOST:-} REPO=${RESTIC_REPOSITORY:-} JOB=${RESTIC_JOB:-}" >> "$RB_LOG"
exit "${FAKE_RESTIC_EXIT:-0}"
EOT
  chmod 755 "$C/bin/restic"
  printf '/skip\n' > "$C/excludes"
  cat > "$ENVF" <<EOT
RESTIC_REPOSITORY=/fake/repo
RESTIC_HOST=testhost
RESTIC_STATE_DIR=$C/state
RESTIC_HOOKS_DIR=$C/hooks
RESTIC_EXCLUDE_FILE=$C/excludes
RESTIC_BACKUP_PATHS="/a /b"
RESTIC_BACKUP_TAGS="x y"
EOT
}
rb() { PATH=$C/bin:$PATH RB_LOG=$LOG RESTIC_ENV_FILE=$ENVF "$SCRIPT" "$@"; }
hook() { # event name body
  mkdir -p "$C/hooks/$1.d"
  printf '#!/bin/sh\n%s\n' "$3" > "$C/hooks/$1.d/$2"
  chmod 755 "$C/hooks/$1.d/$2"
}
log() { cat "$LOG" 2>/dev/null; }
field() { sed -n "s/^$2=//p" "$C/state/status/$1" 2>/dev/null; }

# --- help and usage ----------------------------------------------------------
setup
check "--version prints the program name" has "$("$SCRIPT" --version)" "restic-backup "
out=$("$SCRIPT" --help); check "--help lists the run command" has "$out" "run <job>"
check "--help mentions the hooks man page" has "$out" "restic-backup-hooks(7)"
out=$("$SCRIPT" run --help); rc=$?; check "run --help succeeds" is "$rc" 0
check "run --help lists the jobs" has "$out" "check    verify the repository"
"$SCRIPT" >/dev/null 2>&1; check "no command exits 2" is "$?" 2
rb run bogus >/dev/null 2>&1; check "unknown job exits 2" is "$?" 2

# --- jobs build the right restic command lines ---------------------------------
setup; rb run backup >/dev/null 2>&1; rc=$?
check "backup exits 0" is "$rc" 0
check "backup command line" has "$(log)" "ARGS: backup --one-file-system --exclude-caches --exclude-file=$C/excludes --tag x,y --host testhost /a /b"
check "restic sees RESTIC_HOST and the repository" has "$(log)" "ENV: HOST=testhost REPO=/fake/repo JOB=backup"
check "status result ok" is "$(field backup result)" ok
setup; rb run prune >/dev/null 2>&1
check "prune command line" has "$(log)" "ARGS: forget --prune --host testhost --keep-daily 7 --keep-weekly 4 --keep-monthly 6"
setup; echo 'RESTIC_KEEP_DAILY=3' >> "$ENVF"; rb run prune >/dev/null 2>&1
check "retention can be overridden" has "$(log)" "--keep-daily 3 --keep-weekly 4"
setup; rb run check >/dev/null 2>&1
check "check command line" has "$(log)" "ARGS: check --read-data-subset=10%"
setup; sed -i '/RESTIC_HOST/d' "$ENVF"; rb run backup >/dev/null 2>&1
check "host defaults to uname -n" has "$(log)" "--host $(uname -n) "
setup; sed -i '/RESTIC_EXCLUDE_FILE/d;/RESTIC_BACKUP_TAGS/d' "$ENVF"; echo 'RESTIC_EXCLUDE_FILE=' >> "$ENVF"; echo 'RESTIC_BACKUP_TAGS=' >> "$ENVF"; rb run backup >/dev/null 2>&1
check "empty exclude file and tags are dropped" hasnt "$(log)" "--exclude-file"
setup; echo "RESTIC_EXCLUDE_FILE=$C/missing" >> "$ENVF"; out=$(rb run backup 2>&1); rc=$?
check "unreadable exclude file fails the job" is "$rc" 1
check "restic is not run without the exclude file" is "$(log)" ""

# --- result mapping ------------------------------------------------------------
setup; FAKE_RESTIC_EXIT=3 rb run backup >/dev/null 2>&1; rc=$?
check "restic exit 3 on backup is a warning" is "$(field backup result)" warning
check "a warning exits 0" is "$rc" 0
check "warning message explains exit 3" has "$(field backup message)" "exit 3"
setup; FAKE_RESTIC_EXIT=3 rb run prune >/dev/null 2>&1; rc=$?
check "restic exit 3 on prune is a failure" is "$(field prune result)" failed
setup; FAKE_RESTIC_EXIT=1 rb run backup >/dev/null 2>&1; rc=$?
check "restic exit 1 is a failure" is "$(field backup result)" failed
check "a failure exits 1" is "$rc" 1
check "status records the restic exit code" is "$(field backup exit)" 1

# --- guards --------------------------------------------------------------------
setup; echo 'RESTIC_REQUIRE_MOUNT=/definitely/not/mounted' >> "$ENVF"; out=$(rb run backup 2>&1); rc=$?
check "mount guard refuses an unmounted path" has "$out" "/definitely/not/mounted is not mounted"
check "mount guard exits 1" is "$rc" 1
check "restic is not run when the guard fails" is "$(log)" ""
setup; echo 'RESTIC_REQUIRE_MOUNT=/proc' >> "$ENVF"; rb run backup >/dev/null 2>&1
check "mount guard accepts a mount point" is "$(field backup result)" ok
setup; sed -i '/RESTIC_REPOSITORY/d' "$ENVF"; out=$(rb run backup 2>&1); rc=$?
check "missing repository is reported" has "$out" "RESTIC_REPOSITORY is not set"
setup; echo 'KEEP_DAILY=5' >> "$ENVF"; out=$(rb run prune 2>&1)
check "old setting names produce a warning" has "$out" "KEEP_DAILY in"
check "old setting names are ignored" has "$(log)" "--keep-daily 7"

# --- hooks ---------------------------------------------------------------------
setup
hook pre-backup 10-first   'echo "pre first" >> "$RB_LOG"'
hook pre-backup 20-second  'echo "pre second job=$RESTIC_JOB cwd=$(pwd)" >> "$RB_LOG"'
hook post-backup 10-post   'echo "post status=$RESTIC_JOB_STATUS exit=$RESTIC_JOB_EXIT" >> "$RB_LOG"'
hook pre-backup 30-noexec  'echo "RAN noexec" >> "$RB_LOG"'; chmod 644 "$C/hooks/pre-backup.d/30-noexec"
hook pre-backup 40-x.pacnew 'echo "RAN pacnew" >> "$RB_LOG"'
rb run backup >/dev/null 2>&1; l=$(log)
check "pre-hooks run in order before restic" has "$l" $'pre first\npre second job=backup cwd=/\nARGS: backup'
check "post-hook sees the result" has "$l" "post status=ok exit=0"
check "post-hook runs after restic" has "$l" $'ENV: HOST=testhost REPO=/fake/repo JOB=backup\npost status'
check "non-executable files are not run" hasnt "$l" "RAN noexec"
check "names with dots are not run" hasnt "$l" "RAN pacnew"

setup
hook pre-backup 10-bad 'exit 7'
hook post-backup 10-post 'echo "post status=$RESTIC_JOB_STATUS" >> "$RB_LOG"'
out=$(rb run backup 2>&1); rc=$?
check "a failing pre-hook does not stop the backup" has "$(log)" "ARGS: backup"
check "a failing pre-hook fails the job" is "$(field backup result)" failed
check "the failing hook is named in the message" has "$(field backup message)" "pre-backup/10-bad failed (exit 7)"
check "post-hooks still run after a failed pre-hook" has "$(log)" "post status=ok"
check "a failed hook exits 1" is "$rc" 1

setup; echo 'RESTIC_HOOKS_STRICT=1' >> "$ENVF"
hook pre-backup 10-bad 'exit 1'
hook post-backup 10-post 'echo "post status=$RESTIC_JOB_STATUS exit=$RESTIC_JOB_EXIT" >> "$RB_LOG"'
rb run backup >/dev/null 2>&1
check "strict mode does not run restic" hasnt "$(log)" "ARGS: backup"
check "strict mode still runs post-hooks" has "$(log)" "post status=failed exit=1"
check "strict mode fails the job" is "$(field backup result)" failed

setup; FAKE_RESTIC_EXIT=1 rb run backup >/dev/null 2>&1
setup
hook post-backup 10-post 'echo "post status=$RESTIC_JOB_STATUS exit=$RESTIC_JOB_EXIT" >> "$RB_LOG"'
FAKE_RESTIC_EXIT=1 rb run backup >/dev/null 2>&1
check "post-hooks run when restic fails and see it" has "$(log)" "post status=failed exit=1"

setup
hook post-backup 10-bad 'exit 4'
rb run backup >/dev/null 2>&1; rc=$?
check "a failing post-hook fails the job" is "$(field backup result)" failed
check "the failing post-hook is named" has "$(field backup message)" "post-backup/10-bad failed (exit 4)"

setup
hook pre-backup 10-open 'echo "RAN open" >> "$RB_LOG"'
chmod 775 "$C/hooks/pre-backup.d/10-open"
rb run backup >/dev/null 2>&1
check "a group-writable hook is refused" hasnt "$(log)" "RAN open"
check "the refusal is reported" has "$(field backup message)" "10-open: not owned by root or writable by others"

setup
hook pre-backup 10-ok 'echo "RAN ok" >> "$RB_LOG"'
chmod 777 "$C/hooks/pre-backup.d"
rb run backup >/dev/null 2>&1
check "a world-writable hook directory is refused" hasnt "$(log)" "RAN ok"

setup
hook pre-prune 10-p 'echo "pre-prune job=$RESTIC_JOB" >> "$RB_LOG"'
hook pre-backup 10-b 'echo "RAN backup hook" >> "$RB_LOG"'
rb run prune >/dev/null 2>&1
check "hooks are per job" has "$(log)" "pre-prune job=prune"
check "other jobs' hooks are not run" hasnt "$(log)" "RAN backup hook"

# --- status, exec, shell -------------------------------------------------------
setup; out=$(rb status); rc=$?
check "status shows jobs that never ran" has "$out" "never run"
check "status exits 0 when nothing failed" is "$rc" 0
rb run backup >/dev/null 2>&1; FAKE_RESTIC_EXIT=1 rb run prune >/dev/null 2>&1; out=$(rb status); rc=$?
check "status shows ok and failed jobs" has "$out" "backup   ok"
check "status shows the failed prune" has "$out" "prune    failed"
check "status exits 1 when a job failed" is "$rc" 1

setup; out=$(rb exec sh -c 'echo "$RESTIC_HOST:$RESTIC_REPOSITORY"' 2>&1)
check "exec runs with the environment" is "$out" "testhost:/fake/repo"
setup; echo 'RESTIC_REQUIRE_MOUNT=/definitely/not/mounted' >> "$ENVF"; out=$(rb exec true 2>&1); rc=$?
check "exec obeys the mount guard" is "$rc" 1
setup; rb exec >/dev/null 2>&1; check "exec without a command exits 2" is "$?" 2
setup; out=$(SHELL=/bin/sh rb shell </dev/null 2>&1); check "shell starts and prints a banner" has "$out" "environment loaded"

# --- restic commands passed through ---------------------------------------------
setup; out=$(rb snapshots 2>&1); rc=$?
check "an unknown command runs restic" has "$(log)" "ARGS: snapshots"
check "the passed command sees the environment" has "$(log)" "REPO=/fake/repo"
check "the passed command exits 0" is "$rc" 0
setup; rb restore latest --target /x --include /etc/fstab >/dev/null 2>&1
check "arguments are passed on unchanged" has "$(log)" "ARGS: restore latest --target /x --include /etc/fstab"
setup; FAKE_RESTIC_EXIT=3 rb snapshots >/dev/null 2>&1; check "the exit status of restic is kept" is "$?" 3
setup; echo 'RESTIC_REQUIRE_MOUNT=/definitely/not/mounted' >> "$ENVF"; rb snapshots >/dev/null 2>&1; rc=$?
check "a passed command obeys the mount guard" is "$rc" 1
check "a refused passed command does not run restic" is "$(log)" ""
for job in backup prune check forget; do
  setup; out=$(rb "$job" 2>&1); rc=$?
  check "$job is not passed to restic" is "$(log)" ""
  check "$job exits 2" is "$rc" 2
  check "$job points to the job" has "$out" "restic-backup "
done
setup; out=$(rb backup 2>&1); check "backup suggests run backup" has "$out" "run backup"
setup; out=$(rb forget 2>&1); check "forget suggests run prune" has "$out" "run prune"
setup; out=$(rb --bogus 2>&1); rc=$?; check "an unknown option exits 2" is "$rc" 2
check "an unknown option is not passed to restic" is "$(log)" ""
setup; out=$("$SCRIPT" --help); check "--help mentions the pass-through" has "$out" "passed to restic"

# --- the shipped SQLite example ------------------------------------------------
if command -v sqlite3 >/dev/null; then
  setup; mkdir -p "$C/data"
  sqlite3 "$C/data/app.db" 'create table t(a); insert into t values (1),(2),(3);'
  sed "s#/var/lib/myapp#$C/data#" "$HERE/../example-sqlite" > "$C/hooks.sqlite"
  hook pre-backup 10-sqlite "$(sed 1d "$C/hooks.sqlite")"
  rb run backup >/dev/null 2>&1
  copy=$C/state/staging$C/data/app.db
  check "sqlite example stages a consistent copy" is "$(sqlite3 -readonly "$copy" 'select count(*) from t' 2>&1)" 3
else
  printf 'skip sqlite example (sqlite3 not installed)\n'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
