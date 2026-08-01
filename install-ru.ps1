$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$UpstreamUrl = 'https://github.com/lanetsky/nikkiopen'
$RepoOwner = if ($env:NIKKIGO_OWNER) { $env:NIKKIGO_OWNER } else { 'bezsildavno' }
$BaseUrl = if ($env:NIKKIGO_BASE_URL) {
    $env:NIKKIGO_BASE_URL.TrimEnd('/')
} else {
    "https://raw.githubusercontent.com/$RepoOwner/nikkigo/main"
}

function Stop-WithError([string]$Message) {
    throw [InvalidOperationException]::new($Message)
}

function Test-RouterAddress([string]$Address) {
    $parsedAddress = $null
    if ([Net.IPAddress]::TryParse($Address, [ref]$parsedAddress)) {
        return $parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
    }
    return $Address -match '^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+$'
}

function Read-NikkiInput([string]$Prompt) {
    if ([Console]::IsInputRedirected) {
        $value = Read-Host $Prompt
        if ($value -eq [string][char]27) {
            throw [OperationCanceledException]::new('Отменено пользователем.')
        }
        return $value
    }

    Write-Host -NoNewline "${Prompt}: " -ForegroundColor Yellow
    $value = [Text.StringBuilder]::new()
    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Escape' {
                Write-Host ''
                throw [OperationCanceledException]::new('Отменено пользователем.')
            }
            'Enter' {
                Write-Host ''
                return $value.ToString()
            }
            'Backspace' {
                if ($value.Length -gt 0) {
                    $value.Length--
                    Write-Host -NoNewline "`b `b"
                }
            }
            default {
                if (-not [char]::IsControl($key.KeyChar)) {
                    [void]$value.Append($key.KeyChar)
                    Write-Host -NoNewline $key.KeyChar
                }
            }
        }
    }
}

Write-Host 'ВНИМАНИЕ: изменение программного обеспечения роутера выполняется на ваш страх и риск.' -ForegroundColor Yellow
Write-Host 'NikkiGo предоставляется «как есть», без гарантий.' -ForegroundColor Yellow
Write-Host 'Перед продолжением убедитесь, что у вас есть резервная копия и доступ к роутеру.'
$riskCode = Read-NikkiInput 'Для подтверждения ответственности введите 322'
if ($riskCode -ne '322') {
    Write-Host 'Операция отменена. Изменения не внесены.' -ForegroundColor Yellow
    return
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Stop-WithError 'Не найден клиент OpenSSH. Установите компонент OpenSSH Client в Windows.'
}

$gateway = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1 -ExpandProperty NextHop
$gatewayDetected = -not [string]::IsNullOrWhiteSpace($gateway)
if (-not $gatewayDetected) {
    $gateway = '192.168.1.1'
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' NikkiGo — установка Taproom Nikki на OpenWrt' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Перед подключением нужно ответить на три простых вопроса.'
Write-Host 'Чтобы выбрать предложенное значение, просто нажмите Enter.'
Write-Host "Исходный код Taproom Nikki: $UpstreamUrl"
Write-Host ''

Write-Host '[Шаг 1 из 3] Адрес роутера' -ForegroundColor Yellow
if ($gatewayDetected) {
    Write-Host "NikkiGo нашёл роутер по адресу $gateway."
} else {
    Write-Host 'NikkiGo не смог автоматически определить адрес роутера.'
    Write-Host "Предлагаемый адрес по умолчанию: $gateway."
}
$router = Read-NikkiInput "Нажмите Enter для $gateway или введите другой адрес"
if ([string]::IsNullOrWhiteSpace($router)) { $router = $gateway }
if (-not (Test-RouterAddress $router)) {
    Stop-WithError 'Некорректный адрес роутера. Укажите IPv4-адрес или полное имя устройства.'
}

Write-Host ''
Write-Host '[Шаг 2 из 3] Логин роутера' -ForegroundColor Yellow
Write-Host 'На большинстве роутеров OpenWrt используется логин root.'
$sshUser = Read-NikkiInput 'Нажмите Enter для root или введите другой логин'
if ([string]::IsNullOrWhiteSpace($sshUser)) { $sshUser = 'root' }

Write-Host ''
Write-Host '[Шаг 3 из 3] Порт SSH' -ForegroundColor Yellow
Write-Host 'На большинстве роутеров используется порт 22.'
$sshPort = Read-NikkiInput 'Нажмите Enter для 22 или введите другой порт'
if ([string]::IsNullOrWhiteSpace($sshPort)) { $sshPort = '22' }
if ($sshPort -notmatch '^\d{1,5}$' -or [int]$sshPort -gt 65535) {
    Stop-WithError 'Указан некорректный порт SSH.'
}

if ($BaseUrl -match "['`r`n]") {
    Stop-WithError 'Адрес загрузки содержит недопустимый символ.'
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' ДАЛЬШЕ: вход по SSH' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Сейчас NikkiGo подключится к $sshUser@$router."
Write-Host ''
Write-Host 'Если SSH спросит, доверяете ли вы устройству:' -ForegroundColor Yellow
Write-Host '  Введите yes и нажмите Enter.'
Write-Host ''
Write-Host "Когда появится строка $sshUser@$router's password:" -ForegroundColor Yellow
Write-Host '  Введите ПАРОЛЬ ОТ РОУТЕРА и нажмите Enter.'
Write-Host '  При вводе не будет видно ничего — ни точек, ни звёздочек.'
Write-Host '  Это нормально: клавиатура работает, пароль вводится.'
Write-Host ''
Write-Host 'После входа роутер предложит установку, обновление или удаление.' -ForegroundColor Cyan
Write-Host 'Ожидание SSH...' -ForegroundColor Green
$remoteCommand = @'
base_url='__BASE_URL__'
tmp="/tmp/nikkigo-$$.sh"
safety="/tmp/nikkigo-safety-$$.sh"
echo "[NikkiGo] SSH-подключение установлено. Скачивание сценария обслуживания..."
if ! wget -O "$tmp" "$base_url/router-install.sh?nikkigo=$(date +%s)"; then
    echo "[NikkiGo] ОШИБКА: не удалось скачать router-install.sh" >&2
    rm -f "$tmp"
    exit 91
fi
if ! wget -O "$safety" "$base_url/router-safety.sh?nikkigo=$(date +%s)"; then
    echo "[NikkiGo] ОШИБКА: не удалось скачать модуль безопасности" >&2
    rm -f "$tmp" "$safety"
    exit 91
fi
NIKKIGO_BASE_URL="$base_url" NIKKIGO_SAFETY_PATH="$safety" NIKKIGO_LANGUAGE='ru' NIKKIGO_ROUTER_ADDRESS='__ROUTER_ADDRESS__' ash "$tmp"
status=$?
rm -f "$tmp" "$safety"
exit "$status"
'@
$remoteCommand = $remoteCommand.Replace('__BASE_URL__', $BaseUrl)
$remoteCommand = $remoteCommand.Replace('__ROUTER_ADDRESS__', $router)
& ssh -tt -p $sshPort "$sshUser@$router" $remoteCommand
$sshExitCode = $LASTEXITCODE
if ($sshExitCode -eq -1 -or $sshExitCode -eq 255) {
    Stop-WithError 'SSH-подключение прервано или не установлено. Если вы нажали Ctrl+C или Esc, установка отменена; иначе проверьте адрес, SSH, логин, пароль и журнал роутера.'
}
if ($sshExitCode -eq 90) {
    Stop-WithError 'Роутер не смог прочитать адрес загрузки.'
}
if ($sshExitCode -eq 91) {
    Stop-WithError 'Роутер не смог скачать сценарий NikkiGo. Проверьте интернет, DNS и системное время на роутере.'
}
if ($sshExitCode -ne 0) {
    Stop-WithError "NikkiGo завершился на роутере с кодом $sshExitCode. Подробности показаны выше."
}

Write-Host ''
Write-Host 'NikkiGo завершил работу. Результат показан выше.' -ForegroundColor Green
