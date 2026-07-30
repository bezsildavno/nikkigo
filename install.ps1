& {
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SupportBot = '@transib_service_gena_bot'
$RepoOwner = if ($env:NIKKIGO_OWNER) { $env:NIKKIGO_OWNER } else { 'bezsildavno' }
$BaseUrl = if ($env:NIKKIGO_BASE_URL) {
    $env:NIKKIGO_BASE_URL.TrimEnd('/')
} else {
    "https://raw.githubusercontent.com/$RepoOwner/nikkigo/main"
}

$language = if ($env:NIKKIGO_LANG) {
    $env:NIKKIGO_LANG.ToLowerInvariant()
} else {
    (Get-UICulture).TwoLetterISOLanguageName.ToLowerInvariant()
}

$installerName = if ($language -eq 'ru') {
    'install-ru.ps1'
} else {
    'install-en.ps1'
}

try {
    $installer = (Invoke-WebRequest -UseBasicParsing "$BaseUrl/$installerName").Content
    $installer = $installer.TrimStart([char]0xFEFF)
    Invoke-Expression $installer
} catch {
    if ($_.Exception -is [OperationCanceledException]) {
        Write-Host 'NikkiGo cancelled by user.' -ForegroundColor Yellow
        return
    }
    [Console]::Error.WriteLine("NikkiGo failed: $($_.Exception.Message)")
    Write-Host "Telegram support: $SupportBot" -ForegroundColor Yellow
    return
}
}
