# Ручная установка NikkiOpen

[English](MANUAL_INSTALL.md) | [Русский](MANUAL_INSTALL.ru.md)

Это руководство устанавливает Taproom Nikki Fork из официальных пакетов
[lanetsky/nikkiopen](https://github.com/lanetsky/nikkiopen) без запуска
NikkiGo или другого установочного скрипта.

> Перед началом сохраните конфигурацию роутера. Ошибка в прокси или DNS может
> лишить устройства в локальной сети доступа в интернет. Не закрывайте
> SSH-сессию до завершения проверок.

## Перед подключением к роутеру

Сначала скачайте на компьютер всё, что может понадобиться. Не начинайте
изменять роутер, пока файлы не готовы. Если версия OpenWrt или архитектура
неизвестна, сначала выполните только команды чтения из раздела 1, отключитесь,
скачайте подходящие файлы и затем подключитесь снова.

1. Архив NikkiOpen для вашей версии OpenWrt и архитектуры со страницы
   [официальных релизов](https://github.com/lanetsky/nikkiopen/releases).
2. Резервный архив `dist-cdn-fonts.zip` со страницы
   [официальных релизов Zashboard](https://github.com/Zephyruso/zashboard/releases).
   Он понадобится только в том случае, если панель не окажется внутри
   установленного пакета или не будет подготовлена самим NikkiOpen.
3. Программу для передачи файлов по SCP/SFTP либо штатную команду `scp`.

Официальные клиенты с графическим интерфейсом:

- Windows — [WinSCP](https://winscp.net/eng/download.php);
- Windows и macOS — [Cyberduck](https://cyberduck.io/download/);
- Windows, macOS и Linux —
  [FileZilla Client](https://filezilla-project.org/download.php?type=client).

Скачивайте программы только с указанных официальных сайтов. В WinSCP сначала
выберите протокол SCP, укажите адрес роутера, порт SSH (обычно `22`) и
пользователя `root`. Cyberduck и FileZilla используют SFTP и сработают только
тогда, когда SFTP-сервер установлен на роутере.

Пользователи Linux и macOS могут ничего не устанавливать и передать файлы из
терминала:

```sh
scp -O nikki_*.tar.gz dist-cdn-fonts.zip root@АДРЕС_РОУТЕРА:/tmp/
```

Ключ `-O` принудительно включает классический SCP, совместимый со штатным
Dropbear на многих сборках OpenWrt.

## 1. Проверка роутера

Подключитесь по SSH и выполните:

```sh
cat /etc/openwrt_release
uname -r
uname -m
test -x /sbin/fw4 && echo "firewall4: OK"
```

Нужны поддерживаемая версия OpenWrt, Linux kernel не ниже 5.13 и `firewall4`.
Определите менеджер пакетов:

```sh
command -v apk || command -v opkg
```

## 2. Резервная копия

```sh
mkdir -p /root/nikki-backup
cp -p /etc/config/nikki /root/nikki-backup/ 2>/dev/null || true
cp -Rp /etc/nikki/subscriptions /root/nikki-backup/ 2>/dev/null || true
```

Если Nikki уже установлен, перед изменениями остановите его:

```sh
/etc/init.d/nikki stop 2>/dev/null || true
```

Штатная остановка убирает созданный Nikki перехват DNS и трафика.

## 3. Получение официальных пакетов

Передайте заранее скачанный архив в `/tmp` через SFTP/SCP. Например, имя
архива может выглядеть так:

```text
nikki_aarch64_cortex-a53-openwrt-25.12.tar.gz
```

```sh
mkdir -p /tmp/nikki-manual
tar -xzf /tmp/nikki_*.tar.gz -C /tmp/nikki-manual
cd /tmp/nikki-manual
```

Не устанавливайте пакет другой архитектуры или версии OpenWrt.

## 4. Установка пакетов

### OpenWrt с apk

```sh
apk update
apk add --allow-untrusted ./nikki-*.apk ./luci-app-nikki-*.apk
apk add --allow-untrusted ./luci-i18n-nikki-ru-*.apk
```

### OpenWrt с opkg

```sh
opkg update
opkg install ./nikki_*.ipk ./luci-app-nikki_*.ipk
opkg install ./luci-i18n-nikki-ru_*.ipk
```

Перезапустите backend LuCI без перезагрузки роутера:

```sh
rm -f /tmp/luci-indexcache
/etc/init.d/rpcd restart
/etc/init.d/uhttpd reload
ubus -S list luci.nikki
```

Последняя команда должна вывести `luci.nikki`.

## 5. Добавление подписки

Откройте:

```text
http://АДРЕС_РОУТЕРА/cgi-bin/luci/admin/services/nikki
```

В разделе профилей или подписок создайте подписку:

- имя — понятное вам название;
- URL — ссылка, выданная провайдером;
- User-Agent — `Clash.Meta`;
- предпочтение — удалённая версия.

Не публикуйте URL подписки: он может содержать токен, UUID или другие
секретные данные.

В настройках приложения выберите созданную подписку как активный профиль.
Включите проверку профиля, но пока не включайте проксирование локальной сети.

## 6. Первый безопасный запуск

Сначала отключите перехват:

```sh
uci set nikki.proxy.enabled='0'
uci set nikki.config.enabled='1'
uci commit nikki
/etc/init.d/nikki enable
/etc/init.d/nikki restart
sleep 3
/etc/init.d/nikki running && echo "Nikki core: OK"
```

Проверьте журнал:

```sh
tail -n 30 /var/log/nikki/app.log
tail -n 30 /var/log/nikki/core.log
```

В журнале должны присутствовать успешная проверка профиля и запуск ядра.

## 7. Zashboard

Официальный проект:
[Zephyruso/zashboard](https://github.com/Zephyruso/zashboard).

Сначала проверьте, установлена ли панель самим пакетом NikkiOpen:

```sh
test -f /etc/nikki/run/ui/index.html && echo "Zashboard уже установлен"
```

Если файл существует, ничего скачивать или копировать не нужно. Откройте
панель и переходите к следующему разделу.

Только если файла нет, используйте заранее скачанный официальный архив
`dist-cdn-fonts.zip`, переданный в `/tmp`. Распакуйте его во временный каталог:

```sh
mkdir -p /tmp/zashboard-unpack
unzip -q /tmp/dist-cdn-fonts.zip -d /tmp/zashboard-unpack
find /tmp/zashboard-unpack -name index.html
```

Если найден `/tmp/zashboard-unpack/dist/index.html`, копировать нужно
содержимое `dist`, а не сам каталог `dist`:

```sh
mkdir -p /etc/nikki/run/ui
cp -Rp /tmp/zashboard-unpack/dist/. /etc/nikki/run/ui/
test -f /etc/nikki/run/ui/index.html && echo "Zashboard: OK"
```

Если `index.html` находится в корне архива:

```sh
cp -Rp /tmp/zashboard-unpack/. /etc/nikki/run/ui/
```

Каталог `/etc/nikki/run` может пересоздаваться при запуске Nikki, поэтому
панель устанавливается после генерации run-конфигурации.

## 8. Включение и проверка интернета

```sh
uci set nikki.proxy.enabled='1'
uci commit nikki
/etc/init.d/nikki restart
sleep 3
```

Проверьте службу, DNS и HTTPS:

```sh
/etc/init.d/nikki running
nslookup example.com
curl -fsS --max-time 10 -o /dev/null https://www.gstatic.com/generate_204
```

Повторите проверки несколько раз. Успешное скачивание подписки само по себе
не доказывает работоспособность прокси.

Если DNS или HTTPS не работают, немедленно выполните fail-open:

```sh
/etc/init.d/nikki stop
uci set nikki.config.enabled='0'
uci commit nikki
```

После этого обычный интернет должен восстановиться. Не отключайте firewall
целиком и не перезагружайте роутер.

## 9. Ручное обновление подписки

Узнайте идентификатор секции:

```sh
uci show nikki | grep '=subscription'
```

Обновите нужную секцию:

```sh
/etc/init.d/nikki update_subscription ИДЕНТИФИКАТОР_СЕКЦИИ
```

Проверьте флаг:

```sh
uci -q get nikki.ИДЕНТИФИКАТОР_СЕКЦИИ.success
```

Значение `1` подтверждает только загрузку и формальную проверку. После
перезапуска снова проверьте службу, DNS и HTTPS.

## 10. Удаление

Используйте официальный
[uninstall.sh](https://github.com/lanetsky/nikkiopen/blob/main/uninstall.sh)
либо удалите установленные пакеты через `apk`/`opkg`. Перед удалением:

```sh
/etc/init.d/nikki stop
/etc/init.d/nikki disable
```

После завершения удалите временные каталоги:

```sh
rm -rf /tmp/nikki-manual /tmp/zashboard-unpack
```
