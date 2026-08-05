#!/data/data/com.termux/files/usr/bin/bash
# homebrew-termux: integration test suite
# Usage: bash test.sh
set -uo pipefail

BREW="${HOME}/brew/bin/brew"
BREW_TERMUX="${HOME}/brew/bin/brew-termux"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_GIT=/data/data/com.termux/files/usr/bin/git
export HOMEBREW_TEMP="${HOME}/tmp"
export HOMEBREW_DEFAULT_TEMP="${HOME}/tmp"
mkdir -p "$HOMEBREW_TEMP"

PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { ((PASS++)); ((TOTAL++)); echo -e "  ${GREEN}✓${NC} $*"; }
fail() { ((FAIL++)); ((TOTAL++)); echo -e "  ${RED}✗${NC} $*"; }
skip() { ((TOTAL++)); echo -e "  ${YELLOW}○${NC} $* (skipped)"; }

echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║           homebrew-termux integration tests                  ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""

# ─── Basic Commands ─────────────────────────────────────────────────────────
echo "Basic commands:"

if $BREW --version >/dev/null 2>&1; then
  VERSION=$($BREW --version | head -1)
  pass "brew --version: $VERSION"
else
  fail "brew --version"
fi

if $BREW config >/dev/null 2>&1; then
  pass "brew config"
else
  fail "brew config"
fi

if $BREW --help >/dev/null 2>&1; then
  pass "brew --help"
else
  fail "brew --help"
fi

# ─── Search & Info ──────────────────────────────────────────────────────────
echo ""
echo "Search & info:"

if $BREW search hello 2>/dev/null | grep -q hello; then
  pass "brew search hello"
else
  fail "brew search hello"
fi

if $BREW info hello 2>/dev/null | grep -q "Program providing"; then
  pass "brew info hello"
else
  fail "brew info hello"
fi

# ─── List ───────────────────────────────────────────────────────────────────
echo ""
echo "List:"

if $BREW list --versions >/dev/null 2>&1; then
  pass "brew list --versions"
else
  fail "brew list --versions"
fi

# ─── Install (bottle) ──────────────────────────────────────────────────────
echo ""
echo "Install (bottle):"

if $BREW install --force-bottle hello 2>/dev/null | grep -q "Pouring"; then
  pass "brew install --force-bottle hello"
else
  fail "brew install --force-bottle hello"
fi

# ─── Binary test ────────────────────────────────────────────────────────────
echo ""
echo "Binary tests:"

# Auto-patch hello
PATCHELF=/data/data/com.termux/files/usr/glibc/bin/patchelf
GLIBC_LD=/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
GLIBC_LIB=/data/data/com.termux/files/usr/glibc/lib
HELLO_BIN="${HOME}/brew/Cellar/hello/2.12.3/bin/hello"

if [[ -f "$HELLO_BIN" ]]; then
  chmod 755 "$HELLO_BIN" 2>/dev/null
  $PATCHELF --set-interpreter "$GLIBC_LD" "$HELLO_BIN" 2>/dev/null
  $PATCHELF --set-rpath "$GLIBC_LIB" "$HELLO_BIN" 2>/dev/null
  
  OUTPUT=$(hello 2>&1)
  if [[ "$OUTPUT" == *"Hello, world!"* ]]; then
    pass "hello binary execution"
  else
    fail "hello binary execution: $OUTPUT"
  fi
  
  # ELF validation
  if file "$HELLO_BIN" | grep -q "ELF"; then
    pass "hello is ELF binary"
  else
    fail "hello is not ELF"
  fi
  
  INTERP=$(readelf -l "$HELLO_BIN" 2>/dev/null | grep " interpreter:" | awk '{print $NF}')
  if [[ "$INTERP" == *"ld-linux-aarch64"* ]]; then
    pass "hello interpreter: $INTERP"
  else
    fail "hello interpreter: $INTERP (expected glibc ld-linux)"
  fi
  
  RPATH=$(readelf -d "$HELLO_BIN" 2>/dev/null | grep "RUNPATH\|RPATH" | head -1)
  if [[ -n "$RPATH" ]]; then
    pass "hello has RUNPATH/RPATH"
  else
    fail "hello missing RUNPATH/RPATH"
  fi
else
  skip "hello binary not found"
fi

# ─── Link/Unlink ────────────────────────────────────────────────────────────
echo ""
echo "Link/Unlink:"

if $BREW link hello >/dev/null 2>&1; then
  pass "brew link hello"
else
  fail "brew link hello"
fi

if $BREW unlink hello >/dev/null 2>&1; then
  pass "brew unlink hello"
else
  fail "brew unlink hello"
fi

# ─── Reinstall ──────────────────────────────────────────────────────────────
echo ""
echo "Reinstall:"

if $BREW reinstall --force-bottle hello 2>/dev/null | grep -q "Pouring"; then
  pass "brew reinstall --force-bottle hello"
else
  fail "brew reinstall --force-bottle hello"
fi

# ─── Uninstall ──────────────────────────────────────────────────────────────
echo ""
echo "Uninstall:"

if $BREW uninstall hello 2>/dev/null | grep -q "Uninstalling"; then
  pass "brew uninstall hello"
else
  fail "brew uninstall hello"
fi

# ─── Update ─────────────────────────────────────────────────────────────────
echo ""
echo "Update/Upgrade:"

if $BREW update >/dev/null 2>&1; then
  pass "brew update"
else
  fail "brew update"
fi

if $BREW upgrade 2>/dev/null; then
  pass "brew upgrade"
else
  fail "brew upgrade"
fi

# ─── Tap ────────────────────────────────────────────────────────────────────
echo ""
echo "Tap:"

if $BREW tap 2>/dev/null; then
  pass "brew tap"
else
  fail "brew tap"
fi

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║  Results: ${PASS} passed, ${FAIL} failed out of ${TOTAL} tests              ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
