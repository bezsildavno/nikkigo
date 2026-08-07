#!/bin/ash

NIKKIGO_STATE_DIR="${NIKKIGO_STATE_DIR:-/tmp/nikkigo-state-$$}"
NIKKIGO_CONFIG="${NIKKIGO_CONFIG:-/etc/config/nikki}"
NIKKIGO_SUBSCRIPTIONS="${NIKKIGO_SUBSCRIPTIONS:-/etc/nikki/subscriptions}"
NIKKIGO_RUN="${NIKKIGO_RUN:-/etc/nikki/run}"
NIKKIGO_SERVICE="${NIKKIGO_SERVICE:-/etc/init.d/nikki}"
NIKKIGO_MANAGER_CONFIG="${NIKKIGO_MANAGER_CONFIG:-/etc/config/nikkigo}"
NIKKIGO_TRANSACTION=0
NIKKIGO_ROLLBACK_ACTIVE=0

safe_log() {
	printf '[NikkiGo] %s\n' "$*" |
		redact_stream
}

redact_stream() {
	sed \
		-e 's#http://[^[:space:]]*#<URL скрыт>#g' \
		-e 's#https://[^[:space:]]*#<URL скрыт>#g' \
		-e 's#[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][=:][^[:space:]]*#password=<скрыто>#g' \
		-e 's#[Ss][Ee][Cc][Rr][Ee][Tt][=:][^[:space:]]*#secret=<скрыто>#g' \
		-e 's#[Tt][Oo][Kk][Ee][Nn][=:][^[:space:]]*#token=<скрыто>#g' \
		-e 's#[Kk][Ee][Yy][=:][^[:space:]]*#key=<скрыто>#g' \
		-e 's#[Uu][Uu][Ii][Dd][=:][^[:space:]]*#uuid=<скрыто>#g'
}

backup_state() {
	if ! mkdir -p "$NIKKIGO_STATE_DIR/subscriptions"; then
		safe_log "Не удалось создать временный каталог резервной копии."
		return 1
	fi
	if [ -f "$NIKKIGO_CONFIG" ]; then
		if ! cp -p "$NIKKIGO_CONFIG" "$NIKKIGO_STATE_DIR/nikki.uci"; then
			safe_log "Не удалось сохранить конфигурацию Nikki."
			return 1
		fi
	fi
	if [ -f "$NIKKIGO_MANAGER_CONFIG" ]; then
		if ! cp -p "$NIKKIGO_MANAGER_CONFIG" "$NIKKIGO_STATE_DIR/nikkigo.uci"; then
			safe_log "Не удалось сохранить конфигурацию NikkiGo."
			return 1
		fi
	else
		: > "$NIKKIGO_STATE_DIR/nikkigo.absent"
	fi
	if [ -d "$NIKKIGO_SUBSCRIPTIONS" ]; then
		for subscription_backup in "$NIKKIGO_SUBSCRIPTIONS"/*.yaml; do
			[ -f "$subscription_backup" ] || continue
			if ! cp -p "$subscription_backup" "$NIKKIGO_STATE_DIR/subscriptions/"; then
				safe_log "Не удалось сохранить существующие подписки."
				return 1
			fi
		done
	fi
	if ! uci -q get nikki.config.enabled > "$NIKKIGO_STATE_DIR/enabled" 2>/dev/null; then
		printf '0\n' > "$NIKKIGO_STATE_DIR/enabled"
	fi
	if [ -x "$NIKKIGO_SERVICE" ] &&
		"$NIKKIGO_SERVICE" running >/dev/null 2>&1; then
		printf '1\n' > "$NIKKIGO_STATE_DIR/running"
		if health_check; then
			printf '1\n' > "$NIKKIGO_STATE_DIR/healthy"
		else
			printf '0\n' > "$NIKKIGO_STATE_DIR/healthy"
		fi
	else
		printf '0\n' > "$NIKKIGO_STATE_DIR/running"
		printf '0\n' > "$NIKKIGO_STATE_DIR/healthy"
	fi
	NIKKIGO_TRANSACTION=1
	return 0
}

enable_fail_open() {
	if [ -x "$NIKKIGO_SERVICE" ]; then
		"$NIKKIGO_SERVICE" stop >/dev/null 2>&1 || :
	fi
	if [ -f "$NIKKIGO_CONFIG" ] &&
		uci -q get nikki.config >/dev/null 2>&1; then
		uci -q set nikki.config.enabled='0'
		uci -q commit nikki
	fi
	safe_log "Nikki отключён, обычный интернет восстановлен."
}

restore_state() {
	NIKKIGO_ROLLBACK_ACTIVE=1
	rollback_ok=1
	enable_fail_open || :
	if [ -f "$NIKKIGO_STATE_DIR/nikki.uci" ]; then
		if cp -p "$NIKKIGO_STATE_DIR/nikki.uci" "$NIKKIGO_CONFIG"; then
			uci -q revert nikki 2>/dev/null || :
		else
			safe_log 'Rollback: не удалось восстановить конфигурацию Nikki.'
			rollback_ok=0
		fi
	fi
	if [ -d "$NIKKIGO_STATE_DIR/subscriptions" ]; then
		mkdir -p "$NIKKIGO_SUBSCRIPTIONS" 2>/dev/null || rollback_ok=0
		if ! rm -f "$NIKKIGO_SUBSCRIPTIONS"/*.yaml 2>/dev/null; then
			safe_log 'Rollback: не удалось удалить файлы неудачного профиля.'
			rollback_ok=0
		fi
		for subscription_backup in "$NIKKIGO_STATE_DIR/subscriptions"/*.yaml; do
			[ -f "$subscription_backup" ] || continue
			if ! cp -p "$subscription_backup" "$NIKKIGO_SUBSCRIPTIONS/" 2>/dev/null; then
				safe_log 'Rollback: не удалось восстановить прежний файл подписки.'
				rollback_ok=0
				break
			fi
		done
	fi
	if [ -f "$NIKKIGO_STATE_DIR/nikkigo.uci" ]; then
		if cp -p "$NIKKIGO_STATE_DIR/nikkigo.uci" "$NIKKIGO_MANAGER_CONFIG" 2>/dev/null; then
			uci -q revert nikkigo 2>/dev/null || :
		else
			safe_log 'Rollback: не удалось восстановить конфигурацию NikkiGo.'
			rollback_ok=0
		fi
	elif [ -f "$NIKKIGO_STATE_DIR/nikkigo.absent" ]; then
		rm -f "$NIKKIGO_MANAGER_CONFIG" 2>/dev/null || rollback_ok=0
		uci -q unload nikkigo 2>/dev/null || :
	fi

	saved_enabled="$(cat "$NIKKIGO_STATE_DIR/enabled" 2>/dev/null || printf 0)"
	saved_running="$(cat "$NIKKIGO_STATE_DIR/running" 2>/dev/null || printf 0)"
	saved_healthy="$(cat "$NIKKIGO_STATE_DIR/healthy" 2>/dev/null || printf 0)"
	if [ "$saved_enabled" = '1' ]; then
		if [ "$rollback_ok" = '1' ] &&
			[ "$saved_running" = '1' ] && [ "$saved_healthy" = '1' ]; then
			saved_proxy_enabled="$(uci -q get nikki.proxy.enabled 2>/dev/null || printf 0)"
			case "$saved_proxy_enabled" in 1) ;; *) saved_proxy_enabled=0 ;; esac
			if uci -q set nikki.config.enabled='1' &&
				uci -q set nikki.proxy.enabled='0' &&
				uci -q set nikki.mixin.selection_cache='1' && uci -q commit nikki &&
				"$NIKKIGO_SERVICE" restart >/dev/null 2>&1 && wait_for_api; then
				safe_log 'Rollback: старый профиль запущен без перехвата; восстанавливаются пользовательские selector-группы.'
				if ! restore_previous_selections rollback; then
					safe_log 'Rollback: локальный Mihomo API недоступен для восстановления selector-групп.'
					rollback_ok=0
				fi
			else
				safe_log 'Rollback: старый профиль или локальный Mihomo API не запустился.'
				rollback_ok=0
			fi
			if [ "$rollback_ok" = '1' ]; then
				if uci -q set "nikki.proxy.enabled=$saved_proxy_enabled" &&
					uci -q commit nikki &&
					"$NIKKIGO_SERVICE" restart >/dev/null 2>&1 && wait_for_api; then
					safe_log 'Rollback: прежняя конфигурация, selector-группы и состояние перехвата восстановлены.'
				else
					safe_log 'Rollback: не удалось вернуть исходное состояние перехвата.'
					rollback_ok=0
				fi
			fi
		else
			safe_log 'Прежнее состояние не прошло health-check и оставлено отключённым.'
			rollback_ok=0
		fi
	fi
	if [ "$rollback_ok" != '1' ]; then
		enable_fail_open || :
	fi
	NIKKIGO_TRANSACTION=0
	NIKKIGO_ROLLBACK_ACTIVE=0
	rm -rf "$NIKKIGO_STATE_DIR"
	[ "$rollback_ok" = '1' ]
}

restore_after_package_update() {
	if [ -x "$NIKKIGO_SERVICE" ]; then
		"$NIKKIGO_SERVICE" stop >/dev/null 2>&1 || :
	fi
	if [ -f "$NIKKIGO_STATE_DIR/nikki.uci" ]; then
		cp -p "$NIKKIGO_STATE_DIR/nikki.uci" "$NIKKIGO_CONFIG" || return 1
		uci -q revert nikki 2>/dev/null || :
	fi
	if [ -d "$NIKKIGO_STATE_DIR/subscriptions" ]; then
		mkdir -p "$NIKKIGO_SUBSCRIPTIONS" || return 1
		cp -p "$NIKKIGO_STATE_DIR/subscriptions"/*.yaml "$NIKKIGO_SUBSCRIPTIONS/" 2>/dev/null || :
	fi
	saved_enabled="$(cat "$NIKKIGO_STATE_DIR/enabled" 2>/dev/null || printf 0)"
	saved_running="$(cat "$NIKKIGO_STATE_DIR/running" 2>/dev/null || printf 0)"
	if [ "$saved_enabled" = '1' ]; then
		uci -q set nikki.config.enabled='1' || return 1
		uci -q commit nikki || return 1
		if [ "$saved_running" = '1' ]; then
			"$NIKKIGO_SERVICE" restart >/dev/null 2>&1 || {
				enable_fail_open
				return 1
			}
		fi
	else
		uci -q set nikki.config.enabled='0' 2>/dev/null || :
		uci -q commit nikki 2>/dev/null || :
	fi
	NIKKIGO_TRANSACTION=0
	rm -rf "$NIKKIGO_STATE_DIR"
	return 0
}

validate_profile() {
	profile="$1"
	[ -s "$profile" ] || return 1
	yq -M -p yaml -o yaml -e \
		'(has("proxies") or has("proxy-providers")) and has("proxy-groups")' \
		"$profile" >/dev/null 2>&1 || return 1
	/usr/bin/mihomo -d "$NIKKIGO_RUN" -t >/dev/null 2>&1
}

controller_url() {
	listen="$(yq -r '."external-controller" // ""' "$NIKKIGO_RUN/config.yaml" 2>/dev/null)"
	port="${listen##*:}"
	case "$port" in ''|*[!0-9]*) port=9090 ;; esac
	printf 'http://127.0.0.1:%s' "$port"
}

url_encode() (
	# Work byte-by-byte in the C locale. This avoids optional OpenWrt tools
	# such as od, hexdump, xxd, Python, or Perl.
	LC_ALL=C
	export LC_ALL
	value="$1"
	encoded=
	while [ -n "$value" ]; do
		rest="${value#?}"
		byte="${value%"$rest"}"
		decimal="$(printf '%d' "'$byte")"
		hex="$(printf '%02X' "$decimal")"
		encoded="${encoded}%${hex}"
		value="$rest"
	done
	printf '%s' "$encoded"
)

api_get() {
	url="$1"
	secret="$(yq -r '.secret // ""' "$NIKKIGO_RUN/config.yaml" 2>/dev/null)"
	if [ -n "$secret" ]; then
		curl -fsS --max-time 5 -H "Authorization: Bearer $secret" "$url"
	else
		curl -fsS --max-time 5 "$url"
	fi
}

api_select() {
	api="$1"
	group="$2"
	choice="$3"
	secret="$(yq -r '.secret // ""' "$NIKKIGO_RUN/config.yaml" 2>/dev/null)"
	encoded="$(url_encode "$group")"
	payload="$(printf '%s' "$choice" | sed 's/\\/\\\\/g; s/"/\\"/g')"
	if [ -n "$secret" ]; then
		curl -fsS --max-time 5 -H "Authorization: Bearer $secret" \
			-H 'Content-Type: application/json' -X PUT \
			-d "{\"name\":\"$payload\"}" "$api/proxies/$encoded" >/dev/null
	else
		curl -fsS --max-time 5 -H 'Content-Type: application/json' -X PUT \
			-d "{\"name\":\"$payload\"}" "$api/proxies/$encoded" >/dev/null
	fi
}

wait_for_api() {
	api="$(controller_url)"
	attempt=1
	while [ "$attempt" -le 10 ]; do
		api_get "$api/version" >/dev/null 2>&1 && return 0
		sleep 1
		attempt=$((attempt + 1))
	done
	return 1
}

capture_previous_selections() {
	snapshot="$NIKKIGO_STATE_DIR/previous-selections.tsv"
	proxies_snapshot="$NIKKIGO_STATE_DIR/previous-proxies.json"
	: > "$snapshot" || return 1
	api="$(controller_url)"
	if ! api_get "$api/proxies" > "$proxies_snapshot"; then
		safe_log 'Предупреждение: текущие selector-группы получить не удалось; обновление продолжится с безопасным автовыбором.'
		rm -f "$proxies_snapshot"
		return 0
	fi
	if ! yq -r '.proxies | to_entries[] |
		select(.value.type == "Selector") |
		select((.value.now // "") != "") |
		[.key, .value.now] | @tsv' "$proxies_snapshot" > "$snapshot" 2>/dev/null; then
		safe_log 'Предупреждение: снимок selector-групп разобрать не удалось; обновление продолжится с безопасным автовыбором.'
		: > "$snapshot"
	fi
	rm -f "$proxies_snapshot"
	saved_count="$(awk 'NF >= 2 { count++ } END { print count + 0 }' "$snapshot")"
	safe_log "Сохранено групп: $saved_count."
	return 0
}

selection_exists_in_snapshot() {
	proxies_file="$1"
	group_name="$2"
	choice_name="$3"
	GROUP_NAME="$group_name" CHOICE_NAME="$choice_name" yq -e '
		.proxies[strenv(GROUP_NAME)] as $group |
		$group.type == "Selector" and
		(($group.all // []) | any_c(. == strenv(CHOICE_NAME)))
	' "$proxies_file" >/dev/null 2>&1
}

restore_previous_selections() {
	restore_mode="${1:-update}"
	snapshot="$NIKKIGO_STATE_DIR/previous-selections.tsv"
	[ -s "$snapshot" ] || {
		safe_log 'Сохранено групп: 0; восстановлено: 0; отсутствуют в новой подписке: 0.'
		return 0
	}
	current_proxies="$NIKKIGO_STATE_DIR/current-proxies.json"
	api="$(controller_url)"
	if ! api_get "$api/proxies" > "$current_proxies"; then
		safe_log 'Предупреждение: Mihomo API недоступен для восстановления selector-групп; безопасный автовыбор сохранён.'
		if [ "$restore_mode" = 'rollback' ]; then
			return 1
		fi
		return 0
	fi
	saved=0
	restored=0
	missing=0
	rejected=0
	while IFS="$(printf '\t')" read -r group choice; do
		[ -n "$group" ] && [ -n "$choice" ] || continue
		saved=$((saved + 1))
		if ! selection_exists_in_snapshot "$current_proxies" "$group" "$choice"; then
			missing=$((missing + 1))
			continue
		fi
		if api_select "$api" "$group" "$choice"; then
			restored=$((restored + 1))
		else
			rejected=$((rejected + 1))
		fi
	done < "$snapshot"
	rm -f "$current_proxies"
	[ "$rejected" -eq 0 ] ||
		safe_log "Предупреждение: Mihomo API отклонил восстановление групп: $rejected; обновление продолжено."
	safe_log "Сохранено групп: $saved; восстановлено: $restored; отсутствуют в новой подписке: $missing."
	return 0
}

select_safe_proxies() {
	api="$(controller_url)"
	api_get "$api/proxies" > "$NIKKIGO_STATE_DIR/proxies.json" || return 1
	selector_count="$(yq -r '[.proxies[] | select(.type == "Selector")] | length' "$NIKKIGO_STATE_DIR/proxies.json")"
	yq -r '.proxies as $all | .proxies | to_entries[] |
		select(.value.type == "Selector") |
		[.key, ((.value.all // []) |
			map(select(($all[.].type == "URLTest") or ($all[.].type == "Fallback")))[0] //
			map(select(. == "DIRECT"))[0] // "")] | @tsv' \
		"$NIKKIGO_STATE_DIR/proxies.json" > "$NIKKIGO_STATE_DIR/selections.tsv" 2>/dev/null || return 1
	choice_count="$(awk -F '\t' '$2 != "" { count++ } END { print count + 0 }' "$NIKKIGO_STATE_DIR/selections.tsv")"
	if [ "$choice_count" -lt "$selector_count" ]; then
		safe_log "Не для всех selector-групп найден предварительный автоматический вариант."
		safe_log "Оставшиеся группы будут проверены функционально после запуска."
	fi
	while IFS="$(printf '\t')" read -r group choice; do
		[ -n "$group" ] && [ -n "$choice" ] || continue
		api_select "$api" "$group" "$choice" || return 1
	done < "$NIKKIGO_STATE_DIR/selections.tsv"
}

quick_health_check() {
	api="$(controller_url)"
	"$NIKKIGO_SERVICE" running >/dev/null 2>&1 || return 1
	api_get "$api/version" >/dev/null 2>&1 || return 1
	uplink_available || return 1
	dns_available || return 1
	https_available
}

uplink_available() {
	if command -v ip >/dev/null 2>&1; then
		{
			ip -4 route show default 2>/dev/null || :
			ip -6 route show default 2>/dev/null || :
		} | grep -q '^default'
		return
	fi
	[ -r /proc/net/route ] &&
		awk '$2 == "00000000" && $4 != "0000" { found=1 } END { exit !found }' /proc/net/route
}

dns_available() {
	targets="$(uci -q get nikkigo.health.dns_targets 2>/dev/null || :)"
	targets="${targets:-example.com cloudflare.com}"
	for target in $targets; do
		nslookup "$target" >/dev/null 2>&1 && return 0
	done
	return 1
}

https_available() {
	targets="$(uci -q get nikkigo.health.https_targets 2>/dev/null || :)"
	targets="${targets:-https://www.gstatic.com/generate_204 https://cp.cloudflare.com/generate_204}"
	for target in $targets; do
		curl -fsS --max-time 8 -o /dev/null "$target" >/dev/null 2>&1 && return 0
	done
	return 1
}

try_recover_proxies() {
	api="$(controller_url)"
	api_get "$api/proxies" > "$NIKKIGO_STATE_DIR/recovery-proxies.json" || return 1
	yq -r '.proxies as $all | .proxies | to_entries[] |
		select(.value.type == "Selector") |
		.key as $group | (.value.all // [])[] |
		select(. != "DIRECT" and . != "REJECT") |
		[$group, ., ($all[$group].now // "")] | @tsv' \
		"$NIKKIGO_STATE_DIR/recovery-proxies.json" \
		> "$NIKKIGO_STATE_DIR/recovery-candidates-raw.tsv" 2>/dev/null || return 1

	# Round-robin start: try one option from every selector before spending the
	# bounded budget on additional options from the same group.
	awk -F '\t' '!seen[$1]++ { print }' \
		"$NIKKIGO_STATE_DIR/recovery-candidates-raw.tsv" \
		> "$NIKKIGO_STATE_DIR/recovery-first-round.tsv"
	awk -F '\t' 'seen[$1]++ { print }' \
		"$NIKKIGO_STATE_DIR/recovery-candidates-raw.tsv" \
		> "$NIKKIGO_STATE_DIR/recovery-next-rounds.tsv"
	cat "$NIKKIGO_STATE_DIR/recovery-first-round.tsv" \
		"$NIKKIGO_STATE_DIR/recovery-next-rounds.tsv" \
		> "$NIKKIGO_STATE_DIR/recovery-candidates.tsv"

	tested=0
	delay_passed=0
	applied=0
	while IFS="$(printf '\t')" read -r group candidate original; do
		[ -n "$group" ] && [ -n "$candidate" ] || continue
		[ "$tested" -lt 8 ] || break
		[ "$candidate" = "$original" ] && continue
		tested=$((tested + 1))
		encoded="$(url_encode "$candidate")"
		if api_get "$api/proxies/$encoded/delay?timeout=4000&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204" \
			>/dev/null 2>&1; then
			delay_passed=$((delay_passed + 1))
			api_select "$api" "$group" "$candidate" || continue
			applied=$((applied + 1))
			sleep 1
			if quick_health_check; then
				safe_log "Автоподбор успешен: проверено $tested, delay-test прошли $delay_passed, применено $applied."
				return 0
			fi
			[ -z "$original" ] || api_select "$api" "$group" "$original" >/dev/null 2>&1 || :
		fi
	done < "$NIKKIGO_STATE_DIR/recovery-candidates.tsv"
	safe_log "Автоподбор не помог: проверено $tested, delay-test прошли $delay_passed, применено $applied."
	return 1
}

prepare_zashboard() {
	url="$(uci -q get nikki.mixin.ui_url || :)"
	if [ -f "$NIKKIGO_RUN/config.yaml" ]; then
		run_url="$(yq -r '."external-ui-url" // ""' "$NIKKIGO_RUN/config.yaml" 2>/dev/null)"
		[ -z "$run_url" ] || url="$run_url"
	fi
	[ -n "$url" ] || return 1
	work="$NIKKIGO_STATE_DIR/ui"
	rm -rf "$work"
	mkdir -p "$work/unpack"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --max-time 120 -o "$work/ui.zip" "$url" || return 1
	else
		wget -q -O "$work/ui.zip" "$url" || return 1
	fi
	command -v unzip >/dev/null 2>&1 || return 1
	unzip -t "$work/ui.zip" >/dev/null 2>&1 || return 1
	unzip -q "$work/ui.zip" -d "$work/unpack" || return 1
	index="$(find "$work/unpack" -type f -name index.html | head -n 1)"
	[ -n "$index" ] || return 1
	printf '%s\n' "${index%/*}" > "$work/source-dir"
}

ensure_zashboard() {
	work="$NIKKIGO_STATE_DIR/ui"
	[ -f "$work/source-dir" ] || prepare_zashboard || return 1
	source_dir="$(cat "$work/source-dir")"
	rm -rf "$NIKKIGO_RUN/ui"
	mkdir -p "$NIKKIGO_RUN/ui"
	cp -R "$source_dir"/. "$NIKKIGO_RUN/ui/"
	[ -f "$NIKKIGO_RUN/ui/index.html" ] || return 1
	configure_zashboard_defaults "$NIKKIGO_RUN/ui/index.html"
}

configure_zashboard_defaults() {
	index_file="$1"
	marker='id="nikkigo-defaults"'
	grep -Fq "$marker" "$index_file" && return 0
	bootstrap='<script id="nikkigo-defaults">(()=>{const d={"config/check-upgrade-core":"true","config/auto-upgrade-core":"true","config/auto-upgrade":"true","config/auto-disconnect-idle-udp":"true"};for(const k in d)if(localStorage.getItem(k)===null)localStorage.setItem(k,d[k])})()</script>'
	if grep -Fq '</head>' "$index_file"; then
		sed -i "s#</head>#$bootstrap</head>#" "$index_file" || return 1
	else
		sed -i "1a\\$bootstrap" "$index_file" || return 1
	fi
	grep -Fq "$marker" "$index_file"
}

health_check() {
	attempt=1
	while [ "$attempt" -le 3 ]; do
		quick_health_check && return 0
		uplink_available || return 1
		sleep 3
		attempt=$((attempt + 1))
	done
	return 1
}

commit_state() {
	NIKKIGO_TRANSACTION=0
	rm -rf "$NIKKIGO_STATE_DIR"
}
