#!/bin/bash
# Refuse to sign unless the keyring holds the repo signing subkey and NOT the
# primary's secret key (a stripped primary shows up as "sec" with "#" in field 15
# of the --with-colons listing). Uses the keyring selected by GNUPGHOME.
set -euo pipefail
: "${SIGNING_SUBKEY:?}"

colons=$(gpg --batch --list-secret-keys --with-colons --with-subkey-fingerprints)

awk -F: '$1=="sec" && $15=="#" {found=1} END {exit !found}' <<<"$colons" \
  || { echo "the primary secret key is present in CI (or missing); refusing to sign" >&2; exit 1; }

grep -q "^fpr:::::::::${SIGNING_SUBKEY}:" <<<"$colons" \
  || { echo "signing subkey ${SIGNING_SUBKEY} not found in the secret" >&2; exit 1; }

echo "signing key check passed: primary is a stub, subkey ${SIGNING_SUBKEY} is available"
