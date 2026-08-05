#!/data/data/com.termux/files/usr/bin/bash
# homebrew-termux: uninstaller
# Usage: bash uninstall.sh [--keep-cellar]
set -euo pipefail

BREW_DIR="${HOME}/brew"
KEEP_CELLAR=false

[[ "${1:-}" == "--keep-cellar" ]] && KEEP_CELLAR=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[homebrew-termux]${NC} $*"; }
warn()  { echo -e "${YELLOW}[homebrew-termux]${NC} $*"; }

echo ""
echo "  homebrew-termux uninstaller"
echo ""

# Remove from PATH in shell rc
for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
  if [[ -f "$rc" ]] && grep -q "homebrew-termux" "$rc" 2>/dev/null; then
    sed -i '/# homebrew-termux/d' "$rc"
    sed -i "\|${BREW_DIR}/bin|d" "$rc"
    info "Removed from $rc"
  fi
done

# Remove wrapper scripts
rm -f "${HOME}/.local/bin/brew-termux" 2>/dev/null
rm -f "/data/data/com.termux/files/usr/bin/brew-tar" 2>/dev/null

# Remove git hooks
rm -f "${BREW_DIR}/.git/hooks/post-merge" 2>/dev/null
rm -f "${BREW_DIR}/.git/hooks/post-checkout" 2>/dev/null
rm -f "${BREW_DIR}/.git/hooks/post-rewrite" 2>/dev/null

if $KEEP_CELLAR; then
  info "Keeping Cellar (installed packages)"
  rm -rf "${BREW_DIR}"
else
  info "Removing ${BREW_DIR}..."
  rm -rf "${BREW_DIR}"
fi

# Remove cache
rm -rf "${HOME}/.cache/Homebrew" 2>/dev/null
rm -rf "${HOME}/.homebrew" 2>/dev/null
rm -rf "${HOME}/tmp/homebrew"* 2>/dev/null

info "Uninstall complete"
