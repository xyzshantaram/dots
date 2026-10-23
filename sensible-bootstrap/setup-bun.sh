#!/usr/bin/env bash
# ---
# script: setup-bun.sh
# desc:   Optional. Installs Bun system-wide and smoke-tests Bun Shell.
#         Not needed to run the ladder: `bun run ladder` re-execs itself with
#         the absolute path of the bun that started it, so sudo does not need
#         bun on PATH. Kept for a machine where bun is not installed at all.
# needs:  curl, unzip (only when it has to install)
# do:     finds bun on PATH, else reuses ~/.bun/bin/bun, else installs to
#         /usr/local via Bun's official installer. Then smoke-tests Bun Shell.
# undo:   rm -f /usr/local/bin/bun /usr/local/share/bun; leaves ~/.bun alone
# revisit: 2026-12-21
# ---
set -euo pipefail

BUN_INSTALL_DIR=/usr/local
SMOKE="$(mktemp /tmp/bun-smoke.XXXXXX.ts)"
trap 'rm -f "$SMOKE"' EXIT

say() { printf 'setup-bun: %s\n' "$*"; }
die() { printf 'setup-bun: error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0"

say "existing bun: $(command -v bun || echo none)"

if ! command -v bun >/dev/null 2>&1; then
    if [ -x /usr/local/bin/bun ]; then
        say "using /usr/local/bin/bun"
    elif [ -x "$HOME/.bun/bin/bun" ] && [ -n "${SUDO_USER:-}" ]; then
        # Reuse the invoking user's copy rather than downloading again.
        user_bun="$(getent passwd "$SUDO_USER" | cut -d: -f6)/.bun/bin/bun"
        if [ -x "$user_bun" ]; then
            say "copying $user_bun to /usr/local/bin/bun"
            install -Dm755 "$user_bun" /usr/local/bin/bun
        fi
    fi
fi

if ! command -v bun >/dev/null 2>&1; then
    command -v curl >/dev/null 2>&1 || die "curl is required to install bun"
    command -v unzip >/dev/null 2>&1 || die "unzip is required to install bun"
    say "installing bun into $BUN_INSTALL_DIR"
    BUN_INSTALL="$BUN_INSTALL_DIR" bash -c \
        'curl -fsSL https://bun.sh/install | bash' >/dev/null
fi

command -v bun >/dev/null 2>&1 || die "bun is still not on PATH after install"
say "bun $(bun --version) at $(command -v bun)"

# Smoke-test the features the ladder relies on: array argument spreading,
# interpolation escaping, and .nothrow() exit codes.
cat > "$SMOKE" <<'EOF'
import { $ } from "bun";
const args = ["-a", "two words", "-b"];
const spread = await $`printf '[%s]' ${args}`.text();
const escaped = await $`printf '%s' ${"a; rm -rf /nope"}`.text();
const failed = await $`false`.nothrow().quiet();
if (spread !== "[-a][two words][-b]") throw new Error(`array spread broken: ${spread}`);
if (escaped !== "a; rm -rf /nope") throw new Error(`escaping broken: ${escaped}`);
if (failed.exitCode !== 1) throw new Error(`nothrow broken: ${failed.exitCode}`);
console.log("bun shell ok");
EOF

if ! out="$(bun run "$SMOKE" 2>&1)"; then
    printf '%s\n' "$out" >&2
    die "Bun Shell smoke test failed"
fi
say "$out"

if ! bun -e 'Bun.file' >/dev/null 2>&1; then
    die "bun cannot evaluate TypeScript"
fi

say "ready — next: bun run ladder up --only 00-check"
