#!/bin/sh
set -eu

REPO_OWNER="${NIKKIGO_OWNER:-bezsildavno}"
BASE_URL="${NIKKIGO_BASE_URL:-https://raw.githubusercontent.com/$REPO_OWNER/nikkigo/main}"
UPSTREAM_URL='https://github.com/lanetsky/nikkiopen'
SUPPORT_BOT='@transib_service_gena_bot'
SUPPORT_SHOWN=0

say() {
	printf '%s\n' "$*"
}

fail() {
	SUPPORT_SHOWN=1
	printf 'Ошибка: %s\n' "$*" >&2
	printf 'Если нужна помощь, напишите в Telegram-бот: %s\n' "$SUPPORT_BOT" >&2
	exit 1
}

finish_local() {
	status=$?
	if [ "$status" -ne 0 ] && [ "$SUPPORT_SHOWN" -eq 0 ]; then
		printf 'NikkiGo завершился с неожиданной ошибкой.\n' >&2
		printf 'Если нужна помощь, напишите в Telegram-бот: %s\n' "$SUPPORT_BOT" >&2
	fi
	trap - 0
	exit "$status"
}

trap finish_local 0

NIKKIGO_TTY_STATE=

restore_terminal() {
	if [ -n "$NIKKIGO_TTY_STATE" ]; then
		stty "$NIKKIGO_TTY_STATE" </dev/tty 2>/dev/null || true
		NIKKIGO_TTY_STATE=
	fi
}

cancel_input() {
	restore_terminal
	printf '\nОтменено пользователем.\n'
	exit "${1:-0}"
}

trap 'cancel_input 130' INT TERM HUP

read_input() {
	prompt="$1"
	printf '%s: ' "$prompt"

	if [ ! -t 0 ]; then
		IFS= read -r REPLY
		return
	fi

	NIKKIGO_TTY_STATE="$(stty -g </dev/tty)"
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
			27) cancel_input 0 ;;
			3) cancel_input 130 ;;
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

	restore_terminal
	printf '\n'
	REPLY="$value"
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
say " NikkiGo — установка NikkiOpen на OpenWrt"
say "============================================================"
say ""
say "Перед подключением нужно ответить на три простых вопроса."
say "Значение в [скобках] — стандартное. Чтобы его выбрать, нажмите Enter."
say "Исходный код NikkiOpen: $UPSTREAM_URL"
say ""
say "[Шаг 1 из 3] Адрес роутера"
say "NikkiGo нашёл роутер по адресу $gateway."
read_input "Нажмите Enter для $gateway или введите другой адрес"
router="$REPLY"
router="${router:-$gateway}"
case "$router" in
	''|*[!a-zA-Z0-9.-]*|.*|*.) fail "некорректный адрес роутера" ;;
	*.*) ;;
	*) fail "укажите IPv4-адрес или полное имя роутера" ;;
esac
case "$router" in
	*[!0-9.]*)
		;;
	*)
		if ! printf '%s' "$router" | awk -F. '
			NF != 4 { exit 1 }
			{
				for (i = 1; i <= 4; i++)
					if ($i !~ /^[0-9]+$/ || $i > 255) exit 1
			}
		'; then
			fail "некорректный IPv4-адрес роутера"
		fi
		;;
esac

say ""
say "[Шаг 2 из 3] Логин роутера"
say "На большинстве роутеров OpenWrt используется логин root."
read_input "Нажмите Enter для root или введите другой логин"
ssh_user="$REPLY"
ssh_user="${ssh_user:-root}"

say ""
say "[Шаг 3 из 3] Порт SSH"
say "На большинстве роутеров используется порт 22."
read_input "Нажмите Enter для 22 или введите другой порт"
ssh_port="$REPLY"
ssh_port="${ssh_port:-22}"

payload_b64="$(
	{
		router_b64="$(printf '%s' "$router" | base64 | tr -d '\r\n')"
		printf "NIKKIGO_ROUTER_ADDRESS_B64='%s'\n" "$router_b64"
		download "$BASE_URL/router-install.sh"
	} |
		base64 |
		tr -d '\r\n'
)"

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
say "После входа роутер предложит установку, обновление или удаление."
say "Ожидание SSH..."
ssh -tt -p "$ssh_port" "$ssh_user@$router" \
	"printf '%s' '$payload_b64' | base64 -d | ash"
unset payload_b64

say ""
say "NikkiGo завершил работу. Результат показан выше."
