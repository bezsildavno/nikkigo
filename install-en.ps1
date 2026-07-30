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

function Read-NikkiInput([string]$Prompt) {
    if ([Console]::IsInputRedirected) {
        $value = Read-Host $Prompt
        if ($value -eq [string][char]27) {
            Write-Host 'Cancelled by user.'
            exit 0
        }
        return $value
    }

    Write-Host -NoNewline "${Prompt}: "
    $value = [Text.StringBuilder]::new()
    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Escape' {
                Write-Host ''
                Write-Host 'Cancelled by user.' -ForegroundColor Yellow
                exit 0
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

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Stop-WithError 'OpenSSH Client was not found. Install the Windows OpenSSH Client feature.'
}

$gateway = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1 -ExpandProperty NextHop
if (-not $gateway) {
    $gateway = '192.168.1.1'
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' NikkiGo - Nikki installer for OpenWrt' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'You will answer four simple questions.'
Write-Host 'A value in [brackets] is the default. Press Enter to use it.'
Write-Host ''

Write-Host '[Step 1 of 4] Router address' -ForegroundColor Yellow
Write-Host "NikkiGo found your router at $gateway."
$router = Read-NikkiInput "Press Enter to use $gateway, or type another address"
if ([string]::IsNullOrWhiteSpace($router)) { $router = $gateway }

Write-Host ''
Write-Host '[Step 2 of 4] Router login' -ForegroundColor Yellow
Write-Host 'On most OpenWrt routers the login is root.'
$sshUser = Read-NikkiInput 'Press Enter to use root, or type another login'
if ([string]::IsNullOrWhiteSpace($sshUser)) { $sshUser = 'root' }

Write-Host ''
Write-Host '[Step 3 of 4] SSH port' -ForegroundColor Yellow
Write-Host 'On most routers the SSH port is 22.'
$sshPort = Read-NikkiInput 'Press Enter to use 22, or type another port'
if ([string]::IsNullOrWhiteSpace($sshPort)) { $sshPort = '22' }
if ($sshPort -notmatch '^\d{1,5}$' -or [int]$sshPort -gt 65535) {
    Stop-WithError 'Invalid SSH port.'
}

Write-Host ''
Write-Host '[Step 4 of 4] Subscription' -ForegroundColor Yellow
Write-Host 'Paste the complete subscription URL and press Enter.'
$subscription = Read-NikkiInput 'Subscription URL'
if ($subscription -notmatch '^https?://') {
    Stop-WithError 'The URL must start with http:// or https://.'
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
Write-Host ' NEXT: SSH login' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "NikkiGo will now connect to $sshUser@$router."
Write-Host ''
Write-Host 'If SSH asks whether you trust the host:' -ForegroundColor Yellow
Write-Host '  Type yes and press Enter.'
Write-Host ''
Write-Host "When you see: $sshUser@$router's password:" -ForegroundColor Yellow
Write-Host '  Type the ROUTER password and press Enter.'
Write-Host '  Nothing will appear while you type: no dots and no stars.'
Write-Host '  This is normal. The keyboard is still working.'
Write-Host ''
Write-Host 'Waiting for SSH...' -ForegroundColor Green
$payloadB64 | & ssh -T -p $sshPort "$sshUser@$router" "tr -d '\r\n' | base64 -d | ash"
$payloadB64 = $null
if ($LASTEXITCODE -ne 0) {
    Stop-WithError "Installation failed with exit code $LASTEXITCODE."
}

Write-Host ''
Write-Host 'SUCCESS: Nikki is configured and running.' -ForegroundColor Green
