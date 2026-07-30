$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoOwner = if ($env:NIKKIGO_OWNER) { $env:NIKKIGO_OWNER } else { 'bezsildavno' }
$BaseUrl = if ($env:NIKKIGO_BASE_URL) {
    $env:NIKKIGO_BASE_URL.TrimEnd('/')
} else {
    "https://raw.githubusercontent.com/$RepoOwner/nikkigo/main"
}

function Stop-WithError([string]$Message) {
    Write-Error $Message
    exit 1
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Stop-WithError 'Не найден клиент OpenSSH. Установите компонент OpenSSH Client в Windows.'
}

$gateway = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1 -ExpandProperty NextHop
if (-not $gateway) {
    $gateway = '192.168.1.1'
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' NikkiGo — установка Nikki на OpenWrt' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Нужно ответить на четыре простых вопроса.'
Write-Host 'Чтобы выбрать предложенное значение, просто нажмите Enter.'
Write-Host ''

Write-Host '[Шаг 1 из 4] Адрес роутера' -ForegroundColor Yellow
Write-Host "NikkiGo нашёл роутер по адресу $gateway."
$router = Read-Host "Нажмите Enter для $gateway или введите другой адрес"
if ([string]::IsNullOrWhiteSpace($router)) { $router = $gateway }

Write-Host ''
Write-Host '[Шаг 2 из 4] Логин роутера' -ForegroundColor Yellow
Write-Host 'На большинстве роутеров OpenWrt используется логин root.'
$sshUser = Read-Host 'Нажмите Enter для root или введите другой логин'
if ([string]::IsNullOrWhiteSpace($sshUser)) { $sshUser = 'root' }

Write-Host ''
Write-Host '[Шаг 3 из 4] Порт SSH' -ForegroundColor Yellow
Write-Host 'На большинстве роутеров используется порт 22.'
$sshPort = Read-Host 'Нажмите Enter для 22 или введите другой порт'
if ([string]::IsNullOrWhiteSpace($sshPort)) { $sshPort = '22' }
if ($sshPort -notmatch '^\d{1,5}$' -or [int]$sshPort -gt 65535) {
    Stop-WithError 'Указан некорректный порт SSH.'
}

Write-Host ''
Write-Host '[Шаг 4 из 4] Подписка' -ForegroundColor Yellow
Write-Host 'Вставьте полную ссылку подписки и нажмите Enter.'
$subscription = Read-Host 'Ссылка подписки'
if ($subscription -notmatch '^https?://') {
    Stop-WithError 'Ссылка должна начинаться с http:// или https://.'
}

$subscriptionB64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($subscription)
)
$subscription = $null

$routerScript = (Invoke-WebRequest -UseBasicParsing "$BaseUrl/router-install.sh").Content
$payload = "NIKKIGO_SUBSCRIPTION_B64='$subscriptionB64'`n$routerScript"
$payloadB64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($payload)
)
$payload = $null

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
Write-Host 'Ожидание SSH...' -ForegroundColor Green
$payloadB64 | & ssh -T -p $sshPort "$sshUser@$router" "tr -d '\r\n' | base64 -d | ash"
$payloadB64 = $null
if ($LASTEXITCODE -ne 0) {
    Stop-WithError "Установка завершилась с кодом ошибки $LASTEXITCODE."
}

Write-Host ''
Write-Host 'УСПЕШНО: Nikki настроен и запущен.' -ForegroundColor Green
