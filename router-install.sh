#!/bin/ash
set -eu

UPSTREAM_INSTALLER='https://raw.githubusercontent.com/lanetsky/nikkiopen/main/install.sh'
UPSTREAM_UNINSTALLER='https://raw.githubusercontent.com/lanetsky/nikkiopen/main/uninstall.sh'
UPSTREAM_REPOSITORY='https://github.com/lanetsky/nikkiopen'
ZASHBOARD_REPOSITORY='https://github.com/Zephyruso/zashboard'
SUPPORT_BOT='@transib_service_gena_bot'
CURRENT_STAGE='запуск'
SUPPORT_SHOWN=0

[ -n "${NIKKIGO_SAFETY_PATH:-}" ] && [ -r "$NIKKIGO_SAFETY_PATH" ] || {
	printf '[NikkiGo] Ошибка: модуль безопасности не загружен\n' >&2
	exit 1
}
. "$NIKKIGO_SAFETY_PATH"

say() {
	printf '[NikkiGo] %s\n' "$*"
}

show_support() {
	SUPPORT_SHOWN=1
	say "Если не получается исправить ошибку, напишите в Telegram-бот: $SUPPORT_BOT"
	say "Пришлите скриншот текущего окна от команды запуска до ошибки"
	say "или скопируйте и отправьте весь текст из консоли."
}

fail() {
	printf '[NikkiGo] Ошибка: %s\n' "$*" >&2
	show_support >&2
	exit 1
}

REMOTE_TTY_STATE=

restore_remote_terminal() {
	if [ -n "$REMOTE_TTY_STATE" ]; then
		stty "$REMOTE_TTY_STATE" </dev/tty 2>/dev/null || true
		REMOTE_TTY_STATE=
	fi
}

read_remote_input() {
	prompt="$1"
	printf '[NikkiGo] %s: ' "$prompt"
	if ! command -v stty >/dev/null 2>&1 ||
		! command -v od >/dev/null 2>&1 ||
		[ ! -r /dev/tty ]; then
		IFS= read -r REPLY
		return
	fi
	REMOTE_TTY_STATE="$(stty -g </dev/tty)"
	stty -icanon -echo min 1 time 0 </dev/tty
	value=
	while :; do
		code="$(
			dd if=/dev/tty bs=1 count=1 2>/dev/null |
				od -An -tu1 |
				tr -d ' '
		)"
		[ -n "$code" ] || continue
		case "$code" in
			27)
				restore_remote_terminal
				printf '\n[NikkiGo] Отменено пользователем.\n'
				exit 0
				;;
			3)
				restore_remote_terminal
				exit 130
				;;
			10|13) break ;;
			8|127)
				if [ -n "$value" ]; then
					value="${value%?}"
					printf '\b \b'
				fi
				;;
			*)
				octal="$(printf '%03o' "$code")"
				char="$(printf "\\$octal")"
				value="${value}${char}"
				printf '%s' "$char"
				;;
		esac
	done
	restore_remote_terminal
	printf '\n'
	REPLY="$value"
}

cleanup() {
	restore_remote_terminal
	unset NIKKIGO_LANGUAGE NIKKIGO_ROUTER_ADDRESS_B64 router_address subscription_url action
}

finish() {
	status=$?
	if [ "$status" -ne 0 ] && [ "${NIKKIGO_TRANSACTION:-0}" = '1' ]; then
		restore_state
	fi
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
say "Веб-панель Zashboard устанавливается из официального репозитория:"
say "$ZASHBOARD_REPOSITORY"

CURRENT_STAGE='проверка прав и совместимости роутера'
[ "$(id -u)" = '0' ] || fail "требуются права root"
[ -r /etc/openwrt_release ] || fail "устройство не похоже на OpenWrt"
[ -x /sbin/fw4 ] || fail "Nikki требует OpenWrt с firewall4"
command -v uci >/dev/null 2>&1 || fail "не найден uci"
command -v wget >/dev/null 2>&1 || fail "не найден wget"

CURRENT_STAGE='определение адреса панели управления'
[ -n "${NIKKIGO_ROUTER_ADDRESS_B64:-}" ] || fail "не передан адрес роутера"
router_address="$(
	printf '%s' "$NIKKIGO_ROUTER_ADDRESS_B64" |
		base64 -d 2>/dev/null
)" || fail "не удалось прочитать адрес роутера"
unset NIKKIGO_ROUTER_ADDRESS_B64

CURRENT_STAGE='проверка доступа к GitHub'
say "Проверка соединения с GitHub"
wget -q --spider 'https://github.com' ||
	fail "роутер не может подключиться к GitHub. Проверьте интернет, DNS и время на роутере"

if [ -x /etc/init.d/nikki ]; then
	if [ -x /bin/opkg ]; then
		installed_version="$(opkg status nikki 2>/dev/null | awk -F': ' '$1 == "Version" { print $2; exit }')"
	elif [ -x /usr/bin/apk ]; then
		installed_version="$(apk list --installed nikki 2>/dev/null | sed -n '1s/.*-//p')"
	else
		installed_version=
	fi
	say "NikkiOpen уже установлен${installed_version:+, версия $installed_version}."
	say "1 — обновить NikkiOpen и настроить подписку"
	say "2 — удалить NikkiOpen и его конфигурацию"
	say "3 — выйти без изменений"
	read_remote_input "Выберите действие [1]"
	action="${REPLY:-1}"
	case "$action" in
		1) action='update' ;;
		2) action='remove' ;;
		3) say "Выход без изменений."; exit 0 ;;
		*) fail "неизвестное действие: $action" ;;
	esac
else
	action='install'
	say "NikkiOpen не обнаружен. Будет выполнена установка."
fi

if [ "$action" = 'remove' ]; then
	say "ВНИМАНИЕ: будут удалены NikkiOpen, подписки, настройки и логи."
	read_remote_input "Для подтверждения введите 1337"
	[ "$REPLY" = '1337' ] ||
		fail "удаление не подтверждено; изменения не внесены"
	CURRENT_STAGE='удаление NikkiOpen'
	sed -i '/# nikkigo-update$/d' /etc/crontabs/root 2>/dev/null || true
	/etc/init.d/cron restart 2>/dev/null || true
	if ! wget -qO- "$UPSTREAM_UNINSTALLER" | ash; then
		fail "штатное удаление NikkiOpen завершилось ошибкой"
	fi
	say "NikkiOpen и его конфигурация удалены."
	exit 0
fi

CURRENT_STAGE='создание резервной копии рабочего состояния'
say "Сохранение текущей конфигурации и состояния NikkiOpen"
if ! backup_state; then
	fail "не удалось создать резервную копию перед установкой"
fi
enable_fail_open
say "Предварительная загрузка Zashboard"
prepare_zashboard ||
	say "Zashboard пока не загружен; NikkiGo повторит попытку после установки пакетов."

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

CURRENT_STAGE="${action} NikkiOpen и зависимостей"
if [ "$action" = 'update' ]; then
	say "Обновление NikkiOpen из $UPSTREAM_REPOSITORY"
else
	say "Установка NikkiOpen из $UPSTREAM_REPOSITORY"
fi
if ! LUCI_I18N=1 wget -qO- "$UPSTREAM_INSTALLER" | ash; then
	say "Не удалось автоматически установить или обновить NikkiOpen."
	say "Проверьте ошибки пакетного менеджера выше."
	say "Основные зависимости: ca-bundle curl yq firewall4 ip-full"
	say "Модули ядра: kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun kmod-dummy"
	say "Ручная установка и готовые пакеты: $UPSTREAM_REPOSITORY/releases"
	fail "ошибка установки NikkiOpen или его зависимостей"
fi

[ -x /etc/init.d/nikki ] || fail "NikkiOpen не установился"

if [ "${NIKKIGO_LANGUAGE:-ru}" = 'ru' ]; then
	CURRENT_STAGE='установка русского языка NikkiOpen'
	say "Установка русского языка панели NikkiOpen"
	if [ -x /bin/opkg ]; then
		if opkg install luci-i18n-nikki-ru; then
			say "Русский язык панели NikkiOpen установлен."
		else
			say "Предупреждение: пакет luci-i18n-nikki-ru недоступен для этой прошивки."
			say "NikkiOpen установлен и продолжит работать с языком, доступным в LuCI."
		fi
	elif [ -x /usr/bin/apk ]; then
		if apk add luci-i18n-nikki-ru; then
			say "Русский язык панели NikkiOpen установлен."
		else
			say "Предупреждение: пакет luci-i18n-nikki-ru недоступен для этой прошивки."
			say "NikkiOpen установлен и продолжит работать с языком, доступным в LuCI."
		fi
	fi
fi

say "Автообновление самого пакета upstream не предоставляет."
say "NikkiGo включит автоматическое обновление подписки."

CURRENT_STAGE='ввод ссылки подписки'
if uci -q get nikki.ssh_transibservice >/dev/null 2>&1; then
	existing_name="$(uci -q get nikki.ssh_transibservice.name || true)"
	say "Подписка ${existing_name:-ssh_transibservice} уже существует."
	say "Новая копия создана не будет; существующая подписка будет обновлена."
fi
read_remote_input "Вставьте ссылку подписки"
subscription_url="$REPLY"
[ -n "$subscription_url" ] || fail "ссылка подписки не указана"
case "$subscription_url" in
	http://*|https://*) ;;
	*) fail "ссылка должна начинаться с http:// или https://" ;;
esac
case "$subscription_url" in
	*"'"*) fail "ссылка содержит недопустимый символ" ;;
esac
sanitized_url="$(printf '%s' "$subscription_url" | tr -d '\r\n')"
[ "$sanitized_url" = "$subscription_url" ] ||
	fail "ссылка содержит перенос строки"
unset sanitized_url

subscription_name="${subscription_url#*://}"
subscription_name="${subscription_name%%/*}"
subscription_name="${subscription_name%%\?*}"
subscription_name="${subscription_name%%\#*}"
[ -n "$subscription_name" ] ||
	fail "не удалось определить имя подписки из ссылки"
say "Имя подписки определено из ссылки: $subscription_name"

existing_url="$(uci -q get nikki.ssh_transibservice.url || true)"
if [ -n "$existing_url" ]; then
	if [ "$existing_url" = "$subscription_url" ]; then
		say "Введена та же ссылка. Выполняется обновление существующей подписки."
	else
		say "Ссылка существующей подписки будет заменена новой."
	fi
fi

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
set nikki.ssh_transibservice.name='$subscription_name'
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
	fail "Nikki не смог загрузить подписку; будет восстановлено прежнее состояние"
fi

subscription_file="/etc/nikki/subscriptions/ssh_transibservice.yaml"
CURRENT_STAGE='проверка синтаксиса нового профиля'
yq -M -p yaml -o yaml -e \
	'(has("proxies") or has("proxy-providers")) and has("proxy-groups")' \
	"$subscription_file" >/dev/null 2>&1 ||
	fail "новая подписка скачана, но профиль имеет некорректную структуру"

CURRENT_STAGE='безопасный запуск ядра без перехвата трафика'
say "Проверка ядра без перехвата DNS и трафика"
uci -q batch <<EOF
set nikki.config.profile='subscription:ssh_transibservice'
set nikki.config.enabled='1'
set nikki.proxy.enabled='0'
commit nikki
EOF
/etc/init.d/nikki enable
/etc/init.d/nikki restart
sleep 3

/etc/init.d/nikki running >/dev/null 2>&1 ||
	fail "ядро NikkiOpen не запустилось; будет выполнен rollback"
validate_profile /etc/nikki/run/config.yaml ||
	fail "итоговый профиль не прошёл проверку ядра; будет выполнен rollback"

CURRENT_STAGE='подготовка панели Zashboard'
if ensure_zashboard; then
	say "Панель Zashboard подготовлена: /etc/nikki/run/ui/index.html"
else
	say "Предупреждение: Zashboard подготовить не удалось; это не влияет на обычный интернет."
fi

CURRENT_STAGE='безопасный выбор прокси'
select_safe_proxies ||
	fail "не удалось безопасно подготовить proxy-group; перехват трафика не включён"

CURRENT_STAGE='включение перехвата и проверка интернета'
say "Включение NikkiOpen и проверка DNS/HTTPS"
uci -q set nikki.proxy.enabled='1'
uci -q commit nikki
/etc/init.d/nikki restart
if ! health_check; then
	say "Основная проверка интернета не пройдена."
	say "Проверка до 8 альтернативных вариантов из подписки..."
	if ! try_recover_proxies; then
		fail "ни один проверенный вариант не восстановил DNS/HTTPS; выполняется rollback"
	fi
fi
say "NikkiOpen успешно запущен; DNS и HTTPS работают."
if curl -fsS --max-time 5 "$(controller_url)/ui/" >/dev/null 2>&1; then
	say "Zashboard отвечает через локальный controller."
else
	say "Предупреждение: Zashboard не отвечает, но интернет работает."
fi

CURRENT_STAGE='настройка ежедневного обновления подписки'
say "Настройка ежедневного обновления подписки на 05:00"
mkdir -p /usr/lib/nikkigo
cp "$NIKKIGO_SAFETY_PATH" /usr/lib/nikkigo/safety.sh
wget -q -O /usr/lib/nikkigo/update.sh \
	"$NIKKIGO_BASE_URL/router-update.sh?nikkigo=$(date +%s)" ||
	fail "не удалось установить безопасный модуль ежедневного обновления"
chmod 755 /usr/lib/nikkigo/safety.sh /usr/lib/nikkigo/update.sh
sed -i '/# nikkigo-update$/d' /etc/crontabs/root
echo '0 5 * * * /usr/lib/nikkigo/update.sh >>/var/log/nikkigo-update.log 2>&1 # nikkigo-update' >> /etc/crontabs/root
/etc/init.d/cron restart
commit_state

expire_at="$(uci -q get nikki.ssh_transibservice.expire || true)"
updated_at="$(uci -q get nikki.ssh_transibservice.update || true)"
say "Подписка $subscription_name успешно загружена."
if [ -n "$updated_at" ]; then
	say "Последнее обновление: $updated_at"
fi
if [ -n "$expire_at" ]; then
	say "Подписка действует до: $expire_at"
else
	say "Провайдер не сообщил дату окончания подписки."
fi
say "Панель управления NikkiOpen:"
say "http://$router_address/cgi-bin/luci/admin/services/nikki"
say "Если LuCI настроен на HTTPS, замените http:// на https://."
