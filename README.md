pkgbuilds
=========

My own PKGBUILDs and patches for Arch Linux.

| Directory | What |
|---|---|
| `jtheoof/` | my own packages and PKGBUILDs |

Private, machine-specific packages live in a separate private repository.

## pacman repository

Packages listed in [`.github/repo-packages`](.github/repo-packages) are built and
signed by GitHub Actions and published at <https://pkg.jtheoof.me>.

```sh
# 1. trust the signing key (compare the fingerprint below before trusting it)
curl -fsSL https://pkg.jtheoof.me/jtheoof.gpg | sudo pacman-key --add -
sudo pacman-key --lsign-key F44D05A50F6C9EB5C81BCF966A6B35DBE9442683

# 2. add to /etc/pacman.conf
[jtheoof]
SigLevel = Required DatabaseRequired
Server = https://pkg.jtheoof.me/$arch
```

Signing key fingerprint: `F44D 05A5 0F6C 9EB5 C81B CF96 6A6B 35DB E944 2683`
(packages are signed by a dedicated subkey of this key).

### How publishing works

- A push to `master` that touches a listed package rebuilds the repository.
- Only versions that are **not yet published** are built. Unchanged packages are
  copied from the live site, so their bytes and signatures never change.
  **Bump `pkgrel` (or `pkgver`) when you change a package**, or the change is not
  published.
- The build job has no secrets. The signing key is only available to the next job,
  which signs and indexes and runs no package code.
- To rebuild and re-sign everything (first run, key rotation), run the workflow
  manually with `force` enabled.
