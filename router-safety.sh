#!/bin/ash

NIKKIGO_STATE_DIR="${NIKKIGO_STATE_DIR:-/tmp/nikkigo-state-$$}"
NIKKIGO_CONFIG="${NIKKIGO_CONFIG:-/etc/config/nikki}"
NIKKIGO_SUBSCRIPTIONS="${NIKKIGO_SUBSCRIPTIONS:-/etc/nikki/subscriptions}"
NIKKIGO_RUN="${NIKKIGO_RUN:-/etc/nikki/run}"
NIKKIGO_SERVICE="${NIKKIGO_SERVICE:-/etc/init.d/nikki}"
NIKKIGO_TRANSACTION=0

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
	enable_fail_open
	if [ -f "$NIKKIGO_STATE_DIR/nikki.uci" ]; then
		cp -p "$NIKKIGO_STATE_DIR/nikki.uci" "$NIKKIGO_CONFIG"
		uci -q revert nikki 2>/dev/null || :
	fi
	if [ -d "$NIKKIGO_STATE_DIR/subscriptions" ]; then
		cp -p "$NIKKIGO_STATE_DIR/subscriptions"/*.yaml "$NIKKIGO_SUBSCRIPTIONS/" 2>/dev/null || :
	fi
	if [ "$(cat "$NIKKIGO_STATE_DIR/enabled" 2>/dev/null || printf 0)" = '1' ]; then
		uci -q set nikki.config.enabled='1'
		uci -q commit nikki
		if [ "$(cat "$NIKKIGO_STATE_DIR/running" 2>/dev/null || printf 0)" = '1' ] &&
			[ "$(cat "$NIKKIGO_STATE_DIR/healthy" 2>/dev/null || printf 0)" = '1' ]; then
			"$NIKKIGO_SERVICE" restart >/dev/null 2>&1 || enable_fail_open
		else
			uci -q set nikki.config.enabled='0'
			uci -q commit nikki
			safe_log "Прежнее состояние не прошло health-check и оставлено отключённым."
		fi
	fi
	NIKKIGO_TRANSACTION=0
	rm -rf "$NIKKIGO_STATE_DIR"
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

url_encode() {
	printf '%s' "$1" | od -An -tx1 | tr -d '\n ' | sed 's/../%&/g'
}

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
	nslookup example.com >/dev/null 2>&1 || return 1
	curl -fsS --max-time 8 -o /dev/null https://www.gstatic.com/generate_204
}

try_recover_proxies() {
	api="$(controller_url)"
	api_get "$api/proxies" > "$NIKKIGO_STATE_DIR/recovery-proxies.json" || return 1
	yq -r '.proxies | to_entries[] |
		select(.value.type == "Selector") |
		.key as $group | (.value.all // [])[] |
		select(. != "DIRECT" and . != "REJECT") |
		[$group, .] | @tsv' \
		"$NIKKIGO_STATE_DIR/recovery-proxies.json" \
		> "$NIKKIGO_STATE_DIR/recovery-candidates.tsv" 2>/dev/null || return 1

	tested=0
	while IFS="$(printf '\t')" read -r group candidate; do
		[ -n "$group" ] && [ -n "$candidate" ] || continue
		[ "$tested" -lt 8 ] || break
		tested=$((tested + 1))
		encoded="$(url_encode "$candidate")"
		if api_get "$api/proxies/$encoded/delay?timeout=4000&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204" \
			>/dev/null 2>&1; then
			api_select "$api" "$group" "$candidate" || continue
			sleep 1
			if quick_health_check; then
				safe_log "Найден работоспособный вариант прокси после автоматической проверки."
				return 0
			fi
		fi
	done < "$NIKKIGO_STATE_DIR/recovery-candidates.tsv"
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
	[ -f "$NIKKIGO_RUN/ui/index.html" ]
}

health_check() {
	attempt=1
	while [ "$attempt" -le 3 ]; do
		quick_health_check && return 0
		ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || :
		sleep 3
		attempt=$((attempt + 1))
	done
	return 1
}

commit_state() {
	NIKKIGO_TRANSACTION=0
	rm -rf "$NIKKIGO_STATE_DIR"
}
