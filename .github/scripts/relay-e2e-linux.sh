#!/usr/bin/env bash
set -euo pipefail

assert_equal() {
  local check="$1" expected="$2" actual="$3"
  printf 'CHECK %s | expected: %s | actual: %s\n' "$check" "$expected" "$actual"
  if [[ "$actual" != "$expected" ]]; then exit 1; fi
}
assert_contains() {
  local check="$1" expected="$2" actual="$3"
  printf 'CHECK %s | expected: %s | actual: %s\n' "$check" "$expected" "$actual"
  if [[ "$actual" != *"$expected"* ]]; then exit 1; fi
}
assert_file() {
  local actual=missing
  if [[ -f "$2" ]]; then actual=present; fi
  assert_equal "$1 ($2)" present "$actual"
}
assert_usage() {
  assert_contains "$1 Claude usage" 'claude: source=statusline error=- session=23' "$2"
  assert_contains "$1 Codex usage" 'codex: source=logs error=- session=15' "$2"
}

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
config="$XDG_DATA_HOME/aimana/setup.json"
mkdir -p "$CLAUDE_CONFIG_DIR/projects" "$CODEX_HOME/sessions/2026/10/12"
cp AImana/Relay/Tests/Fixtures/codex-session.jsonl "$CODEX_HOME/sessions/2026/10/12/session.jsonl"
printf '%s' '{"theme":"dark"}' > "$settings"
cleanup() { "$relay" uninstall >/dev/null || true; rm -rf "$root"; }
trap cleanup EXIT

setup_output="$("$relay" setup --output "$output" --interval 1)"
printf '%s\n' "$setup_output"
assert_file 'initial output' "$output"
assert_file 'saved setup configuration' "$config"
initial_check="$("$relay" check "$output")"
assert_contains 'initial output decodes' 'version ' "$initial_check"
command="$(perl -MJSON::PP -0777 -ne 'print decode_json($_)->{statusLine}{command}' "$settings")"
assert_contains 'configured statusline command' 'statusline.sh' "$command"
status_text="$(sh -c "$command" < AImana/Relay/Tests/Fixtures/statusline.json)"
assert_equal 'configured statusline text' 'CI Opus' "$status_text"
assert_file 'statusline capture file' "$capture"
captured_at="$(perl -MJSON::PP -0777 -ne 'print decode_json($_)->{capturedAt} // ""' "$capture")"
assert_equal 'statusline capture timestamp present' true "$([[ -n "$captured_at" ]] && echo true || echo false)"

"$relay" run --output "$output" --no-costs
captured_check="$("$relay" check "$output")"
assert_usage 'published after capture' "$captured_check"

if [[ "$setup_output" == *'systemd user timer installed'* ]]; then
  enabled="$(systemctl --user is-enabled aimana-relay.timer)"
  assert_equal 'systemd timer enabled' enabled "$enabled"
  service="$(cat "$HOME/.config/systemd/user/aimana-relay.service")"
  assert_contains 'systemd run configuration' "run --config \"$config\"" "$service"
  before="$(stat -c %Y "$output")"
  sleep 2
  systemctl --user start aimana-relay.service
  changed=false
  for _ in $(seq 1 60); do
    if (( $(stat -c %Y "$output") > before )); then changed=true; break; fi
    sleep 1
  done
  assert_equal 'scheduled output modification' true "$changed"
  scheduled_check="$("$relay" check "$output")"
  assert_usage 'scheduled' "$scheduled_check"
  doctor_output="$("$relay" doctor)"
  assert_contains 'doctor recent capture' '(recent)' "$doctor_output"
else
  assert_contains 'systemd unavailable' 'systemd user manager unavailable' "$setup_output"
  assert_contains 'cron cadence' '*/1 * * * *' "$setup_output"
  assert_contains 'cron run configuration' "run --config '$config'" "$setup_output"
  cron_line="$(printf '%s\n' "$setup_output" | grep '^\*/1 \* \* \* \* ')"
  cron_command="${cron_line#\*/1 \* \* \* \* }"
  env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME sh -c "$cron_command"
  cron_check="$("$relay" check "$output")"
  assert_usage 'cron fallback' "$cron_check"
  doctor_ok=false
  doctor_output="$("$relay" doctor)" && doctor_ok=true || true
  assert_contains 'doctor recent capture' '(recent)' "$doctor_output"
  assert_equal 'doctor detects missing scheduler' false "$doctor_ok"
fi
"$relay" uninstall
trap - EXIT
restored_settings="$(cat "$settings")"
assert_equal 'settings restored' '{"theme":"dark"}' "$restored_settings"
if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  enabled=false
  systemctl --user is-enabled aimana-relay.timer >/dev/null 2>&1 && enabled=true || true
  assert_equal 'timer removed' false "$enabled"
fi
rm -rf "$root"
