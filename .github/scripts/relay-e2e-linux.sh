#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${AIMANA_RELAY_BIN:-}" ]]; then
  relay="$AIMANA_RELAY_BIN"
else
  bin="$(swift build -c release --package-path AImana/Relay --show-bin-path)"
  relay="$bin/usage-relay"
fi
root="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$root/profile/.claude"
export CODEX_HOME="$root/profile/.codex"
export XDG_DATA_HOME="$root/data"
export XDG_CACHE_HOME="$root/cache"
settings="$CLAUDE_CONFIG_DIR/settings.json"
output="$root/out/usage-relay.json"
capture="$XDG_DATA_HOME/aimana/claude-statusline.json"
mkdir -p "$CLAUDE_CONFIG_DIR/projects" "$CODEX_HOME/sessions/2026/10/12"
cp AImana/Relay/Tests/Fixtures/codex-session.jsonl "$CODEX_HOME/sessions/2026/10/12/session.jsonl"
printf '%s' '{"theme":"dark"}' > "$settings"
cleanup() { "$relay" uninstall >/dev/null || true; rm -rf "$root"; }
trap cleanup EXIT

setup_output="$("$relay" setup --output "$output" --interval 1)"
printf '%s\n' "$setup_output"
test -f "$output"
"$relay" check "$output"
command="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["statusLine"]["command"])' "$settings")"
test -n "$command"
sh -c "$command" < AImana/Relay/Tests/Fixtures/statusline.json
test -f "$capture"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["capturedAt"]' "$capture"

if printf '%s' "$setup_output" | grep -q 'systemd user timer installed'; then
  systemctl --user is-enabled aimana-relay.timer
  before="$(stat -c %Y "$output")"
  sleep 2
  systemctl --user start aimana-relay.service
  changed=false
  for _ in $(seq 1 60); do
    if (( $(stat -c %Y "$output") > before )); then changed=true; break; fi
    sleep 1
  done
  test "$changed" = true
  "$relay" doctor | grep -q '(recent)'
else
  printf '%s\n' "$setup_output" | grep -q 'systemd user manager unavailable'
  printf '%s\n' "$setup_output" | grep -qF '*/1 * * * *'
  doctor_output="$("$relay" doctor)" && doctor_ok=true || doctor_ok=false
  printf '%s\n' "$doctor_output" | grep -q '(recent)'
  if test "$doctor_ok" = true; then
    echo 'doctor unexpectedly accepted a missing scheduler' >&2
    exit 1
  fi
fi
"$relay" uninstall
trap - EXIT
test "$(cat "$settings")" = '{"theme":"dark"}'
if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  ! systemctl --user is-enabled aimana-relay.timer >/dev/null 2>&1
fi
rm -rf "$root"
