#!/data/data/com.termux/files/usr/bin/bash
# homebrew-termux: revert all patches
set -euo pipefail

BREW="${1:-$HOME/brew}"

cd "$BREW" || exit 1
git checkout -- .
git clean -fd -- Library/Homebrew 2>/dev/null || true
echo "=== All patches reverted ==="
echo "Homebrew restored to upstream state."
