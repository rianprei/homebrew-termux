#!/data/data/com.termux/files/usr/bin/ruby
# frozen_string_literal: true
# Fix all Utils.safe_fork do; exec(*args); end call sites on Termux
# Replaces with direct Process.spawn + Process.wait + error check

require "pathname"

HOMEBREW_PREFIX = ENV.fetch("HOMEBREW_PREFIX") { File.expand_path("~/brew") }
H = Pathname.new(HOMEBREW_PREFIX) / "Library" / "Homebrew"

patches_applied = 0

# ─── 1. formula_installer.rb line ~1182 (build) ──────────────────────────────
f = H / "formula_installer.rb"
if f.exist?
  content = f.read
  # Exact 6-space indentation pattern
  old1 = "      Utils.safe_fork do\n        exec(*args)\n      end\n    end\n\n    formula.update_head_version"
  new1 = "      # Termux: Process.spawn instead of Utils.safe_fork (fork crashes on Android)\n      pid = Process.spawn(*args)\n      Process.wait(pid)\n      raise BuildError.new(formula, args, nil, formula.options) unless $CHILD_STATUS.success?\n    end\n\n    formula.update_head_version"

  if content.include?(old1)
    content.sub!(old1, new1)
    patches_applied += 1
    puts "  [OK] formula_installer.rb: build safe_fork → Process.spawn"
  else
    puts "  [SKIP] formula_installer.rb: build pattern not found (already patched?)"
  end

  # ─── 2. formula_installer.rb line ~1426 (postinstall) ──────────────────────
  # 8-space indentation
  old2 = "        Utils.safe_fork do\n          exec(*args)\n        end\n      end\n    end\n  # Handle all possible exceptions when postinstall"
  new2 = "        # Termux: Process.spawn instead of Utils.safe_fork (fork crashes on Android)\n        pid = Process.spawn(*args)\n        Process.wait(pid)\n        raise BuildError.new(formula, args, nil, formula.options) unless $CHILD_STATUS.success?\n      end\n    end\n  # Handle all possible exceptions when postinstall"

  if content.include?(old2)
    content.sub!(old2, new2)
    patches_applied += 1
    puts "  [OK] formula_installer.rb: postinstall safe_fork → Process.spawn"
  else
    puts "  [SKIP] formula_installer.rb: postinstall pattern not found (already patched?)"
  end

  f.write(content) if patches_applied > 0
end

# ─── 3. dev-cmd/test.rb line ~101 ────────────────────────────────────────────
f = H / "dev-cmd" / "test.rb"
if f.exist?
  content = f.read
  # 14-space indentation
  old3 = "              Utils.safe_fork do\n                exec(*exec_args)\n              end"
  new3 = "              # Termux: Process.spawn instead of Utils.safe_fork (fork crashes on Android)\n              pid = Process.spawn(*exec_args)\n              Process.wait(pid)\n              raise ErrorDuringExecution.new(exec_args, status: $CHILD_STATUS) unless $CHILD_STATUS.success?"

  if content.include?(old3)
    content.sub!(old3, new3)
    f.write(content)
    patches_applied += 1
    puts "  [OK] dev-cmd/test.rb: safe_fork → Process.spawn"
  else
    puts "  [SKIP] dev-cmd/test.rb: pattern not found (already patched?)"
  end
end

puts "\nApplied #{patches_applied} patch(es)"
exit(patches_applied > 0 ? 0 : 1)
