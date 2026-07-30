# NikkiGo

Интерактивная установка NikkiOpen из
[lanetsky/nikkiopen](https://github.com/lanetsky/nikkiopen) на роутер с
OpenWrt через SSH.

## Linux и macOS

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.sh)"
```

## Windows PowerShell

Язык определяется автоматически по настройкам Windows:

```powershell
irm https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.ps1 | iex
```

Принудительно выбрать русский:

```powershell
$env:NIKKIGO_LANG='ru'; irm https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.ps1 | iex
```

Принудительно выбрать английский:

```powershell
$env:NIKKIGO_LANG='en'; irm https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.ps1 | iex
```

Установщик:

1. определяет адрес основного шлюза;
2. спрашивает адрес, SSH-пользователя и порт;
3. подключается к роутеру штатным `ssh`;
4. определяет, установлен ли NikkiOpen;
5. предлагает установку либо обновление, а для установленного пакета — удаление;
6. при установке/обновлении принимает ссылку подписки;
7. берёт имя подписки из домена ссылки и обновляет существующую секцию без дубликата;
8. проверяет подписку и сохраняет прежний профиль при ошибке;
9. включает NikkiOpen;
10. ежедневно в 05:00 обновляет подписку и применяет её только при успехе;
11. показывает срок подписки и ссылку на панель LuCI.

SSH-пароль не сохраняется и не передаётся установщику: его запрашивает
системный SSH-клиент.

При ошибке установщик показывает этап и диагностику. Дополнительная помощь:
Telegram-бот `@transib_service_gena_bot`.

## Требования

- роутер с поддерживаемой версией OpenWrt и firewall4;
- включённый SSH-доступ к роутеру;
- Windows 10/11 с OpenSSH Client, Linux или macOS;
- `curl` либо `wget` на Linux/macOS.
