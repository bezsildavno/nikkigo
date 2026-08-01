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

grep -q 'recovery-first-round.tsv' "$ROOT/router-safety.sh" &&
	grep -q 'delay-test прошли' "$ROOT/router-safety.sh" ||
	fail 'round-robin proxy recovery diagnostics'
pass 'round-robin proxy recovery diagnostics'

encoded="$(
	. "$ROOT/router-safety.sh"
	url_encode 'Тест 🌍'
)"
[ "$encoded" = '%D0%A2%D0%B5%D1%81%D1%82%20%F0%9F%8C%8D' ] ||
	fail 'BusyBox-only UTF-8 URL encoding'
! grep -q 'od -An' "$ROOT/router-safety.sh" ||
	fail 'URL encoding must not depend on od'
pass 'BusyBox-only UTF-8 URL encoding'

grep -q 'Оставшиеся группы будут проверены функционально' "$ROOT/router-safety.sh" &&
	! grep -q '\[ "$selector_count" = "$choice_count" \]' "$ROOT/router-safety.sh" ||
	fail 'partial selector preparation is allowed'
pass 'partial selector preparation is allowed'

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

grep -q 'wget -qO- "$UPSTREAM_INSTALLER" | LUCI_I18N=1 ash' "$ROOT/router-install.sh" ||
	fail 'Russian package flag reaches upstream installer'
pass 'Russian package flag reaches upstream installer'

grep -q "C_YELLOW.*prompt" "$ROOT/router-install.sh" ||
	fail 'highlighted router input prompt'
pass 'highlighted router input prompt'

grep -q "subscription_name.*sub.csm.transib.services" "$ROOT/router-install.sh" &&
	grep -q "SUPPORT_MODE='provider'" "$ROOT/router-install.sh" &&
	grep -q "SUPPORT_MODE='transib'" "$ROOT/router-install.sh" ||
	fail 'provider-aware support routing'
pass 'provider-aware support routing'

grep -q 'Обратитесь в поддержку сервиса' "$ROOT/install.sh" &&
	! grep -q 'Telegram-бот' "$ROOT/install.sh" &&
	! grep -q 'SupportBot' "$ROOT/install.ps1" ||
	fail 'provider support before subscription domain is known'
pass 'provider support before subscription domain is known'

grep -q 'не смог автоматически определить адрес роутера' "$ROOT/install.sh" &&
	grep -q 'Предлагаемый адрес по умолчанию' "$ROOT/install-ru.ps1" &&
	grep -q 'could not detect the router address automatically' "$ROOT/install-en.ps1" ||
	fail 'honest router address fallback'
pass 'honest router address fallback'

grep -q '/etc/init.d/rpcd restart' "$ROOT/router-install.sh" &&
	grep -q 'ubus -S list luci.nikki' "$ROOT/router-install.sh" ||
	fail 'LuCI RPC backend registration'
pass 'LuCI RPC backend registration'

grep -q 'предоставляется «как есть»' "$ROOT/install.sh" &&
	grep -q 'Для подтверждения ответственности введите 322' "$ROOT/install.sh" ||
	fail 'explicit risk acknowledgement'
consent_line="$(grep -n "Для подтверждения ответственности введите 322" "$ROOT/install.sh" | head -n 1 | cut -d: -f1)"
banner_line="$(grep -n "NikkiGo — установка Taproom Nikki на OpenWrt" "$ROOT/install.sh" | head -n 1 | cut -d: -f1)"
[ "$consent_line" -lt "$banner_line" ] ||
	fail 'risk acknowledgement must be first'
pass 'explicit risk acknowledgement'

grep -q 'trap cancel_remote INT TERM' "$ROOT/router-install.sh" &&
	grep -q 'exit 0' "$ROOT/router-install.sh" &&
	! grep -q 'existing_support_host' "$ROOT/router-install.sh" ||
	fail 'clean cancellation without stale provider detection'
pass 'clean cancellation without stale provider detection'

grep -q 'Операция отменена. Изменения не внесены.' "$ROOT/router-install.sh" &&
	grep -q '\[ "$REPLY" != '\''322'\'' \]' "$ROOT/install.sh" &&
	grep -q "'1337'.*||" "$ROOT/router-install.sh" ||
	fail 'confirmation refusal exits cleanly'
pass 'confirmation refusal exits cleanly'

grep -q 'nikki restart >"$service_output" 2>&1' "$ROOT/router-install.sh" &&
	grep -q 'Ответ службы:' "$ROOT/router-install.sh" ||
	fail 'service restart output handling'
pass 'service restart output handling'

! grep -q 'base64' "$ROOT/install.sh" &&
	! grep -q 'base64' "$ROOT/install-ru.ps1" &&
	! grep -q 'base64' "$ROOT/install-en.ps1" &&
	! grep -q 'base64' "$ROOT/router-install.sh" ||
	fail 'router bootstrap must not require base64'
pass 'base64-free router bootstrap'

watchdog_patch='[ "$(uci -q get nikki.config.enabled)" = "1" ] || { rm -f /tmp/nikki-watchdog.failures; exit 0; }'
grep -Fq "PATCH_LINE='$watchdog_patch'" "$ROOT/router-install.sh" &&
	grep -q "UPLINK_LINE=" "$ROOT/router-install.sh" &&
	grep -q 'grep -Fq "$PATCH_LINE" "$WATCHDOG"' "$ROOT/router-install.sh" &&
	grep -q 'cp -p "$WATCHDOG" "$WATCHDOG_BACKUP"' "$ROOT/router-install.sh" &&
	grep -Fq 'sed -i "1a\\$PATCH_LINE" "$WATCHDOG"' "$ROOT/router-install.sh" &&
	grep -q 'chmod +x "$WATCHDOG"' "$ROOT/router-install.sh" &&
	grep -q 'sh -n "$WATCHDOG"' "$ROOT/router-install.sh" &&
	grep -q 'cp -p "$WATCHDOG_PREPATCH" "$WATCHDOG"' "$ROOT/router-install.sh" ||
	fail 'idempotent Nikki watchdog patch'
patch_call_line="$(grep -n '^patch_nikki_watchdog$' "$ROOT/router-install.sh" | tail -n 1 | cut -d: -f1)"
package_check_line="$(grep -n 'Taproom Nikki не установился' "$ROOT/router-install.sh" | head -n 1 | cut -d: -f1)"
[ "$patch_call_line" -gt "$package_check_line" ] ||
	fail 'watchdog patch must run after package installation'
pass 'idempotent Nikki watchdog patch'

grep -q '\[ ! -f "$WATCHDOG" \]' "$ROOT/router-install.sh" &&
	grep -q 'патч watchdog не требуется' "$ROOT/router-install.sh" &&
	! grep -q 'после установки не найден.*WATCHDOG' "$ROOT/router-install.sh" ||
	fail 'missing upstream watchdog is optional'
pass 'missing upstream watchdog is optional'

grep -q 'uplink_available' "$ROOT/router-safety.sh" &&
	grep -q 'ip -4 route show default' "$ROOT/router-safety.sh" &&
	grep -q 'ip -6 route show default' "$ROOT/router-safety.sh" &&
	grep -q 'dns_targets' "$ROOT/router-safety.sh" &&
	grep -q 'https_targets' "$ROOT/router-safety.sh" &&
	! grep -q 'ping .*1\.1\.1\.1' "$ROOT/router-safety.sh" ||
	fail 'model-independent multi-target health checks'
pass 'model-independent multi-target health checks'

grep -q '\[ -x /sbin/procd \]' "$ROOT/router-install.sh" &&
	grep -q 'for required_command in ash uci ubus sed grep awk cp df wget' "$ROOT/router-install.sh" &&
	grep -q 'MemAvailable:' "$ROOT/router-install.sh" &&
	grep -q 'opkg или apk' "$ROOT/router-install.sh" ||
	fail 'feature detection before changes'
pass 'feature detection before changes'

grep -q "NIKKIGO_INSTALL_LOG='/var/log/nikkigo-install.log'" "$ROOT/router-install.sh" &&
	grep -q 'redact_stream >> "$NIKKIGO_INSTALL_LOG"' "$ROOT/router-install.sh" &&
	grep -q 'NIKKIGO_INSTALL_LOG}.previous' "$ROOT/router-install.sh" &&
	grep -q 'Журнал последней установки для поддержки' "$ROOT/router-install.sh" ||
	fail 'compact support log for last installation'
! grep -q 'mountd\|/mnt/sda1\|/dev/sda1\|GL-MT6000\|GL\.iNet' "$ROOT/router-install.sh" ||
	fail 'installer must not depend on a router model or storage path'
pass 'compact support log for last installation'

grep -q '0 — только обновить Taproom Nikki' "$ROOT/router-install.sh" &&
	grep -q "0) action='update_only'" "$ROOT/router-install.sh" &&
	grep -q "\[ \"\$action\" = 'update_only' \]" "$ROOT/router-install.sh" &&
	grep -q 'restore_after_package_update' "$ROOT/router-install.sh" &&
	grep -q 'Подписки и настройки не изменены' "$ROOT/router-install.sh" ||
	fail 'package-only update action'
package_only_line="$(grep -n "\[ \"\$action\" = 'update_only' \]" "$ROOT/router-install.sh" | tail -n 1 | cut -d: -f1)"
subscription_prompt_line="$(grep -n "CURRENT_STAGE='ввод ссылки подписки'" "$ROOT/router-install.sh" | head -n 1 | cut -d: -f1)"
[ "$package_only_line" -lt "$subscription_prompt_line" ] ||
	fail 'package-only update must exit before subscription prompt'
pass 'package-only update action'
