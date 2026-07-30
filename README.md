# NikkiGo

[English](README.md) | [Русский](README.ru.md)

Interactive SSH installer for deploying the Taproom Nikki fork from
[lanetsky/nikkiopen](https://github.com/lanetsky/nikkiopen) to an OpenWrt
router.

Prefer not to run an installer? See the
[fully manual installation guide](MANUAL_INSTALL.md).

NikkiGo is an independent project. See
[third-party notices and licenses](THIRD_PARTY_NOTICES.md).
Use of the project is subject to the [disclaimer](DISCLAIMER.md).

## Linux and macOS

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.sh)"
```

## Windows PowerShell

The language is selected automatically from the Windows locale:

```powershell
irm https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.ps1 | iex
```

Force Russian:

```powershell
$env:NIKKIGO_LANG='ru'; irm https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.ps1 | iex
```

Force English:

```powershell
$env:NIKKIGO_LANG='en'; irm https://raw.githubusercontent.com/bezsildavno/nikkigo/main/install.ps1 | iex
```

The installer:

1. detects the default gateway;
2. asks for the router address, SSH user, and port;
3. connects using the system `ssh` client;
4. detects whether Taproom Nikki is installed;
5. offers installation or update, and removal for an existing installation;
6. requests the subscription URL during installation or update;
7. derives its name from the URL domain and updates one stable section without duplicates;
8. backs up the working state and starts the core without traffic interception;
9. checks the profile, local API, DNS, and HTTPS before enabling interception;
10. updates the subscription transactionally every day at 05:00 and rolls back on failure;
11. shows the subscription expiration date and LuCI panel URL.

## Fail-open and automatic rollback

A successful subscription download and syntax check do not prove that the
proxy works. NikkiGo first saves UCI, the active profile, subscription files,
and service state. It starts the new core without intercepting DNS or traffic.
After preparing safe proxy-group selections, NikkiGo enables interception and
repeatedly checks:

- the service and local Mihomo API;
- DNS resolution of a control domain;
- HTTPS access to a control endpoint.

If these checks fail, Nikki is stopped normally, its interception rules are
removed, and the previous working state is restored. The router is never
rebooted.

Before rollback, NikkiGo asks the local Mihomo API to test up to eight
subscription options. Names, countries, emojis, and proxy protocols are not
hard-coded. Each candidate gets a four-second delay test followed by a real
DNS and HTTPS check. If none works, a fresh installation leaves Nikki
disabled; an update restores the previous state only when that state passed
its own health check.

## Zashboard

The web dashboard is provided by the official
[Zephyruso/zashboard](https://github.com/Zephyruso/zashboard) project.
Its archive is downloaded to a temporary staging directory.
NikkiGo supports archives containing either a root `index.html` or
`dist/index.html`, and installs the contents so the final file is
`/etc/nikki/run/ui/index.html`.

To open the controls, sign in to the router's regular web interface and go to
`Services → Nikki`, then click `Open Panel`. Sign out and back in after
installation because restarting `rpcd` may invalidate the previous LuCI
session.

Zashboard failure is reported separately and does not by itself disable
normal internet access.

## Diagnostics

Diagnostics distinguish subscription download, YAML structure, core startup,
local API, DNS/HTTPS, and Zashboard failures. Daily updates write a short
sanitized result to `/var/log/nikkigo-update.log`.

The SSH password is neither stored nor handled by NikkiGo. The system SSH
client requests it directly.

For additional help, contact the you're provider and send a screenshot from the launch command
through the error, or copy the complete console output.

## Requirements

- a supported OpenWrt router with firewall4;
- SSH access enabled on the router;
- Windows 10/11 with OpenSSH Client, Linux, or macOS;
- `curl` or `wget` on Linux/macOS.
