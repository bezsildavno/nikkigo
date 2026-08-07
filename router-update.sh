#!/bin/ash
set -eu

. /usr/lib/nikkigo/safety.sh
SECTION="${1:-$(uci -q get nikkigo.main.subscription_section 2>/dev/null || :)}"
reason='неизвестная ошибка'

case "$SECTION" in
	''|*[!a-zA-Z0-9_]*)
		safe_log 'Не задан корректный section ID подписки для автоматического обновления.'
		exit 1
		;;
esac
uci -q get "nikki.$SECTION" >/dev/null 2>&1 || {
	safe_log 'Настроенная секция подписки не найдена; обновление не выполнялось.'
	exit 1
}

rollback() {
	safe_log "Обновление подписки отменено: $reason"
	restore_state
	exit 1
}

finish() {
	status=$?
	trap - EXIT
	if [ "$status" -ne 0 ] && [ "${NIKKIGO_TRANSACTION:-0}" = '1' ]; then
		safe_log "Неожиданная ошибка обновления: $reason"
		restore_state
	fi
	exit "$status"
}
trap finish EXIT
trap 'reason="обновление прервано"; exit 1' INT TERM

backup_state || {
	reason='не удалось создать резервную копию'
	exit 1
}
capture_previous_selections ||
	safe_log 'Предупреждение: создать снимок selector-групп не удалось; будет использован безопасный автовыбор.'
if ! /etc/init.d/nikki update_subscription "$SECTION"; then
	reason='ошибка загрузки подписки'
	rollback
fi
[ "$(uci -q get nikki.$SECTION.success || :)" = '1' ] || {
	reason='подписка не прошла формальную проверку'
	rollback
}
enable_fail_open
uci -q set "nikki.config.profile=subscription:$SECTION"
uci -q set nikki.config.enabled='1'
uci -q set nikki.proxy.enabled='0'
uci -q set nikki.mixin.selection_cache='1'
uci -q commit nikki
/etc/init.d/nikki restart
sleep 3
validate_profile /etc/nikki/run/config.yaml || {
	reason='ошибка синтаксиса или запуска ядра'
	rollback
}
wait_for_api || {
	reason='локальный Mihomo API не запустился'
	rollback
}
select_safe_proxies ||
	safe_log 'Предварительный выбор proxy-group не выполнен; будет использован health-check.'
restore_previous_selections
ensure_zashboard || safe_log 'Zashboard будет повторно загружен после проверки интернета.'
uci -q set nikki.proxy.enabled='1'
uci -q commit nikki
/etc/init.d/nikki restart
if ! health_check; then
	safe_log 'Основная проверка не пройдена; проверяются альтернативные варианты.'
	try_recover_proxies || {
		reason='ни один из проверенных вариантов не восстановил DNS/HTTPS'
		rollback
	}
fi
ensure_zashboard || safe_log 'Предупреждение: Zashboard не подготовлен.'
commit_state
safe_log 'Подписка обновлена, функциональная проверка пройдена.'
