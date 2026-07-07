#!/bin/sh
# mobai-ci installer.
#
#   curl -fsSL https://raw.githubusercontent.com/MobAI-App/mobai-ci/main/install.sh | sh
#
# Env overrides:
#   MOBAI_CI_VERSION   version to install (e.g. 0.1.0); default: latest
#   MOBAI_CI_REPO      GitHub repo hosting releases; default: MobAI-App/mobai-ci
#   MOBAI_CI_BIN_DIR   install dir; default: /usr/local/bin if writable, else ~/.local/bin
set -eu

REPO="${MOBAI_CI_REPO:-MobAI-App/mobai-ci}"
VERSION="${MOBAI_CI_VERSION:-latest}"

err() { echo "mobai-ci install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "required command not found: $1"; }

need uname
need tar
if command -v curl >/dev/null 2>&1; then
  dl() { curl -fsSL "$1" -o "$2"; }
  # fetch URL [extra-header]
  fetch() { if [ -n "${2:-}" ]; then curl -fsSL -H "$2" "$1"; else curl -fsSL "$1"; fi; }
elif command -v wget >/dev/null 2>&1; then
  dl() { wget -qO "$2" "$1"; }
  fetch() { if [ -n "${2:-}" ]; then wget --header="$2" -qO- "$1"; else wget -qO- "$1"; fi; }
else
  err "need curl or wget"
fi

# latest_tag resolves the newest release tag. Primary: follow the
# releases/latest redirect on github.com - no API call, so it is immune to the
# anonymous api.github.com rate limit that shared CI runner IPs (especially
# GitHub's macOS fleet) hit constantly. Fallback: the API, authenticated with
# GH_TOKEN/GITHUB_TOKEN when set.
latest_tag() {
  if command -v curl >/dev/null 2>&1; then
    t=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)
    t="${t##*/tag/}"
    case "$t" in v[0-9]*) echo "$t"; return 0 ;; esac
  fi
  token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  hdr=""
  [ -n "$token" ] && hdr="Authorization: Bearer ${token}"
  fetch "https://api.github.com/repos/${REPO}/releases/latest" "$hdr" \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

# Detect OS / arch and map to release naming.
os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$os" in
  darwin) os=darwin ;;
  linux)  os=linux ;;
  *) err "unsupported OS: $os (mobai-ci supports macOS and Linux)" ;;
esac
arch=$(uname -m)
case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) err "unsupported arch: $arch" ;;
esac

# Resolve version -> release tag (tags look like v0.1.0).
if [ "$VERSION" = "latest" ]; then
  tag=$(latest_tag)
  [ -n "$tag" ] || err "could not resolve latest release of ${REPO} (pin one with MOBAI_CI_VERSION=x.y.z)"
else
  tag="v${VERSION#v}"
fi
ver="${tag#v}"

asset="mobai-ci_${ver}_${os}_${arch}.tar.gz"
base="https://github.com/${REPO}/releases/download/${tag}"

# Choose install dir.
if [ -n "${MOBAI_CI_BIN_DIR:-}" ]; then
  bindir="$MOBAI_CI_BIN_DIR"
elif [ -w /usr/local/bin ] 2>/dev/null; then
  bindir="/usr/local/bin"
else
  bindir="$HOME/.local/bin"
fi
mkdir -p "$bindir"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Installing mobai-ci ${ver} (${os}/${arch}) to ${bindir}"
dl "${base}/${asset}" "${tmp}/${asset}" || err "download failed: ${base}/${asset}"

# Verify checksum if the release publishes checksums.txt.
if fetch "${base}/checksums.txt" > "${tmp}/checksums.txt" 2>/dev/null && [ -s "${tmp}/checksums.txt" ]; then
  want=$(grep " ${asset}\$" "${tmp}/checksums.txt" | awk '{print $1}' | head -1)
  if [ -n "$want" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      got=$(sha256sum "${tmp}/${asset}" | awk '{print $1}')
    else
      got=$(shasum -a 256 "${tmp}/${asset}" | awk '{print $1}')
    fi
    [ "$want" = "$got" ] || err "checksum mismatch for ${asset}"
  fi
fi

tar -xzf "${tmp}/${asset}" -C "$tmp"
[ -f "${tmp}/mobai-ci" ] || err "archive did not contain mobai-ci"
chmod +x "${tmp}/mobai-ci"
mv "${tmp}/mobai-ci" "${bindir}/mobai-ci"

echo "Installed: ${bindir}/mobai-ci"
case ":$PATH:" in
  *":${bindir}:"*) : ;;
  *) echo "Note: ${bindir} is not on your PATH; add it or move the binary." >&2 ;;
esac
"${bindir}/mobai-ci" validate >/dev/null 2>&1 || true
echo "Done. Run: mobai-ci --help"
