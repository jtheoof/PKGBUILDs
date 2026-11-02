#!/bin/bash
# Build every package listed in .github/repo-packages whose files are not yet
# published at $SITE_URL (all of them when FORCE=1).
#
# Runs as root inside an archlinux:base-devel container; package code runs as the
# unprivileged "builder" user. This job never sees any secret.
# Output: out/built/*.pkg.tar.zst (unsigned) and out/expected.txt (every file the
# repository must contain).
set -euo pipefail

: "${SITE_URL:?}"
root=$PWD
out=$root/out

mkdir -p "$out/built"
: > "$out/expected.txt"

id builder &>/dev/null || useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
chown -R builder:builder "$root"

# The container's makepkg.conf enables "debug". With that option on, --packagelist
# always names a <pkgbase>-debug-* package, but makepkg only builds one when
# stripping produced detached debug symbols (compiled binaries). None of our
# packages ship any, so the plan would name files that are never built. We do not
# publish debug packages anyway: force the option off for both plan and build.
cfg=/tmp/makepkg.conf
cp /etc/makepkg.conf "$cfg"
echo 'OPTIONS+=(!debug)' >> "$cfg"
chmod 644 "$cfg"

while read -r dir; do
  [[ -z $dir || $dir == \#* ]] && continue

  mapfile -t files < <(runuser -u builder -- bash -c 'cd "$1" && makepkg --config "$2" --packagelist' _ "$root/$dir" "$cfg" | xargs -n1 basename)
  need=${FORCE:-0}

  for f in "${files[@]}"; do
    echo "$f" >> "$out/expected.txt"
    ((need)) && continue
    code=$(curl -s -o /dev/null -I -w '%{http_code}' --retry 3 "$SITE_URL/x86_64/$f" || true)
    case $code in
      200) ;;
      404) need=1 ;;
      *) echo "unexpected HTTP $code for $SITE_URL/x86_64/$f (rerun with force to build everything)" >&2; exit 1 ;;
    esac
  done

  if ((need)); then
    echo "==> building $dir"
    runuser -u builder -- env PKGDEST="$out/built" bash -c 'cd "$1" && makepkg --config "$2" -sf --noconfirm --nosign' _ "$root/$dir" "$cfg"
  else
    echo "==> $dir is already published, skipping"
  fi
done < .github/repo-packages

# Everything that was built must be in the plan. A mismatch (for example a debug
# or split package nobody listed) would otherwise be silently dropped from the
# repository; fail here and say which file.
shopt -s nullglob
for f in "$out"/built/*; do
  name=${f##*/}
  grep -qxF -- "$name" "$out/expected.txt" \
    || { echo "built $name, which is not in the plan (expected.txt); check split packages and makepkg options" >&2; exit 1; }
done
