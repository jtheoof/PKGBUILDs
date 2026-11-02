#!/bin/bash
# Sign the newly built packages, fetch the unchanged ones from the live site, build
# and sign the pacman database, and lay out the GitHub Pages site. Runs no package
# code. Expects the signing key in the keyring selected by GNUPGHOME.
#
# Environment: REPO_NAME SITE_URL PRIMARY_FPR SIGNING_SUBKEY
#              IN_DIR (downloaded build artifact)  SITE_DIR (output)
#              TEMPLATE_DIR (directory holding index.html)
set -euo pipefail

: "${REPO_NAME:?}" "${SITE_URL:?}" "${PRIMARY_FPR:?}" "${SIGNING_SUBKEY:?}"
: "${IN_DIR:?}" "${SITE_DIR:?}" "${TEMPLATE_DIR:?}"

IN_DIR=$(realpath "$IN_DIR")
TEMPLATE_DIR=$(realpath "$TEMPLATE_DIR")
rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR/x86_64"
SITE_DIR=$(realpath "$SITE_DIR")

# Always force the repo subkey (the trailing "!"), never the primary key.
sign() { gpg --batch --yes --detach-sign --no-armor --local-user "$SIGNING_SUBKEY!" --output "$1.sig" "$1"; }

cd "$SITE_DIR/x86_64"

while read -r f; do
  [[ -n $f ]] || continue
  if [[ -f $IN_DIR/built/$f ]]; then
    cp "$IN_DIR/built/$f" .
    sign "$f"
  else
    curl -fsSLO --retry 3 "$SITE_URL/x86_64/$f"
    curl -fsSLO --retry 3 "$SITE_URL/x86_64/$f.sig"
  fi
done < "$IN_DIR/expected.txt"

for f in *.pkg.tar.zst; do
  gpg --batch --verify "$f.sig" "$f" 2>/dev/null \
    || { echo "bad signature on $f (rerun with force to rebuild and re-sign everything)" >&2; exit 1; }
done

repo-add -q "$REPO_NAME.db.tar.zst" ./*.pkg.tar.zst
for n in db files; do
  sign "$REPO_NAME.$n.tar.zst"
  # Pages cannot serve symlinks: replace the ones repo-add made with real copies.
  cp -f --remove-destination "$REPO_NAME.$n.tar.zst" "$REPO_NAME.$n"
  cp -f --remove-destination "$REPO_NAME.$n.tar.zst.sig" "$REPO_NAME.$n.sig"
done

cd "$SITE_DIR"
gpg --armor --export "$PRIMARY_FPR" > jtheoof.gpg

sed -E 's/-(any|x86_64|aarch64)\.pkg\.tar\.zst$//; s#.*#      <li><code>&</code></li>#' "$IN_DIR/expected.txt" > "$IN_DIR/list.html"
sed -e "/<!--PACKAGES-->/{r $IN_DIR/list.html" -e 'd}' "$TEMPLATE_DIR/index.html" > index.html
