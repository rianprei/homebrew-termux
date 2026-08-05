# homebrew-termux

Native Homebrew port for Termux Android (ARM64). No proot, no chroot, no containers, no emulation, no root.

## What Works

| Command | Status | Notes |
|---------|--------|-------|
| `brew search` | ✅ | Full API search |
| `brew info` | ✅ | Formula info |
| `brew install --force-bottle` | ✅ | Bottle installation with auto-patchelf |
| `brew uninstall` | ✅ | With dependency autoremove |
| `brew link` / `brew unlink` | ✅ | Symlink management |
| `brew list --versions` | ✅ | Installed packages |
| `brew deps` | ✅ | Dependency tree |
| `brew update` | ✅ | Patches survive via git hooks |
| `brew upgrade` | ✅ | Package upgrades |
| `brew tap` | ✅ | Tap management |
| `brew bundle --help` | ✅ | Bundle help |
| `brew create --help` | ✅ | Create help |
| `brew edit --help` | ✅ | Edit help |

## Known Limitations

- **Bubblewrap sandbox**: Disabled on Termux (no unprivileged user namespaces)
- **Prefix mismatch**: Bottles built for `/home/linuxbrew/.linuxbrew` work via `--force-bottle`
- **ELF patching**: All binaries must be patched with patchelf to use glibc linker
- **`brew update-reset`**: destructive by design (hard-resets `Library/Homebrew` to upstream for every user) — always wipes these patches, always reapply `patches/build-from-source-fixes.patch` after running it

## `--build-from-source` (verified working)

`patches/build-from-source-fixes.patch` (apply with `git apply` from `$HOMEBREW_REPOSITORY`, then `git commit` so `brew update`'s guard recognizes it as intentional) fixes the from-source build path end to end — `git` and `cmake` built and ran successfully with it applied:

- GCC `-idirafter` vs `-isystem` ordering (fixes libstdc++'s `#include_next` chain finding real headers)
- `-std=gnu17`/`gnu89` fallback so this GCC's default C standard doesn't reject C99 mid-block declarations (git) or ancient K&R code (cyrus-sasl)
- `-rpath-link` to the glibc bridge (fixes indirect-dependency link failures, e.g. krb5 needing `libresolv`)
- `CMAKE_LIBRARY_PATH`/`CMAKE_INCLUDE_PATH` set directly on `ENV` in `build.rb` (Superenv strips shell-level exports, so `.zshrc`-level env vars never reach the build)
- `bin/brew`, `os.sh`, `vendor-install.sh`, `list.sh`, `executables.sh`, `update.sh`, shared `curl`/`git` shims, `system_command.rb`: every remaining hardcoded `/usr/bin/env`, `/usr/bin/ldd`, `/usr/bin/stat`, `/etc/os-release`, `/bin/bash` replaced with the real Termux/bridge path
- `os/linux/glibc.rb`: **root cause** of a nasty cascade — `Glibc.system_version` shelled out to a hardcoded `/usr/bin/ldd` that doesn't exist, silently returned a null version, which made Homebrew think glibc was "too old" and auto-add `glibc`+`linux-headers` as a forced from-source dependency for *any* formula, and also broke `DevelopmentTools.locate` into reporting "No developer tools installed" even with a working from-source GCC installed
- `cmd/doctor.rb`: fixed a `max_by` crash comparing `Symbol` vs `Integer` tiers (hit by any non-default/Tier-3 prefix, which this always is)
- `LC_ALL=C.UTF-8` forced in `os.sh` instead of falling back to `C` (Termux has no `locale` binary), since `LC_ALL=C` makes Ruby's external encoding US-ASCII and `JSON.parse` crashes on the first non-ASCII byte in a formula description

## Architecture

```
Termux (Android ARM64)
├── $PREFIX/glibc/          # GNU C Library
│   ├── lib/ld-linux-aarch64.so.1
│   └── bin/bash, env, patchelf
├── $PREFIX/bin/ruby        # Ruby 3.4.1
├── $PREFIX/bin/git         # Git 2.55.0
└── ~/brew/                 # Homebrew
    ├── bin/brew            # Original brew
    ├── bin/brew-termux     # Wrapper with auto-patchelf
    ├── bin/env -> glibc env
    ├── Cellar/             # Installed packages
    └── Library/Homebrew/   # Patched source
```

## How It Works

1. **Fork avoidance**: Android kernel blocks `pthread_rwlock_unlock` in forked processes. All `fork()` calls are replaced with `Process.spawn()`.

2. **glibc compatibility**: Homebrew bottles are built against glibc. Termux uses Bionic. The `patchelf` tool rewrites ELF binaries to use Termux's glibc linker and libraries.

3. **Hard-link fix**: Android's FUSE filesystem doesn't support hard links. The `brew-tar` wrapper handles this gracefully.

4. **Path redirection**: All references to `/bin/bash`, `/usr/bin/env`, `/usr/bin/ldd` are redirected to Termux equivalents.

5. **Patch persistence**: Git hooks re-apply patches after `brew update`.

## Installation

```bash
# Prerequisites
pkg install git ruby patchelf

# Install
bash <(curl -fsSL https://raw.githubusercontent.com/user/homebrew-termux/main/install.sh)

# Or clone and install
git clone https://github.com/user/homebrew-termux.git
cd homebrew-termux
bash install.sh
```

## Usage

```bash
# Using the wrapper (recommended)
brew-termux search wget
brew-termux install wget
brew-termux list

# Or add to PATH
export PATH="$HOME/brew/bin:$PATH"
brew search wget
```

## Uninstall

```bash
bash ~/homebrew-termux/uninstall.sh
```

## Testing

```bash
bash ~/homebrew-termux/test.sh
```

## How Patches Work

All patches are applied by `apply-patches.sh` which is:
- **Idempotent**: Safe to run multiple times
- **Detectable**: Each patch checks for a sentinel pattern before applying
- **Reversible**: `rollback.sh` reverts all changes via `git checkout`

Git hooks (`post-merge`, `post-checkout`, `post-rewrite`) automatically re-apply patches after `brew update`.

## ELF Binary Validation

After installing a package, validate the binary:

```bash
# Check file type
file ~/brew/Cellar/hello/2.12.3/bin/hello
# Expected: ELF 64-bit LSB pie executable, ARM aarch64

# Check interpreter
readelf -l ~/brew/Cellar/hello/2.12.3/bin/hello | grep interpreter
# Expected: interpreter: /data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1

# Check dependencies
readelf -d ~/brew/Cellar/hello/2.12.3/bin/hello | grep NEEDED
# Expected: libc.so.6 (glibc, not bionic)

# Run the binary
hello
# Expected: Hello, world!
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `bash test.sh`
5. Submit a pull request

## License

MIT License. Same as Homebrew.

## Acknowledgments

- [Homebrew](https://brew.sh/) - The original package manager
- [Termux](https://termux.dev/) - Android terminal emulator
- [patchelf](https://github.com/NixOS/patchelf) - ELF binary patching tool
