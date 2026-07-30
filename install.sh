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

say "NikkiGo — установка Nikki на OpenWrt"
printf 'Адрес роутера [%s]: ' "$gateway"
IFS= read -r router
router="${router:-$gateway}"

printf 'SSH-пользователь [root]: '
IFS= read -r ssh_user
ssh_user="${ssh_user:-root}"

printf 'SSH-порт [22]: '
IFS= read -r ssh_port
ssh_port="${ssh_port:-22}"

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

say "Подключение к $ssh_user@$router. Пароль запросит SSH."
{
	printf "NIKKIGO_SUBSCRIPTION_B64='%s'\n" "$subscription_b64"
	download "$BASE_URL/router-install.sh"
} | ssh -tt -p "$ssh_port" "$ssh_user@$router" "ash -s"

say "Готово."
