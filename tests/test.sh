#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nikkigo-tests-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP"

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

for layout in ui-root ui-dist; do
	state="$TMP/$layout-state"
	run="$TMP/$layout-run"
	mkdir -p "$state/ui/unpack" "$run"
	cp -R "$ROOT/tests/fixtures/$layout"/. "$state/ui/unpack/"
	index="$(find "$state/ui/unpack" -type f -name index.html | head -n 1)"
	printf '%s\n' "${index%/*}" > "$state/ui/source-dir"
	(
		NIKKIGO_STATE_DIR="$state"
		NIKKIGO_RUN="$run"
		. "$ROOT/router-safety.sh"
		ensure_zashboard
	)
	[ -f "$run/ui/index.html" ] || fail "$layout normalization"
	pass "$layout normalization"
done

grep -q 'sudoku' "$ROOT/tests/fixtures/select-broken.yaml" &&
	grep -q 'trusttunnel' "$ROOT/tests/fixtures/select-broken.yaml" ||
	fail 'broken selector fixture'
pass 'broken selector fixture'

grep -q 'DIRECT' "$ROOT/tests/fixtures/success.yaml" ||
	fail 'successful profile fixture'
! grep -q 'DIRECT' "$ROOT/tests/fixtures/without-direct.yaml" ||
	fail 'profile without DIRECT fixture'
pass 'profile fixtures'

fresh="$TMP/fresh-install"
mkdir -p "$fresh/bin"
cat > "$fresh/bin/uci" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$fresh/bin/uci"
(
	PATH="$fresh/bin:$PATH"
	NIKKIGO_CONFIG="$fresh/missing-nikki-config"
	NIKKIGO_SERVICE="$fresh/missing-nikki-service"
	. "$ROOT/router-safety.sh"
	enable_fail_open >/dev/null
) || fail 'fresh install fail-open without UCI config'
pass 'fresh install fail-open without UCI config'

(
	PATH="$fresh/bin:$PATH"
	NIKKIGO_STATE_DIR="$fresh/empty-state"
	NIKKIGO_CONFIG="$fresh/missing-nikki-config"
	NIKKIGO_SUBSCRIPTIONS="$fresh/missing-subscriptions"
	NIKKIGO_SERVICE="$fresh/missing-nikki-service"
	. "$ROOT/router-safety.sh"
	backup_state
	[ "$NIKKIGO_TRANSACTION" = '1' ]
	[ "$(cat "$NIKKIGO_STATE_DIR/enabled")" = '0' ]
	[ "$(cat "$NIKKIGO_STATE_DIR/running")" = '0' ]
) || fail 'backup on completely fresh router'
pass 'backup on completely fresh router'

grep -q 'restore_state' "$ROOT/router-update.sh" &&
	grep -q 'health_check' "$ROOT/router-update.sh" &&
	grep -q 'try_recover_proxies' "$ROOT/router-update.sh" ||
	fail 'transactional updater wiring'
pass 'transactional updater wiring'

grep -q '\[ "$tested" -lt 8 \]' "$ROOT/router-safety.sh" &&
	grep -q 'timeout=4000' "$ROOT/router-safety.sh" ||
	fail 'bounded proxy recovery'
pass 'bounded proxy recovery'

redacted="$(
	printf '%s\n' 'url=https://example.com/private?token=abc password=hunter2 secret=xyz' |
		(
			. "$ROOT/router-safety.sh"
			redact_stream
		)
)"
printf '%s' "$redacted" | grep -q 'example.com' &&
	fail 'diagnostic URL redaction'
printf '%s' "$redacted" | grep -q 'hunter2' &&
	fail 'diagnostic password redaction'
printf '%s' "$redacted" | grep -q 'secret=xyz' &&
	fail 'diagnostic secret redaction'
pass 'diagnostic secret redaction'

grep -q 'OpenWrt:' "$ROOT/router-install.sh" &&
	grep -q 'Состояние службы:' "$ROOT/router-install.sh" &&
	grep -q 'Свободно в /overlay:' "$ROOT/router-install.sh" ||
	fail 'technical diagnostic context'
pass 'technical diagnostic context'
