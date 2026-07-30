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

grep -q 'restore_state' "$ROOT/router-update.sh" &&
	grep -q 'health_check' "$ROOT/router-update.sh" ||
	fail 'transactional updater wiring'
pass 'transactional updater wiring'
