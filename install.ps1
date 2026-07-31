& {
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertFrom-NikkiGoBase64([string]$EncodedText) {
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($EncodedText))
}

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
        if ($language -eq 'ru') {
            Write-Host (ConvertFrom-NikkiGoBase64 'Tmlra2lHbyDQvtGC0LzQtdC90ZHQvSDQv9C+0LvRjNC30L7QstCw0YLQtdC70LXQvC4=') -ForegroundColor Yellow
        } else {
            Write-Host 'NikkiGo cancelled by user.' -ForegroundColor Yellow
        }
        return
    }

    if ($language -eq 'ru') {
        [Console]::Error.WriteLine(
            ((ConvertFrom-NikkiGoBase64 '0J7RiNC40LHQutCwIE5pa2tpR286IHswfQ==') -f $_.Exception.Message)
        )
        $remoteDetailsMarker = ConvertFrom-NikkiGoBase64 '0J/QvtC00YDQvtCx0L3QvtGB0YLQuCDQv9C+0LrQsNC30LDQvdGLINCy0YvRiNC1Lg=='
        if ($_.Exception.Message -like "*$remoteDetailsMarker*") {
            return
        }
        Write-Host (
            ConvertFrom-NikkiGoBase64 '0J7QsdGA0LDRgtC40YLQtdGB0Ywg0LIg0L/QvtC00LTQtdGA0LbQutGDINGB0LXRgNCy0LjRgdCwLCDRgyDQutC+0YLQvtGA0L7Qs9C+INCy0Ysg0L/QvtC70YPRh9C40LvQuCDRgdGB0YvQu9C60YMg0L/QvtC00L/QuNGB0LrQuC4='
        ) -ForegroundColor Yellow
        Write-Host (
            ConvertFrom-NikkiGoBase64 '0J/RgNC40YjQu9C40YLQtSDRgdC60YDQuNC90YjQvtGCINGN0YLQvtCz0L4g0L7QutC90LAg0L7RgiDQutC+0LzQsNC90LTRiyDQt9Cw0L/Rg9GB0LrQsCDQtNC+INC+0YjQuNCx0LrQuA=='
        ) -ForegroundColor Yellow
        Write-Host (
            ConvertFrom-NikkiGoBase64 '0LjQu9C4INGB0LrQvtC/0LjRgNGD0LnRgtC1INC4INC+0YLQv9GA0LDQstGM0YLQtSDQstC10YHRjCDRgtC10LrRgdGCINC60L7QvdGB0L7Qu9C4Lg=='
        ) -ForegroundColor Yellow
    } else {
        [Console]::Error.WriteLine("NikkiGo failed: $($_.Exception.Message)")
        if ($_.Exception.Message -like '*detailed messages above.*') {
            return
        }
        Write-Host 'Contact the subscription provider for support.' -ForegroundColor Yellow
        Write-Host 'Send a screenshot of this window from the launch command through the error,' -ForegroundColor Yellow
        Write-Host 'or copy and send the complete console text.' -ForegroundColor Yellow
    }
    return
}
}
