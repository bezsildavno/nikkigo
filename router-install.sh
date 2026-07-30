#!/bin/ash
set -eu

UPSTREAM_INSTALLER='https://raw.githubusercontent.com/lanetsky/nikkiopen/main/install.sh'

say() {
	printf '[NikkiGo] %s\n' "$*"
}

fail() {
	printf '[NikkiGo] Ошибка: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	unset NIKKIGO_SUBSCRIPTION_B64 subscription_url
}
trap cleanup EXIT INT TERM

[ "$(id -u)" = '0' ] || fail "требуются права root"
[ -r /etc/openwrt_release ] || fail "устройство не похоже на OpenWrt"
[ -x /sbin/fw4 ] || fail "Nikki требует OpenWrt с firewall4"
command -v uci >/dev/null 2>&1 || fail "не найден uci"
command -v wget >/dev/null 2>&1 || fail "не найден wget"

[ -n "${NIKKIGO_SUBSCRIPTION_B64:-}" ] || fail "не передана подписка"
subscription_url="$(
	printf '%s' "$NIKKIGO_SUBSCRIPTION_B64" |
		base64 -d 2>/dev/null
)" || fail "не удалось прочитать подписку"

case "$subscription_url" in
	http://*|https://*) ;;
	*) fail "некорректная ссылка подписки" ;;
esac
case "$subscription_url" in
	*"'"*) fail "ссылка содержит недопустимый символ" ;;
esac
sanitized_url="$(printf '%s' "$subscription_url" | tr -d '\r\n')"
[ "$sanitized_url" = "$subscription_url" ] ||
	fail "ссылка содержит перенос строки"
unset sanitized_url

say "Проверка соединения с GitHub"
wget -q --spider 'https://github.com' ||
	fail "роутер не может подключиться к GitHub"

if [ ! -x /etc/init.d/nikki ]; then
	say "Установка Nikki из lanetsky/nikkiopen"
	LUCI_I18N=1 wget -qO- "$UPSTREAM_INSTALLER" | ash
else
	say "Nikki уже установлен; переустановка пропущена"
fi

[ -x /etc/init.d/nikki ] || fail "Nikki не установился"

say "Настройка подписки"
previous_profile="$(uci -q get nikki.config.profile || true)"

# Repair the default section only when an older NikkiGo version overwrote it.
if [ "$(uci -q get nikki.subscription.name || true)" = 'NikkiGo' ]; then
	uci -q batch <<EOF
set nikki.subscription=subscription
set nikki.subscription.name='default'
set nikki.subscription.url='http://example.com/default.yaml'
set nikki.subscription.user_agent='clash'
set nikki.subscription.prefer='remote'
commit nikki
EOF
	uci -q delete nikki.subscription.success || true
	uci -q delete nikki.subscription.update || true
	uci commit nikki
fi

uci -q batch <<EOF
set nikki.ssh_transibservice=subscription
set nikki.ssh_transibservice.name='SSH_TransibService'
set nikki.ssh_transibservice.url='$subscription_url'
set nikki.ssh_transibservice.user_agent='Clash.Meta'
set nikki.ssh_transibservice.prefer='remote'
commit nikki
EOF
unset subscription_url NIKKIGO_SUBSCRIPTION_B64

say "Загрузка и проверка подписки"
/etc/init.d/nikki update_subscription ssh_transibservice
success="$(uci -q get nikki.ssh_transibservice.success || true)"
if [ "$success" != '1' ]; then
	say "Последние сообщения Nikki:"
	tail -n 10 /var/log/nikki/app.log 2>/dev/null || true
	if [ -n "$previous_profile" ]; then
		uci set "nikki.config.profile=$previous_profile"
		uci commit nikki
	fi
	fail "Nikki не смог загрузить или проверить подписку; прежний профиль сохранён"
fi

say "Включение и запуск Nikki"
uci -q batch <<EOF
set nikki.config.profile='subscription:ssh_transibservice'
set nikki.config.enabled='1'
commit nikki
EOF
/etc/init.d/nikki enable
/etc/init.d/nikki restart
sleep 3

if /etc/init.d/nikki running >/dev/null 2>&1; then
	say "Nikki успешно запущен"
else
	logread -e Nikki 2>/dev/null | tail -n 20 || true
	fail "служба Nikki не запустилась"
fi

say "Настройка ежедневного обновления подписки на 05:00"
sed -i '/# nikkigo-update$/d' /etc/crontabs/root
echo '0 5 * * * /etc/init.d/nikki update_subscription ssh_transibservice; [ "$(uci -q get nikki.ssh_transibservice.success)" = "1" ] && /etc/init.d/nikki reload # nikkigo-update' >> /etc/crontabs/root
/etc/init.d/cron restart
