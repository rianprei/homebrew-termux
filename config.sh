# homebrew-termux configuration
# All paths are relative to HOMEBREW_PREFIX or use variables.
# No hardcoded personal paths.

# Homebrew repository (where brew is cloned)
HOMEBREW_BREW_GIT_URL="${HOMEBREW_BREW_GIT_URL:-https://github.com/Homebrew/brew.git}"
HOMEBREW_BREW_GIT_BRANCH="${HOMEBREW_BREW_GIT_BRANCH:-stable}"

# Required Ruby version (Termux ships 3.4.x)
HOMEBREW_REQUIRED_RUBY_VERSION="${HOMEBREW_REQUIRED_RUBY_VERSION:-3.4}"

# Portable Ruby version (fallback)
HOMEBREW_PORTABLE_RUBY_VERSION="${HOMEBREW_PORTABLE_RUBY_VERSION:-3.4.6}"

# Termux-specific paths (auto-detected, not hardcoded)
TERMUX_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
TERMUX_GLIBC_PREFIX="${TERMUX_GLIBC_PREFIX:-${TERMUX_PREFIX}/glibc}"
TERMUX_ETC="${TERMUX_ETC:-${TERMUX_PREFIX}/etc}"

# Detect architecture
HOMEBREW_ARCH="${HOMEBREW_ARCH:-$(uname -m)}"
case "${HOMEBREW_ARCH}" in
  aarch64|arm64) HOMEBREW_ARCH="aarch64" ;;
  x86_64)        HOMEBREW_ARCH="x86_64" ;;
  *)             HOMEBREW_ARCH="unknown" ;;
esac

# Ruby binary path
TERMUX_RUBY_BIN="${TERMUX_PREFIX}/bin/ruby"
TERMUX_GLIBC_BASH="${TERMUX_GLIBC_PREFIX}/bin/bash"
TERMUX_ENV="${TERMUX_PREFIX}/bin/env"
TERMUX_GLIBC_LDD="${TERMUX_GLIBC_PREFIX}/bin/ldd"
