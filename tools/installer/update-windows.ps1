# Bunny Beat Down: update to the newest release. Installed next to the game
# as update.ps1 by the Windows installer (tools/installer/windows.nsi), and
# run from "Update Bunny Beat Down" when you right-click the desktop icon (or
# from the Start menu). It asks GitHub for the latest release, and if it's
# newer than the one installed, downloads its installer, runs it quietly over
# this one (saves and settings are never touched) and starts the game.
#   update.ps1              check, update if there's something newer, play
#   update.ps1 -CheckOnly   just say whether there's something newer

param([switch]$CheckOnly)

$ErrorActionPreference = "Stop"
$Repo = "zconnor100-debug/bunny-beat-down"
$Asset = "BunnyBeatDown-Setup-windows-x86_64.exe"
$Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BunnyBeatDown"
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
try { $Host.UI.RawUI.WindowTitle = "Updating Bunny Beat Down" } catch {}

# versions as four numbers: 0.9.1 -> 0.9.1.0
function Version-Parts([string]$v) {
    $parts = @($v.Trim().TrimStart("v").Split(".") | Where-Object { $_ -ne "" } | ForEach-Object { [int]$_ })
    while ($parts.Count -lt 4) { $parts += 0 }
    return $parts
}
function Is-Newer([string]$a, [string]$b) {
    $x = Version-Parts $a
    $y = Version-Parts $b
    for ($i = 0; $i -lt 4; $i++) {
        if ($x[$i] -ne $y[$i]) { return $x[$i] -gt $y[$i] }
    }
    return $false
}
function Finish([string]$message, [int]$seconds = 5) {
    Write-Host ""
    Write-Host $message
    if (-not $CheckOnly) { Start-Sleep -Seconds $seconds }
}

try {
    $have = (Get-ItemProperty $Key -ErrorAction SilentlyContinue).DisplayVersion
    if (-not $have) { $have = "0" }
    Write-Host "Bunny Beat Down $have"
    Write-Host "Checking for a newer version..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ "User-Agent" = "BunnyBeatDown-updater" }
    if ($env:GH_TOKEN) { $headers["Authorization"] = "Bearer $env:GH_TOKEN" }   # (CI: not rate-limited)
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
    $latest = $release.tag_name.TrimStart("v")
    if (-not (Is-Newer $latest $have)) {
        Finish "You have the newest version ($have). Have fun!"
        exit 0
    }
    if ($CheckOnly) {
        Write-Host "Version $latest is out."
        exit 0
    }
    $url = ($release.assets | Where-Object { $_.name -eq $Asset } | Select-Object -First 1).browser_download_url
    if (-not $url) { throw "version $latest has no Windows installer yet; try again in a few minutes" }

    # the game can't be replaced while it's running
    while (Get-Process -Name "BunnyBeatDown" -ErrorAction SilentlyContinue) {
        Read-Host "Bunny Beat Down is running: close it, then press Enter to carry on" | Out-Null
    }

    $setup = Join-Path $env:TEMP "BunnyBeatDown-Setup-$latest.exe"
    Write-Host "Downloading version $latest..."
    try {
        Start-BitsTransfer -Source $url -Destination $setup -DisplayName "Bunny Beat Down $latest" -Description "Downloading the update"
    } catch {
        $ProgressPreference = "SilentlyContinue"   # (the progress bar makes this download crawl)
        Write-Host "(this takes a few minutes)"
        Invoke-WebRequest $url -OutFile $setup -UseBasicParsing -Headers @{ "User-Agent" = "BunnyBeatDown-updater" }
    }
    Write-Host "Installing..."
    $p = Start-Process -FilePath $setup -ArgumentList "/S" -PassThru -Wait
    Remove-Item $setup -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { throw "the installer stopped (code $($p.ExitCode))" }
    Write-Host "Updated to version $latest. Starting the game..."
    if ($env:BBD_TEST -ne "1") {   # (automated runs just check the install)
        Start-Process -FilePath (Join-Path $Dir "BunnyBeatDown.exe") -WorkingDirectory $Dir
        Start-Sleep -Seconds 2
    }
} catch {
    Finish "Couldn't update: $($_.Exception.Message)`nYou can always get the newest version from https://github.com/$Repo/releases/latest" 15
    exit 1
}
