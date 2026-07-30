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
    Stop-WithError 'OpenSSH Client was not found. Install the Windows OpenSSH Client feature.'
}

$gateway = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1 -ExpandProperty NextHop
if (-not $gateway) {
    $gateway = '192.168.1.1'
}

Write-Host 'NikkiGo - Nikki installer for OpenWrt'
$router = Read-Host "Router address [$gateway]"
if ([string]::IsNullOrWhiteSpace($router)) { $router = $gateway }

$sshUser = Read-Host 'SSH user [root]'
if ([string]::IsNullOrWhiteSpace($sshUser)) { $sshUser = 'root' }

$sshPort = Read-Host 'SSH port [22]'
if ([string]::IsNullOrWhiteSpace($sshPort)) { $sshPort = '22' }
if ($sshPort -notmatch '^\d{1,5}$' -or [int]$sshPort -gt 65535) {
    Stop-WithError 'Invalid SSH port.'
}

$subscription = Read-Host 'Subscription URL'
if ($subscription -notmatch '^https?://') {
    Stop-WithError 'The URL must start with http:// or https://.'
}

$subscriptionB64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($subscription)
)
$subscription = $null

$routerScript = (Invoke-WebRequest -UseBasicParsing "$BaseUrl/router-install.sh").Content
$payload = "NIKKIGO_SUBSCRIPTION_B64='$subscriptionB64'`n$routerScript"

Write-Host "Connecting to $sshUser@$router. SSH will ask for the password."
$payload | & ssh -tt -p $sshPort "$sshUser@$router" 'ash -s'
if ($LASTEXITCODE -ne 0) {
    Stop-WithError "Installation failed with exit code $LASTEXITCODE."
}

Write-Host 'Done.'
