#!/bin/sh
set -eu

REPO_OWNER="${NIKKIGO_OWNER:-bezsildavno}"
BASE_URL="${NIKKIGO_BASE_URL:-https://raw.githubusercontent.com/$REPO_OWNER/nikkigo/main}"

say() {
	printf '%s\n' "$*"
}

fail() {
	printf 'Ошибка: %s\n' "$*" >&2
	exit 1
}

command -v ssh >/dev/null 2>&1 || fail "не найден клиент ssh"

default_gateway() {
	case "$(uname -s 2>/dev/null || printf unknown)" in
		Darwin)
			route -n get default 2>/dev/null |
				awk '/gateway:/{print $2; exit}'
			;;
		*)
			if command -v ip >/dev/null 2>&1; then
				ip route 2>/dev/null |
					awk '/^default /{print $3; exit}'
			elif command -v route >/dev/null 2>&1; then
				route -n 2>/dev/null |
					awk '$1 == "0.0.0.0" || $1 == "default" {print $2; exit}'
			fi
			;;
	esac
}

download() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "$1"
	else
		fail "нужен curl или wget"
	fi
}

gateway="$(default_gateway || true)"
[ -n "$gateway" ] || gateway="192.168.1.1"

say ""
say "============================================================"
say " NikkiGo — установка Nikki на OpenWrt"
say "============================================================"
say ""
say "Нужно ответить на четыре простых вопроса."
say "Значение в [скобках] — стандартное. Чтобы его выбрать, нажмите Enter."
say ""
say "[Шаг 1 из 4] Адрес роутера"
say "NikkiGo нашёл роутер по адресу $gateway."
printf 'Нажмите Enter для %s или введите другой адрес: ' "$gateway"
IFS= read -r router
router="${router:-$gateway}"

say ""
say "[Шаг 2 из 4] Логин роутера"
say "На большинстве роутеров OpenWrt используется логин root."
printf 'Нажмите Enter для root или введите другой логин: '
IFS= read -r ssh_user
ssh_user="${ssh_user:-root}"

say ""
say "[Шаг 3 из 4] Порт SSH"
say "На большинстве роутеров используется порт 22."
printf 'Нажмите Enter для 22 или введите другой порт: '
IFS= read -r ssh_port
ssh_port="${ssh_port:-22}"

say ""
say "[Шаг 4 из 4] Подписка"
say "Вставьте полную ссылку подписки и нажмите Enter."
printf 'Ссылка на подписку: '
IFS= read -r subscription
[ -n "$subscription" ] || fail "ссылка на подписку не указана"

case "$subscription" in
	http://*|https://*) ;;
	*) fail "ссылка должна начинаться с http:// или https://" ;;
esac

subscription_b64="$(
	printf '%s' "$subscription" |
		base64 |
		tr -d '\r\n'
)"
unset subscription

say ""
say "============================================================"
say " ДАЛЬШЕ: вход по SSH"
say "============================================================"
say "Сейчас NikkiGo подключится к $ssh_user@$router."
say ""
say "Если SSH спросит, доверяете ли вы устройству:"
say "  введите yes и нажмите Enter."
say ""
say "Когда появится строка $ssh_user@$router's password:"
say "  введите ПАРОЛЬ ОТ РОУТЕРА и нажмите Enter."
say "  Во время ввода не будет видно ничего — ни точек, ни звёздочек."
say "  Это нормально: клавиатура работает, пароль вводится."
say ""
say "Ожидание SSH..."
{
	printf "NIKKIGO_SUBSCRIPTION_B64='%s'\n" "$subscription_b64"
	download "$BASE_URL/router-install.sh"
} | ssh -tt -p "$ssh_port" "$ssh_user@$router" "ash -s"

say ""
say "УСПЕШНО: Nikki настроен и запущен."
