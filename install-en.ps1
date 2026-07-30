$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$UpstreamUrl = 'https://github.com/lanetsky/nikkiopen'
$SupportBot = '@transib_service_gena_bot'
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
            throw [OperationCanceledException]::new('Cancelled by user.')
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
                throw [OperationCanceledException]::new('Cancelled by user.')
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

Write-Host 'WARNING: modifying router software is performed at your own risk.' -ForegroundColor Yellow
Write-Host 'NikkiGo is provided “as is”, without warranties.' -ForegroundColor Yellow
Write-Host 'Before continuing, make sure you have a backup and access to the router.'
$riskCode = Read-NikkiInput 'Enter 322 to acknowledge responsibility'
if ($riskCode -ne '322') {
    Write-Host 'Operation cancelled. No changes were made.' -ForegroundColor Yellow
    return
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
Write-Host ' NikkiGo - Taproom Nikki installer for OpenWrt' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'You will answer three simple questions before connecting.'
Write-Host 'A value in [brackets] is the default. Press Enter to use it.'
Write-Host "Taproom Nikki source: $UpstreamUrl"
Write-Host ''

Write-Host '[Step 1 of 3] Router address' -ForegroundColor Yellow
Write-Host "NikkiGo found your router at $gateway."
$router = Read-NikkiInput "Press Enter to use $gateway, or type another address"
if ([string]::IsNullOrWhiteSpace($router)) { $router = $gateway }
if (-not (Test-RouterAddress $router)) {
    Stop-WithError 'Invalid router address. Use an IPv4 address or a full host name.'
}

Write-Host ''
Write-Host '[Step 2 of 3] Router login' -ForegroundColor Yellow
Write-Host 'On most OpenWrt routers the login is root.'
$sshUser = Read-NikkiInput 'Press Enter to use root, or type another login'
if ([string]::IsNullOrWhiteSpace($sshUser)) { $sshUser = 'root' }

Write-Host ''
Write-Host '[Step 3 of 3] SSH port' -ForegroundColor Yellow
Write-Host 'On most routers the SSH port is 22.'
$sshPort = Read-NikkiInput 'Press Enter to use 22, or type another port'
if ([string]::IsNullOrWhiteSpace($sshPort)) { $sshPort = '22' }
if ($sshPort -notmatch '^\d{1,5}$' -or [int]$sshPort -gt 65535) {
    Stop-WithError 'Invalid SSH port.'
}

$routerB64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($router)
)
$baseUrlB64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($BaseUrl)
)

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
Write-Host 'After login, the router will offer install, update, or removal.' -ForegroundColor Cyan
Write-Host 'Waiting for SSH...' -ForegroundColor Green
$remoteCommand = @'
base_url=$(printf '%s' '__BASE_URL_B64__' | base64 -d) || exit 90
tmp="/tmp/nikkigo-$$.sh"
safety="/tmp/nikkigo-safety-$$.sh"
echo "[NikkiGo] SSH connection established. Downloading the maintenance script..."
if ! wget -O "$tmp" "$base_url/router-install.sh?nikkigo=$(date +%s)"; then
    echo "[NikkiGo] ERROR: failed to download router-install.sh" >&2
    rm -f "$tmp"
    exit 91
fi
if ! wget -O "$safety" "$base_url/router-safety.sh?nikkigo=$(date +%s)"; then
    echo "[NikkiGo] ERROR: failed to download the safety module" >&2
    rm -f "$tmp" "$safety"
    exit 91
fi
NIKKIGO_BASE_URL="$base_url" NIKKIGO_SAFETY_PATH="$safety" NIKKIGO_LANGUAGE='en' NIKKIGO_ROUTER_ADDRESS_B64='__ROUTER_B64__' ash "$tmp"
status=$?
rm -f "$tmp" "$safety"
exit "$status"
'@
$remoteCommand = $remoteCommand.Replace('__BASE_URL_B64__', $baseUrlB64)
$remoteCommand = $remoteCommand.Replace('__ROUTER_B64__', $routerB64)
& ssh -tt -p $sshPort "$sshUser@$router" $remoteCommand
$sshExitCode = $LASTEXITCODE
if ($sshExitCode -eq -1 -or $sshExitCode -eq 255) {
    Stop-WithError 'SSH was interrupted or could not connect. If you pressed Ctrl+C or Esc, setup was cancelled; otherwise check the address, SSH service, login, password, and router log.'
}
if ($sshExitCode -eq 90) {
    Stop-WithError 'The router could not decode the download address.'
}
if ($sshExitCode -eq 91) {
    Stop-WithError 'The router could not download the NikkiGo maintenance script. Check internet, DNS, and system time on the router.'
}
if ($sshExitCode -ne 0) {
    Stop-WithError "NikkiGo failed on the router with exit code $sshExitCode. See the detailed messages above."
}

Write-Host ''
Write-Host 'NikkiGo finished. Review the result above.' -ForegroundColor Green
