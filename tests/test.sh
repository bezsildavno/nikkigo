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
	grep -q 'id="nikkigo-defaults"' "$run/ui/index.html" ||
		fail "$layout Zashboard defaults"
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

capture_line="$(grep -n '^capture_previous_selections' "$ROOT/router-update.sh" | head -n 1 | cut -d: -f1)"
update_line="$(grep -n 'update_subscription "$SECTION"' "$ROOT/router-update.sh" | head -n 1 | cut -d: -f1)"
safe_select_line="$(grep -n '^select_safe_proxies' "$ROOT/router-update.sh" | head -n 1 | cut -d: -f1)"
restore_select_line="$(grep -n '^restore_previous_selections' "$ROOT/router-update.sh" | head -n 1 | cut -d: -f1)"
health_line="$(grep -n '^if ! health_check' "$ROOT/router-update.sh" | head -n 1 | cut -d: -f1)"
[ "$capture_line" -lt "$update_line" ] &&
	[ "$safe_select_line" -lt "$restore_select_line" ] &&
	[ "$restore_select_line" -lt "$health_line" ] ||
	fail 'selector preservation update order'
grep -q 'nikkigo.main.subscription_section' "$ROOT/router-update.sh" &&
	! grep -q "^SECTION='ssh_transibservice'" "$ROOT/router-update.sh" ||
	fail 'dynamic subscription section'
pass 'selector preservation update order'

selector_state="$TMP/selector-state"
mkdir -p "$selector_state"
printf 'group-a\tnode-a\ngroup-b\tnode-b\n' > "$selector_state/previous-selections.tsv"
(
	NIKKIGO_STATE_DIR="$selector_state"
	. "$ROOT/router-safety.sh"
	controller_url() { printf 'http://127.0.0.1:9090'; }
	api_get() { printf '{"proxies":{}}'; }
	selection_exists_in_snapshot() { return 0; }
	api_select() { printf '%s=%s\n' "$2" "$3" >> "$selector_state/applied-all"; }
	restore_previous_selections > "$selector_state/log-all"
)
[ "$(wc -l < "$selector_state/applied-all")" -eq 2 ] ||
	fail 'all previous selector choices restored'
grep -q 'восстановлено: 2' "$selector_state/log-all" ||
	fail 'selector restore summary'
pass 'all previous selector choices restored'

rm -f "$selector_state/applied-missing"
(
	NIKKIGO_STATE_DIR="$selector_state"
	. "$ROOT/router-safety.sh"
	controller_url() { printf 'http://127.0.0.1:9090'; }
	api_get() { printf '{"proxies":{}}'; }
	selection_exists_in_snapshot() { [ "$2" = 'group-a' ]; }
	api_select() { printf '%s=%s\n' "$2" "$3" >> "$selector_state/applied-missing"; }
	restore_previous_selections rollback > "$selector_state/log-missing"
)
[ "$(wc -l < "$selector_state/applied-missing")" -eq 1 ] &&
	grep -q 'отсутствуют в новой подписке: 1' "$selector_state/log-missing" ||
	fail 'missing choice is skipped without aborting'
grep -q 'node-a\|node-b' "$selector_state/log-missing" &&
	fail 'selector node names leaked into log'
pass 'missing and renamed selector choices are non-fatal'

rm -f "$selector_state/applied-rejected"
(
	NIKKIGO_STATE_DIR="$selector_state"
	. "$ROOT/router-safety.sh"
	controller_url() { printf 'http://127.0.0.1:9090'; }
	api_get() { printf '{"proxies":{}}'; }
	selection_exists_in_snapshot() { return 0; }
	api_select() {
		[ "$2" = 'group-a' ] || return 1
		printf '%s=%s\n' "$2" "$3" >> "$selector_state/applied-rejected"
	}
	restore_previous_selections rollback > "$selector_state/log-rejected"
)
[ "$(wc -l < "$selector_state/applied-rejected")" -eq 1 ] &&
	grep -q 'API отклонил восстановление групп: 1' "$selector_state/log-rejected" &&
	grep -q 'отсутствуют в новой подписке: 0' "$selector_state/log-rejected" ||
	fail 'API rejection is reported separately and remains non-fatal'
grep -q 'node-a\|node-b' "$selector_state/log-rejected" &&
	fail 'rejected selector node names leaked into log'
pass 'Mihomo API rejection is non-fatal and anonymized'

capture_state="$TMP/capture-unavailable"
mkdir -p "$capture_state"
(
	NIKKIGO_STATE_DIR="$capture_state"
	. "$ROOT/router-safety.sh"
	controller_url() { printf 'http://127.0.0.1:9090'; }
	api_get() { return 1; }
	capture_previous_selections > "$capture_state/log"
)
[ ! -s "$capture_state/previous-selections.tsv" ] &&
	grep -q 'обновление продолжится' "$capture_state/log" ||
	fail 'unavailable API before update is non-fatal'
pass 'unavailable API before update is non-fatal'

rollback_root="$TMP/rollback-selectors"
rollback_state="$rollback_root/state"
rollback_subscriptions="$rollback_root/subscriptions"
rollback_run="$rollback_root/run"
rollback_service="$rollback_root/nikki-service"
rollback_ops="$rollback_root/operations"
rollback_applied="$rollback_root/applied"
mkdir -p "$rollback_state/subscriptions" "$rollback_subscriptions" "$rollback_run"
printf 'old-config\n' > "$rollback_state/nikki.uci"
printf 'old-manager\n' > "$rollback_state/nikkigo.uci"
printf 'old-profile\n' > "$rollback_state/subscriptions/current.yaml"
printf 'new-config\n' > "$rollback_root/nikki.conf"
printf 'new-manager\n' > "$rollback_root/nikkigo.conf"
printf 'new-profile\n' > "$rollback_subscriptions/current.yaml"
printf 'unexpected-profile\n' > "$rollback_subscriptions/extra.yaml"
printf '1\n' > "$rollback_state/enabled"
printf '1\n' > "$rollback_state/running"
printf '1\n' > "$rollback_state/healthy"
printf 'group-a\tnode-a\ngroup-b\tnode-b\n' > "$rollback_state/previous-selections.tsv"
printf 'cache-must-survive\n' > "$rollback_root/cache.db"
cat > "$rollback_service" <<'EOF'
#!/bin/sh
printf 'service:%s\n' "$1" >> "$ROLLBACK_SERVICE_LOG"
exit 0
EOF
chmod +x "$rollback_service"
(
	NIKKIGO_STATE_DIR="$rollback_state"
	NIKKIGO_CONFIG="$rollback_root/nikki.conf"
	NIKKIGO_MANAGER_CONFIG="$rollback_root/nikkigo.conf"
	NIKKIGO_SUBSCRIPTIONS="$rollback_subscriptions"
	NIKKIGO_RUN="$rollback_run"
	NIKKIGO_SERVICE="$rollback_service"
	ROLLBACK_SERVICE_LOG="$rollback_ops"
	export ROLLBACK_SERVICE_LOG
	. "$ROOT/router-safety.sh"
	NIKKIGO_TRANSACTION=1
	uci() {
		printf 'uci:%s\n' "$*" >> "$rollback_ops"
		case "$*" in
			*'get nikki.proxy.enabled'*) printf '1\n' ;;
		esac
		return 0
	}
	wait_for_api() { printf 'api:ready\n' >> "$rollback_ops"; return 0; }
	controller_url() { printf 'http://127.0.0.1:9090'; }
	api_get() { printf '{"proxies":{}}'; }
	selection_exists_in_snapshot() { [ -f "$rollback_state/previous-selections.tsv" ]; }
	api_select() {
		[ -f "$rollback_state/previous-selections.tsv" ] || return 1
		printf '%s=%s\n' "$2" "$3" >> "$rollback_applied"
		printf 'api:select\n' >> "$rollback_ops"
	}
	restore_state > "$rollback_root/log"
)
[ "$(cat "$rollback_root/nikki.conf")" = 'old-config' ] &&
	[ "$(cat "$rollback_root/nikkigo.conf")" = 'old-manager' ] &&
	[ "$(cat "$rollback_subscriptions/current.yaml")" = 'old-profile' ] &&
	[ ! -f "$rollback_subscriptions/extra.yaml" ] ||
	fail 'rollback must restore old configuration and subscriptions'
[ "$(wc -l < "$rollback_applied")" -eq 2 ] ||
	fail 'rollback must restore all compatible previous selectors'
[ "$(cat "$rollback_root/cache.db")" = 'cache-must-survive' ] ||
	fail 'rollback must not modify cache.db'
[ ! -e "$rollback_state" ] ||
	fail 'transaction state must be removed after selector rollback completes'
proxy_off_line="$(grep -n "nikki.proxy.enabled=0" "$rollback_ops" | tail -n 1 | cut -d: -f1)"
selection_cache_line="$(grep -n "nikki.mixin.selection_cache=1" "$rollback_ops" | tail -n 1 | cut -d: -f1)"
first_selector_line="$(grep -n 'api:select' "$rollback_ops" | head -n 1 | cut -d: -f1)"
proxy_on_line="$(grep -n "nikki.proxy.enabled=1" "$rollback_ops" | tail -n 1 | cut -d: -f1)"
[ "$proxy_off_line" -lt "$first_selector_line" ] &&
	[ "$selection_cache_line" -lt "$first_selector_line" ] &&
	[ "$first_selector_line" -lt "$proxy_on_line" ] ||
	fail 'rollback selector restoration must run before interception is restored'
[ "$(grep -c 'api:ready' "$rollback_ops")" -eq 2 ] ||
	fail 'rollback must verify the API before and after interception restart'
grep -q 'group-a\|group-b\|node-a\|node-b' "$rollback_root/log" &&
	fail 'rollback log leaked selector or node names'
pass 'rollback restores old files and selectors before interception'

rollback_fail_root="$TMP/rollback-api-unavailable"
rollback_fail_state="$rollback_fail_root/state"
mkdir -p "$rollback_fail_state/subscriptions" "$rollback_fail_root/subscriptions" "$rollback_fail_root/run"
printf 'old-config\n' > "$rollback_fail_state/nikki.uci"
printf 'old-profile\n' > "$rollback_fail_state/subscriptions/current.yaml"
printf '1\n' > "$rollback_fail_state/enabled"
printf '1\n' > "$rollback_fail_state/running"
printf '1\n' > "$rollback_fail_state/healthy"
printf 'private-group\tprivate-node\n' > "$rollback_fail_state/previous-selections.tsv"
(
	NIKKIGO_STATE_DIR="$rollback_fail_state"
	NIKKIGO_CONFIG="$rollback_fail_root/nikki.conf"
	NIKKIGO_MANAGER_CONFIG="$rollback_fail_root/nikkigo.conf"
	NIKKIGO_SUBSCRIPTIONS="$rollback_fail_root/subscriptions"
	NIKKIGO_RUN="$rollback_fail_root/run"
	NIKKIGO_SERVICE="$rollback_service"
	ROLLBACK_SERVICE_LOG="$rollback_fail_root/service-log"
	export ROLLBACK_SERVICE_LOG
	. "$ROOT/router-safety.sh"
	NIKKIGO_TRANSACTION=1
	uci() {
		case "$*" in *'get nikki.proxy.enabled'*) printf '1\n' ;; esac
		return 0
	}
	enable_fail_open() { printf 'fail-open\n' >> "$rollback_fail_root/fail-open"; }
	wait_for_api() { return 1; }
	restore_previous_selections() {
		printf 'unexpected selector restore\n' > "$rollback_fail_root/unexpected"
		return 0
	}
	if restore_state > "$rollback_fail_root/log"; then
		exit 1
	fi
)
[ "$(wc -l < "$rollback_fail_root/fail-open")" -eq 2 ] &&
	[ ! -e "$rollback_fail_root/unexpected" ] &&
	[ ! -e "$rollback_fail_state" ] ||
	fail 'unavailable old-profile API must leave rollback in fail-open'
grep -q 'private-group\|private-node' "$rollback_fail_root/log" &&
	fail 'failed rollback log leaked selector or node names'
pass 'unavailable old-profile API leaves Nikki in fail-open'

restore_files_line="$(grep -n 'cp -p "$NIKKIGO_STATE_DIR/nikki.uci"' "$ROOT/router-safety.sh" | head -n 1 | cut -d: -f1)"
rollback_proxy_off_line="$(grep -n "uci -q set nikki.proxy.enabled='0'" "$ROOT/router-safety.sh" | head -n 1 | cut -d: -f1)"
rollback_restore_line="$(grep -n 'restore_previous_selections rollback' "$ROOT/router-safety.sh" | head -n 1 | cut -d: -f1)"
rollback_proxy_restore_line="$(grep -n 'nikki.proxy.enabled=\$saved_proxy_enabled' "$ROOT/router-safety.sh" | head -n 1 | cut -d: -f1)"
rollback_cleanup_line="$(grep -n 'rm -rf "$NIKKIGO_STATE_DIR"' "$ROOT/router-safety.sh" | head -n 1 | cut -d: -f1)"
[ "$restore_files_line" -lt "$rollback_proxy_off_line" ] &&
	[ "$rollback_proxy_off_line" -lt "$rollback_restore_line" ] &&
	[ "$rollback_restore_line" -lt "$rollback_proxy_restore_line" ] &&
	[ "$rollback_proxy_restore_line" -lt "$rollback_cleanup_line" ] ||
	fail 'rollback source order must preserve state through selector restoration'
grep -q 'NIKKIGO_ROLLBACK_ACTIVE' "$ROOT/router-update.sh" &&
	grep -q 'NIKKIGO_ROLLBACK_ACTIVE' "$ROOT/router-install.sh" ||
	fail 'EXIT traps must guard against recursive rollback'
[ "$(grep -c '^restore_previous_selections$' "$ROOT/router-update.sh")" -eq 1 ] ||
	fail 'successful updater must restore selectors exactly once'
! grep -Eq '(rm|cp|mv)[^#]*cache\.db|cache\.db[^#]*(rm|cp|mv)' \
	"$ROOT/router-safety.sh" "$ROOT/router-update.sh" "$ROOT/router-install.sh" ||
	fail 'transaction scripts must not delete or overwrite cache.db'
pass 'rollback ordering, single success restore, and cache preservation'

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

grep -q "nikki.mixin.selection_cache='1'" "$ROOT/router-install.sh" ||
	fail 'Mihomo selected-proxy persistence enabled'
grep -q "nikki.mixin.selection_cache='1'" "$ROOT/router-update.sh" ||
	fail 'scheduled updater must enforce Mihomo selected-proxy persistence'
pass 'Mihomo selected-proxy persistence enabled'

grep -q '^atomic_install_script()' "$ROOT/router-install.sh" &&
	grep -q 'ash -n "$temporary"' "$ROOT/router-install.sh" &&
	grep -q 'mv -f "$temporary" "$destination"' "$ROOT/router-install.sh" &&
	grep -q "sed -i '/# nikkigo-update\$/d'" "$ROOT/router-install.sh" ||
	fail 'atomic maintenance scripts and idempotent cron'
pass 'atomic maintenance scripts and idempotent cron'

grep -q 'config/auto-upgrade-core' "$ROOT/router-safety.sh" &&
	grep -q 'config/auto-upgrade' "$ROOT/router-safety.sh" &&
	grep -q 'config/auto-disconnect-idle-udp' "$ROOT/router-safety.sh" &&
	grep -q 'localStorage.getItem(k)===null' "$ROOT/router-safety.sh" &&
	grep -q 'id="nikkigo-defaults"' "$ROOT/router-safety.sh" ||
	fail 'non-destructive Zashboard defaults'
pass 'non-destructive Zashboard defaults'
