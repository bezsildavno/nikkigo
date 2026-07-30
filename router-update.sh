#!/bin/ash
set -eu

. /usr/lib/nikkigo/safety.sh
SECTION='ssh_transibservice'
reason='неизвестная ошибка'

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

backup_state
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
uci -q commit nikki
/etc/init.d/nikki restart
sleep 3
validate_profile /etc/nikki/run/config.yaml || {
	reason='ошибка синтаксиса или запуска ядра'
	rollback
}
select_safe_proxies || {
	reason='не найден безопасный первоначальный выбор proxy-group'
	rollback
}
ensure_zashboard || safe_log 'Предупреждение: Zashboard не подготовлен'
uci -q set nikki.proxy.enabled='1'
uci -q commit nikki
/etc/init.d/nikki restart
health_check || {
	reason='не прошла проверка службы, API, DNS или HTTPS'
	rollback
}
commit_state
safe_log 'Подписка обновлена, функциональная проверка пройдена.'
