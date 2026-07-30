# NikkiGo

Интерактивная установка
[lanetsky/nikkiopen](https://github.com/lanetsky/nikkiopen) на роутер с
OpenWrt через SSH.

## Linux и macOS

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.sh)"
```

## Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.ps1 | iex
```

Установщик:

1. определяет адрес основного шлюза;
2. спрашивает адрес, SSH-пользователя и порт;
3. принимает ссылку подписки;
4. подключается к роутеру штатным `ssh`;
5. устанавливает Nikki и русский перевод;
6. добавляет и проверяет подписку;
7. включает и запускает Nikki.

SSH-пароль не сохраняется и не передаётся установщику: его запрашивает
системный SSH-клиент.

## Требования

- роутер с поддерживаемой версией OpenWrt и firewall4;
- включённый SSH-доступ к роутеру;
- Windows 10/11 с OpenSSH Client, Linux или macOS;
- `curl` либо `wget` на Linux/macOS.
