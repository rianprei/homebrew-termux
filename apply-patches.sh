#!/data/data/com.termux/files/usr/bin/bash
# homebrew-termux: apply patches to Homebrew for native Termux operation
# Idempotent — safe to run repeatedly.
set -euo pipefail

BREW="${1:-$HOME/brew}"
H="${BREW}/Library/Homebrew"
PATCH_DIR="${HOME}/.homebrew/homebrew-termux/patches"
APPLIED=0

red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
info()  { green "[homebrew-termux] $*"; }

[[ -d "$H" ]] || { red "Homebrew not found at $BREW"; exit 1; }
[[ -f /data/data/com.termux/files/usr/etc/os-release ]] || { red "Not Termux"; exit 1; }

# --- helper: patch only if pattern absent ---
need() { ! grep -q "$1" "$2" 2>/dev/null; }

# ─── 1. bin/brew ─────────────────────────────────────────────────────────────
f="$BREW/bin/brew"
if [[ -f "$f" ]]; then
  if need 'data/data/com.termux/files/usr/glibc/bin/bash' "$f"; then
    sed -i '1s|#!/bin/bash|#!/data/data/com.termux/files/usr/glibc/bin/bash|' "$f"
    info "bin/brew shebang"; APPLIED=$((APPLIED+1))
  fi
  if need 'data/data/com.termux/files/usr/bin/env' "$f"; then
    sed -i 's|exec /bin/bash|exec /data/data/com.termux/files/usr/glibc/bin/bash|g' "$f"
    sed -i 's|exec /usr/bin/env -i|exec /data/data/com.termux/files/usr/bin/env -i|g' "$f"
    sed -i 's| /bin/bash -p| /data/data/com.termux/files/usr/glibc/bin/bash -p|g' "$f"
    info "bin/brew exec paths"; APPLIED=$((APPLIED+1))
  fi
fi

# ─── 2. brew.sh — skip sudo reset ───────────────────────────────────────────
f="$H/brew.sh"
if [[ -f "$f" ]] && need 'HOMEBREW_TERMUX' "$f"; then
  sed -i '/# Reset sudo timestamp to avoid running unauthorized sudo commands/,/^fi$/{
    s|if \[\[ -n "\${SUDO}" \]\]|if [[ -n "${SUDO}" \&\& -z "${HOMEBREW_TERMUX}" ]]|
  }' "$f"
  info "brew.sh sudo guard"; APPLIED=$((APPLIED+1))
fi

# ─── 3. utils/os.sh — Termux detection + os-release ─────────────────────────
f="$H/utils/os.sh"
if [[ -f "$f" ]]; then
  if need 'HOMEBREW_TERMUX' "$f"; then
    sed -i '/HOMEBREW_PHYSICAL_PROCESSOR="${HOMEBREW_PROCESSOR}"/a\
\
# homebrew-termux detection\
if [[ -f "/data/data/com.termux/files/usr/etc/os-release" ]]; then\
  HOMEBREW_TERMUX=1\
  export HOMEBREW_TERMUX\
fi' "$f"
    info "os.sh termux detection"; APPLIED=$((APPLIED+1))
  fi
  if need 'source /data/data/com.termux/files/usr/etc/os-release' "$f"; then
    sed -i '/source \/etc\/os-release/c\
      if [[ -f "/data/data/com.termux/files/usr/etc/os-release" ]]; then\
        HOMEBREW_OS_VERSION="$(source /data/data/com.termux/files/usr/etc/os-release && echo "${PRETTY_NAME}")"\
      else\
        HOMEBREW_OS_VERSION="$(source /etc/os-release && echo "${PRETTY_NAME}")"\
      fi' "$f"
    info "os.sh os-release path"; APPLIED=$((APPLIED+1))
  fi
fi

# ─── 4. utils/ruby.sh — Ruby 3.4 + skip portable ruby ──────────────────────
f="$H/utils/ruby.sh"
if [[ -f "$f" ]]; then
  if need 'HOMEBREW_REQUIRED_RUBY_VERSION="3.4"' "$f"; then
    sed -i '/export HOMEBREW_REQUIRED_RUBY_VERSION="4.0"/c\
# homebrew-termux: use Ruby 3.4 (Termux ships 3.4.x)\
if [[ -f "/data/data/com.termux/files/usr/etc/os-release" ]]; then\
  export HOMEBREW_REQUIRED_RUBY_VERSION="3.4"\
else\
  export HOMEBREW_REQUIRED_RUBY_VERSION="4.0"\
fi' "$f"
    info "ruby.sh version"; APPLIED=$((APPLIED+1))
  fi
  if need 'homebrew-termux: skip portable ruby' "$f"; then
    sed -i '/# Needed for `brew` and `odie`./a\
\
  # homebrew-termux: skip portable ruby, use system ruby\
  if [[ -f "/data/data/com.termux/files/usr/etc/os-release" ]]; then\
    HOMEBREW_RUBY_PATH="$(find_ruby)"\
    if [[ -z "${HOMEBREW_RUBY_PATH}" ]]; then\
      HOMEBREW_RUBY_PATH="/data/data/com.termux/files/usr/bin/ruby"\
    fi\
    return 0\
  fi' "$f"
    info "ruby.sh skip portable"; APPLIED=$((APPLIED+1))
  fi
fi

# ─── 5. global.rb — Homebrew.termux? ────────────────────────────────────────
f="$H/global.rb"
if [[ -f "$f" ]] && need 'def termux?' "$f"; then
  sed -i '/class << self/a\
    sig { returns(T::Boolean) }\
    def termux?\
      @termux ||= T.let(File.exist?("/data/data/com.termux/files/usr/etc/os-release"), T.nilable(T::Boolean))\
    end' "$f"
  info "global.rb termux?"; APPLIED=$((APPLIED+1))
fi

# ─── 6. system_command.rb — env prefix + fork avoidance ─────────────────────
f="$H/system_command.rb"
if [[ -f "$f" ]]; then
  # env_prefix: use $PREFIX/bin/env on Termux
  if need 'homebrew-termux.*use.*PREFIX.*bin.*env' "$f"; then
    sed -i '/def env_prefix/,/^  end$/{
      s|\["/usr/bin/env", \*env_args\]|# homebrew-termux: use \$PREFIX/bin/env on Android\
    env_path = if Homebrew.termux?\
      File.exist?("\#{HOMEBREW_PREFIX}/bin/env") ? "\#{HOMEBREW_PREFIX}/bin/env" : "/data/data/com.termux/files/usr/bin/env"\
    else\
      "/usr/bin/env"\
    end\
    [env_path, *env_args]|
    }' "$f"
    info "system_command.rb env_prefix"; APPLIED=$((APPLIED+1))
  fi

  # fork avoidance: use spawn-only on Termux (complex patch — skip if already applied)
  if ! grep -q 'homebrew-termux.*Android blocks pthread' "$f" 2>/dev/null; then
    info "system_command.rb fork avoidance: SKIPPED (apply manually)"
  fi
fi

# ─── 7. utils/popen.rb — spawn instead of fork ──────────────────────────────
f="$H/utils/popen.rb"
if [[ -f "$f" ]] && need 'Homebrew.termux?' "$f"; then
  sed -i '/if ENV\["HOMEBREW_SPAWN_SYSTEM"\] == "1"/c\    # homebrew-termux: avoid fork (pthread crash on Android)\
    if Homebrew.termux? || ENV["HOMEBREW_SPAWN_SYSTEM"] == "1"' "$f"
  info "popen.rb spawn"; APPLIED=$((APPLIED+1))
fi

# ─── 8. os/linux/glibc.rb — ldd path ────────────────────────────────────────
f="$H/os/linux/glibc.rb"
if [[ -f "$f" ]]; then
  if need 'Homebrew.termux?' "$f"; then
    # Patch both system_version and version methods to use Termux glibc ldd
    sed -i 's|version = Utils\.popen_read("/usr/bin/ldd", "--version")|version = Utils.popen_read(Homebrew.termux? ? "/data/data/com.termux/files/usr/glibc/bin/ldd" : "/usr/bin/ldd", "--version")|' "$f"
    sed -i 's|version = Utils\.popen_read(HOMEBREW_PREFIX/"opt/glibc/bin/ldd", "--version")|version = Utils.popen_read(Homebrew.termux? ? "/data/data/com.termux/files/usr/glibc/bin/ldd" : HOMEBREW_PREFIX/"opt/glibc/bin/ldd", "--version")|' "$f"
    info "glibc.rb ldd paths"; APPLIED=$((APPLIED+1))
  fi
fi

# ─── 9. Shell shims ─────────────────────────────────────────────────────────
for s in curl git; do
  sf="$H/shims/shared/$s"
  if [[ -f "$sf" ]] && head -1 "$sf" | grep -q '#!/bin/bash'; then
    sed -i '1s|#!/bin/bash|#!/data/data/com.termux/files/usr/glibc/bin/bash|' "$sf"
    info "shim $s shebang"; APPLIED=$((APPLIED+1))
  fi
done

# ─── 10. list.sh — env_cmd ──────────────────────────────────────────────────
f="$H/list.sh"
if [[ -f "$f" ]] && need 'env_cmd' "$f"; then
  sed -i '/homebrew-list() {/a\
\
  # homebrew-termux: use $PREFIX/bin/env\
  local env_cmd="/usr/bin/env"\
  if [[ -f "/data/data/com.termux/files/usr/etc/os-release" ]]; then\
    env_cmd="/data/data/com.termux/files/usr/bin/env"\
  fi' "$f"
  sed -i 's|/usr/bin/env "${ls_env\[@\]}" ls|${env_cmd} "${ls_env[@]}" ls|g' "$f"
  info "list.sh env_cmd"; APPLIED=$((APPLIED+1))
fi

# ─── 11. cmd/vendor-install.sh — ldd path ───────────────────────────────────
f="$H/cmd/vendor-install.sh"
if [[ -f "$f" ]] && need 'data/data/com.termux/files/usr/glibc/bin/ldd' "$f"; then
  sed -i 's|/usr/bin/ldd|/data/data/com.termux/files/usr/glibc/bin/ldd|g' "$f"
  info "vendor-install.sh ldd"; APPLIED=$((APPLIED+1))
fi

# ─── 12. Gemfile ─────────────────────────────────────────────────────────────
f="$H/Gemfile"
if [[ -f "$f" ]] && need 'ruby "~> 3.4.0"' "$f"; then
  sed -i 's/ruby "~> 4.0.0"/ruby "~> 3.4.0"/' "$f"
  info "Gemfile ruby"; APPLIED=$((APPLIED+1))
fi

# ─── 13. Gemfile.lock ────────────────────────────────────────────────────────
f="$H/Gemfile.lock"
if [[ -f "$f" ]]; then
  if need 'aarch64-linux-android' "$f"; then
    sed -i '/^  aarch64-linux$/a\  aarch64-linux-android' "$f"
    info "Gemfile.lock platform"; APPLIED=$((APPLIED+1))
  fi
  if need 'ruby 3.4.1' "$f"; then
    sed -i 's/ruby 4.0.6/ruby 3.4.1/' "$f"
    info "Gemfile.lock ruby"; APPLIED=$((APPLIED+1))
  fi
fi

# ─── 14. vendor/portable-ruby-version ────────────────────────────────────────
f="$H/vendor/portable-ruby-version"
if [[ -f "$f" ]] && need '3.4.6' "$f"; then
  echo "3.4.6" > "$f"
  info "portable-ruby-version"; APPLIED=$((APPLIED+1))
fi

# ─── 15. unpack_strategy/tar.rb — hard-link fix ────────────────────────────
f="$H/unpack_strategy/tar.rb"
if [[ -f "$f" ]] && need 'Homebrew.termux?.*brew-tar' "$f"; then
  sed -i '/system_command! "tar",/{
    a\        tar_cmd = if Homebrew.termux? \&\& File.exist?("/data/data/com.termux/files/usr/bin/brew-tar")\n          "/data/data/com.termux/files/usr/bin/brew-tar"\n        else\n          "tar"\n        end
    s|system_command! "tar",|system_command! tar_cmd,|
  }' "$f"
  info "tar.rb brew-tar wrapper"; APPLIED=$((APPLIED+1))
fi

# ─── 16. brew-tar wrapper ────────────────────────────────────────────────────
TAR_WRAPPER="/data/data/com.termux/files/usr/bin/brew-tar"
if [[ ! -x "$TAR_WRAPPER" ]]; then
  cat > "$TAR_WRAPPER" << 'TARWRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
real_tar="/data/data/com.termux/files/usr/bin/tar"
tmperr="$(mktemp)"
"$real_tar" "$@" 2>"$tmperr"
rc=$?
if [[ $rc -ne 0 ]]; then
  if grep -qvE "Cannot hard link|can't link|Exiting with failure status|had errors" "$tmperr" 2>/dev/null; then
    cat "$tmperr" >&2
    rm -f "$tmperr"
    exit $rc
  fi
  rm -f "$tmperr"
  exit 0
fi
rm -f "$tmperr"
exit 0
TARWRAPPER
  chmod +x "$TAR_WRAPPER"
  info "brew-tar wrapper"; APPLIED=$((APPLIED+1))
fi

# ─── summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== homebrew-termux: $APPLIED patch(es) applied ==="
if [[ $APPLIED -gt 0 ]]; then
  echo "Run:  $BREW/bin/brew-termux <command>"
fi

# ─── 17. homebrew.rb — fork avoidance ────────────────────────────────────────
f="$H/homebrew.rb"
if [[ -f "$f" ]] && ! grep -q 'Termux: use Process.spawn instead of fork' "$f"; then
  sed -i '/def self._system/,/^  end/{
    /pid = fork do/c\
# Termux: use Process.spawn instead of fork (fork crashes with pthread_rwlock_unlock)\
args.map!(&:to_s)\
stdout_r, stdout_w = IO.pipe\
stderr_r, stderr_w = IO.pipe\
opts = options.merge(out: stdout_w, err: stderr_w)\
pid = begin\
  if argv0\
    Process.spawn(cmd, argv0, *args, **opts)\
  else\
    Process.spawn(cmd, *args, **opts)\
  end\
rescue\
  stdout_w.close; stderr_w.close; stdout_r.close; stderr_r.close\
  return false\
end\
stdout_w.close; stderr_w.close\
Thread.new(stdout_r, &:read)\
Thread.new(stderr_r, &:read)\
Process.wait(pid)\
$CHILD_STATUS.success? || false
  }' "$f"
  info "homebrew.rb fork avoidance"; APPLIED=$((APPLIED+1))
fi

# ─── 18. formula_installer.rb — fork avoidance (build + postinstall) ──────────
# Instead of patching utils/fork.rb (which uses fork+block that cannot be replaced by Process.spawn),
# we patch formula_installer.rb to bypass Utils.safe_fork entirely and use Process.spawn directly.
f="$H/formula_installer.rb"
if [[ -f "$f" ]] && ! grep -q "Termux: use Process.spawn directly" "$f"; then
  sed -i 's|      Utils.safe_fork do\n        exec(\*args)\n      end\n    end\n\n    formula.update_head_version|      # Termux: use Process.spawn directly (fork crashes with pthread_rwlock_unlock)\n      Process.spawn(\*args)\n      Process.wait\n      raise BuildError.new(formula, args, nil, formula.options) unless $CHILD_STATUS.success?\n    end\n\n    formula.update_head_version|' "$f"
  sed -i 's|        Utils.safe_fork do\n          exec(\*args)\n        end\n      end\n    end\n  # Handle all possible exceptions when postinstall does not complete.|        # Termux: use Process.spawn directly (fork crashes with pthread_rwlock_unlock)\n        Process.spawn(\*args)\n        Process.wait\n        raise BuildError.new(formula, args, nil, formula.options) unless $CHILD_STATUS.success?\n      end\n    end\n  # Handle all possible exceptions when postinstall does not complete.|' "$f"
  info "formula_installer.rb fork avoidance"; APPLIED=$((APPLIED+1))
fi


# ─── 19. formula.rb — fork avoidance ─────────────────────────────────────────
f="$H/formula.rb"
if [[ -f "$f" ]] && ! grep -q 'Termux: use Process.spawn instead of fork' "$f"; then
  sed -i '/pid = fork do/,/end/{
    /pid = fork do/c\
          # Termux: use Process.spawn instead of fork\
          wr.close\
          pid = Process.spawn(cmd, *args.map(&:to_s), out: wr, err: wr)\
          wr.close rescue nil
    /rd.close/d
    /log.close/d
    /exec_cmd(cmd, args, wr, log_filename)/d
  }' "$f"
  sed -i '/pid = fork do/,/end/{
    /pid = fork do/c\
        # Termux: use Process.spawn instead of fork\
        pid = Process.spawn(cmd, *args.map(&:to_s), out: log, err: log)
    /exec_cmd(cmd, args, log, log_filename)/d
  }' "$f"
  info "formula.rb fork avoidance"; APPLIED=$((APPLIED+1))
fi

# ─── 20. extend/kernel.rb — fork avoidance ───────────────────────────────────
f="$H/extend/kernel.rb"
if [[ -f "$f" ]] && ! grep -q 'Termux: use Process.spawn instead of fork' "$f"; then
  sed -i 's|Process.wait fork { exec Utils::Shell.preferred_path(default: "/bin/bash") }|# Termux: use Process.spawn instead of fork\
      pid = Process.spawn(Utils::Shell.preferred_path(default: "/bin/bash"))\
      Process.wait(pid)|' "$f"
  info "extend/kernel.rb fork avoidance"; APPLIED=$((APPLIED+1))
fi

# ─── 21. utils/gem_setup.rb — fork avoidance ─────────────────────────────────
f="$H/utils/gem_setup.rb"
if [[ -f "$f" ]] && ! grep -q 'Termux: use Process.spawn instead of fork' "$f"; then
  sed -i '/Process.wait(fork do/,/end)/{
    /Process.wait(fork do/c\
        # Termux: use Process.spawn instead of fork\
        pid = Process.spawn(bundle, "install", out: :err)\
        Process.wait(pid)
    /Process::UID.change_privilege/d
    /exec bundle, "install", out: :err/d
    /end)/d
  }' "$f"
  info "utils/gem_setup.rb fork avoidance"; APPLIED=$((APPLIED+1))
fi

# ─── 22. dependency_collector.rb — skip bubblewrap on Termux ──────────────────
f="$H/extend/os/linux/dependency_collector.rb"
if [[ -f "$f" ]] && ! grep -q 'Homebrew.termux?' "$f"; then
  sed -i '/def bubblewrap_dependency_needed?/,/^      end/{
    /return false if OS::Linux::Sandbox.landlock?/a\
        # Termux: bubblewrap cannot work (no unprivileged user namespaces)\
        return false if Homebrew.termux?
  }' "$f"
  info "dependency_collector.rb bubblewrap skip"; APPLIED=$((APPLIED+1))
fi

# ─── 23. system_command.rb — fork avoidance + env_prefix ──────────────────────
f="$H/system_command.rb"
if [[ -f "$f" ]] && ! grep -q 'Termux: skip privilege changes' "$f"; then
  sed -i '/pid ||= fork do/,/end/{
    /pid ||= fork do/c\
    pid ||= begin\
      # Termux: skip privilege changes (not available without root)\
      Process.spawn(exec_env, [executable, executable], *args, **options)\
    rescue SystemCallError => e\
      $stderr.puts(e.message)\
      exit!(127)\
    end
    /if run_as_real_uid?/d
    /Process::UID.change_privilege/d
    /exec(exec_env, \[executable, executable\], \*args, \*\*options)/d
    /^    end$/d
  }' "$f"
  info "system_command.rb fork avoidance"; APPLIED=$((APPLIED+1))
fi
