#!/bin/ash
set -eu

UPSTREAM_INSTALLER='https://raw.githubusercontent.com/lanetsky/nikkiopen/main/install.sh'
UPSTREAM_REPOSITORY='https://github.com/lanetsky/nikkiopen'
SUPPORT_BOT='@transib_service_gena_bot'
CURRENT_STAGE='запуск'
SUPPORT_SHOWN=0

say() {
	printf '[NikkiGo] %s\n' "$*"
}

show_support() {
	SUPPORT_SHOWN=1
	say "Если не получается исправить ошибку, напишите в Telegram-бот: $SUPPORT_BOT"
}

fail() {
	printf '[NikkiGo] Ошибка: %s\n' "$*" >&2
	show_support >&2
	exit 1
}

cleanup() {
	unset NIKKIGO_SUBSCRIPTION_B64 subscription_url
}

finish() {
	status=$?
	cleanup
	if [ "$status" -ne 0 ] && [ "$SUPPORT_SHOWN" -eq 0 ]; then
		printf '[NikkiGo] Неожиданная ошибка на этапе: %s\n' "$CURRENT_STAGE" >&2
		show_support >&2
	fi
	trap - EXIT
	exit "$status"
}
trap finish EXIT
trap 'exit 130' INT TERM

say "Устанавливается NikkiOpen из официального репозитория форка:"
say "$UPSTREAM_REPOSITORY"
say "Технические имена пакета и службы в OpenWrt: nikki."

CURRENT_STAGE='проверка прав и совместимости роутера'
[ "$(id -u)" = '0' ] || fail "требуются права root"
[ -r /etc/openwrt_release ] || fail "устройство не похоже на OpenWrt"
[ -x /sbin/fw4 ] || fail "Nikki требует OpenWrt с firewall4"
command -v uci >/dev/null 2>&1 || fail "не найден uci"
command -v wget >/dev/null 2>&1 || fail "не найден wget"

CURRENT_STAGE='проверка ссылки подписки'
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

CURRENT_STAGE='проверка доступа к GitHub'
say "Проверка соединения с GitHub"
wget -q --spider 'https://github.com' ||
	fail "роутер не может подключиться к GitHub. Проверьте интернет, DNS и время на роутере"

if [ ! -x /etc/init.d/nikki ]; then
	CURRENT_STAGE='подготовка менеджера пакетов'
	free_kb="$(df -Pk /overlay 2>/dev/null | awk 'NR == 2 { print $4 }')"
	if [ -n "$free_kb" ] && [ "$free_kb" -lt 32768 ]; then
		say "Предупреждение: в /overlay свободно меньше 32 МБ."
		say "Если установка пакетов не завершится, освободите место и повторите попытку."
	fi

	if [ -x /bin/opkg ]; then
		say "Обновление списков пакетов opkg"
		opkg update ||
			fail "opkg update завершился ошибкой. Проверьте feeds, интернет, DNS и системное время"
	elif [ -x /usr/bin/apk ]; then
		say "Обновление списков пакетов apk"
		apk update ||
			fail "apk update завершился ошибкой. Проверьте репозитории, интернет, DNS и системное время"
	else
		fail "не найден поддерживаемый менеджер пакетов opkg или apk"
	fi

	CURRENT_STAGE='установка NikkiOpen и зависимостей'
	say "Установка NikkiOpen из $UPSTREAM_REPOSITORY"
	if ! LUCI_I18N=1 wget -qO- "$UPSTREAM_INSTALLER" | ash; then
		say "Не удалось автоматически установить NikkiOpen."
		say "Проверьте ошибки пакетного менеджера выше."
		say "Основные зависимости: ca-bundle curl yq firewall4 ip-full"
		say "Модули ядра: kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun kmod-dummy"
		say "Ручная установка и готовые пакеты: $UPSTREAM_REPOSITORY/releases"
		fail "ошибка установки NikkiOpen или его зависимостей"
	fi
else
	say "NikkiOpen уже установлен; переустановка пропущена"
fi

[ -x /etc/init.d/nikki ] || fail "NikkiOpen не установился"

CURRENT_STAGE='настройка подписки SSH_TransibService'
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
CURRENT_STAGE='загрузка и проверка подписки'
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

CURRENT_STAGE='включение и запуск NikkiOpen'
say "Включение и запуск NikkiOpen"
uci -q batch <<EOF
set nikki.config.profile='subscription:ssh_transibservice'
set nikki.config.enabled='1'
commit nikki
EOF
/etc/init.d/nikki enable
/etc/init.d/nikki restart
sleep 3

if /etc/init.d/nikki running >/dev/null 2>&1; then
	say "NikkiOpen успешно запущен"
else
	logread -e Nikki 2>/dev/null | tail -n 20 || true
	fail "служба NikkiOpen не запустилась"
fi

CURRENT_STAGE='настройка ежедневного обновления подписки'
say "Настройка ежедневного обновления подписки на 05:00"
sed -i '/# nikkigo-update$/d' /etc/crontabs/root
echo '0 5 * * * /etc/init.d/nikki update_subscription ssh_transibservice; [ "$(uci -q get nikki.ssh_transibservice.success)" = "1" ] && /etc/init.d/nikki reload # nikkigo-update' >> /etc/crontabs/root
/etc/init.d/cron restart
