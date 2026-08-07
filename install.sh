#!/data/data/com.termux/files/usr/bin/bash
# homebrew-termux: installer for Homebrew on Termux Android
# Usage: bash install.sh
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
BREW_DIR="${HOME}/brew"
CACHE_DIR="${HOME}/.cache/Homebrew"
TMP_DIR="${HOME}/tmp"
PREFIX="/data/data/com.termux/files/usr"
GLIBC_PREFIX="${PREFIX}/glibc"
GIT="${PREFIX}/bin/git"
RUBY="${PREFIX}/bin/ruby"
CURL="${PREFIX}/bin/curl"
PATCHELF="${GLIBC_PREFIX}/bin/patchelf"
GLIBC_LD="${GLIBC_PREFIX}/lib/ld-linux-aarch64.so.1"
GLIBC_LIB="${GLIBC_PREFIX}/lib"
GLIBC_BASH="${GLIBC_PREFIX}/bin/bash"
ENV_BIN="${GLIBC_PREFIX}/bin/env"

# ─── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[homebrew-termux]${NC} $*"; }
warn()  { echo -e "${YELLOW}[homebrew-termux]${NC} $*"; }
error() { echo -e "${RED}[homebrew-termux]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# ─── Pre-flight checks ─────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║           homebrew-termux installer v1.0.0                  ║"
echo "  ║     Native Homebrew for Termux Android (ARM64)              ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check Termux
[[ -f "${PREFIX}/etc/os-release" ]] || die "Not running in Termux"

# Check required tools
for tool in "$GIT" "$RUBY" "$CURL"; do
  [[ -x "$tool" ]] || die "Required tool not found: $tool"
done

# Check glibc
[[ -x "$GLIBC_BASH" ]] || die "glibc not found at $GLIBC_PREFIX. Install glibc first: pkg install glibc"
[[ -x "$GLIBC_LD" ]] || die "glibc ld-linux not found at $GLIBC_LD"

# Check patchelf
if [[ ! -x "$PATCHELF" ]]; then
  warn "patchelf not found at $PATCHELF. Installing..."
  pkg install -y patchelf 2>/dev/null || die "Failed to install patchelf"
  PATCHELF="${GLIBC_PREFIX}/bin/patchelf"
  [[ -x "$PATCHELF" ]] || die "patchelf not available"
fi

info "Prerequisites OK"

# ─── Create directories ─────────────────────────────────────────────────────
mkdir -p "$BREW_DIR" "$CACHE_DIR" "$TMP_DIR"
info "Created directories"

# ─── Clone Homebrew ─────────────────────────────────────────────────────────
if [[ -d "${BREW_DIR}/.git" ]]; then
  info "Homebrew already cloned at $BREW_DIR"
else
  info "Cloning Homebrew..."
  $GIT clone --depth=1 https://github.com/Homebrew/brew.git "$BREW_DIR"
fi

# ─── Create wrapper scripts ────────────────────────────────────────────────
info "Creating wrapper scripts..."

# brew-termux wrapper
cat > "${BREW_DIR}/bin/brew-termux" << 'WRAPPER'
#!/data/data/com.termux/files/usr/glibc/bin/bash
BREW_BIN="$(dirname "$(readlink -f "$0")")"
BREW_DIR="$(dirname "$BREW_BIN")"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_GIT_PATH=/data/data/com.termux/files/usr/bin/git
export HOMEBREW_TEMP="${HOMEBREW_TEMP:-$HOME/tmp}"
export HOMEBREW_DEFAULT_TEMP="${HOMEBREW_DEFAULT_TEMP:-$HOME/tmp}"
mkdir -p "$HOMEBREW_TEMP"

"$BREW_BIN/brew" "$@"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && [[ "$1" == "install" || "$1" == "upgrade" || "$1" == "reinstall" ]]; then
  PATCHELF=/data/data/com.termux/files/usr/glibc/bin/patchelf
  GLIBC_LD=/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
  GLIBC_LIB=/data/data/com.termux/files/usr/glibc/lib
  echo "==> Auto-patching ELF binaries..."
  # rpath must include every Cellar package's own lib/ dir, not just the
  # global glibc bridge — a binary's own shared lib (e.g. jq -> libjq.so.1)
  # and its deps' libs (e.g. oniguruma -> libonig.so.5) live under
  # Cellar/<pkg>/<ver>/lib/, and --set-rpath was overwriting rpath with
  # only $GLIBC_LIB, so those libs were never found at runtime.
  CELLAR_LIBS=""
  for libdir in "$BREW_DIR/Cellar"/*/*/lib; do
    [ -d "$libdir" ] || continue
    CELLAR_LIBS="${CELLAR_LIBS}:${libdir}"
  done
  FULL_RPATH="${GLIBC_LIB}${CELLAR_LIBS}"
  for pkg in "$BREW_DIR/Cellar"/*/*/bin/*; do
    [ -f "$pkg" ] || continue
    file "$pkg" 2>/dev/null | grep -q "ELF" || continue
    chmod 755 "$pkg" 2>/dev/null
    "$PATCHELF" --set-interpreter "$GLIBC_LD" "$pkg" 2>/dev/null
    "$PATCHELF" --set-rpath "$FULL_RPATH" "$pkg" 2>/dev/null
  done
  echo "==> Done patching"
fi
exit $EXIT_CODE
WRAPPER
chmod +x "${BREW_DIR}/bin/brew-termux"

# brew-tar wrapper
cat > "${PREFIX}/bin/brew-tar" << 'TAR'
#!/data/data/com.termux/files/usr/glibc/bin/bash
set -e
TMPDIR="${TMPDIR:-$HOME/tmp}"
mkdir -p "$TMPDIR"
ERROR_FILE=$(mktemp "$TMPDIR/tar-errors.XXXXXX")
if tar "$@" 2>"$ERROR_FILE"; then
  rm -f "$ERROR_FILE"
  exit 0
fi
TAR_EXIT=$?
ERROR_OUTPUT=$(cat "$ERROR_FILE" 2>/dev/null)
rm -f "$ERROR_FILE"
if echo "$ERROR_OUTPUT" | grep -qE "Invalid cross-device|hard link|Operation not permitted|File exists"; then
  tar "$@" --overwrite 2>/dev/null || true
  exit 0
fi
echo "$ERROR_OUTPUT" >&2
exit $TAR_EXIT
TAR
chmod +x "${PREFIX}/bin/brew-tar"

# env symlink
ln -sf "${ENV_BIN}" "${BREW_DIR}/bin/env"

info "Wrapper scripts created"

# ─── Apply patches ──────────────────────────────────────────────────────────
info "Applying Termux patches..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/apply-patches.sh" ]]; then
  bash "${SCRIPT_DIR}/apply-patches.sh" "$BREW_DIR"
elif [[ -f "${HOME}/.homebrew/homebrew-termux/apply-patches.sh" ]]; then
  bash "${HOME}/.homebrew/homebrew-termux/apply-patches.sh" "$BREW_DIR"
else
  die "apply-patches.sh not found"
fi

# ─── Install git hooks ──────────────────────────────────────────────────────
info "Installing git hooks..."
HOOKS_DIR="${BREW_DIR}/.git/hooks"
mkdir -p "$HOOKS_DIR"

for hook in post-merge post-checkout post-rewrite; do
  cat > "${HOOKS_DIR}/${hook}" << HOOK
#!/data/data/com.termux/files/usr/bin/bash
exec ~/.homebrew/homebrew-termux/apply-patches.sh ~/brew
HOOK
  chmod +x "${HOOKS_DIR}/${hook}"
done

info "Git hooks installed"

# ─── Verify installation ────────────────────────────────────────────────────
info "Verifying installation..."

if "${BREW_DIR}/bin/brew" --version >/dev/null 2>&1; then
  VERSION=$("${BREW_DIR}/bin/brew" --version)
  info "Homebrew version: $VERSION"
else
  die "Homebrew installation failed"
fi

if "${BREW_DIR}/bin/brew" config >/dev/null 2>&1; then
  info "Homebrew config OK"
else
  warn "Homebrew config has warnings (this is normal for Termux)"
fi

# ─── Add to PATH ────────────────────────────────────────────────────────────
SHELL_RC=""
if [[ -f "${HOME}/.bashrc" ]]; then
  SHELL_RC="${HOME}/.bashrc"
elif [[ -f "${HOME}/.zshrc" ]]; then
  SHELL_RC="${HOME}/.zshrc"
fi

if [[ -n "$SHELL_RC" ]]; then
  if ! grep -q "homebrew-termux" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# homebrew-termux" >> "$SHELL_RC"
    echo "export PATH=\"${BREW_DIR}/bin:\$PATH\"" >> "$SHELL_RC"
    info "Added ${BREW_DIR}/bin to PATH in $SHELL_RC"
  fi
fi

# ─── Done ───────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║           Installation complete!                            ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo "  ║                                                              ║"
echo "  ║  Usage:                                                      ║"
echo "  ║    brew-termux search <formula>                              ║"
echo "  ║    brew-termux install <formula>                             ║"
echo "  ║    brew-termux list                                          ║"
echo "  ║                                                              ║"
echo "  ║  Or add to PATH and use 'brew' directly:                    ║"
echo "  ║    export PATH=\"${BREW_DIR}/bin:\$PATH\"                ║"
echo "  ║                                                              ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
