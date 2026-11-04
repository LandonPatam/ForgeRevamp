param([switch]$SkipBuild, [switch]$NoZip, [string]$OutName = 'ForgeUI')
# Builds a self-contained Windows folder (and zip) in dist/: ForgeUI.exe plus the Java runtime,
# bridge service and Forge data it starts itself. Needs the Godot 4.7.2 Windows export templates
# (Editor > Manage Export Templates) and a JDK 17 with jlink.
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$clientRoot = Join-Path $projectRoot 'client-godot'
$bridgeRoot = Join-Path $projectRoot 'bridge'
$out = [IO.Path]::GetFullPath((Join-Path $projectRoot "dist/$OutName"))
$godotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64.exe'
if ($env:FORGE_GODOT_PATH) { $godotPath = $env:FORGE_GODOT_PATH }
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'Godot not found. Set FORGE_GODOT_PATH.' }
$template = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $template)) { throw "Godot 4.7.2 export templates are missing: $template" }

if (-not $SkipBuild) {
    & (Join-Path $bridgeRoot 'tools/test.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Bridge build or checks failed' }
}

# Deleting the output under a running copy would break it part way through.
$running = @(Get-Process ForgeUI -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith([IO.Path]::GetFullPath($out), [StringComparison]::OrdinalIgnoreCase) })
if ($running.Count -gt 0) { throw "Close ForgeUI.exe first: it is running from $out" }

# Never replace a folder this script did not create, and never delete anything outside dist/.
$distRoot = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out -Force | Out-Null

# Game: one exe with the data pack embedded.
New-Item -ItemType File -Path (Join-Path $clientRoot 'artifacts/.gdignore') -Force | Out-Null
# The GUI Godot build detaches from the shell, so wait on it and read its log instead of its output.
$exportLog = Join-Path $out 'export.log'
$null = Start-Process -FilePath $godotPath -Wait -WindowStyle Hidden -ArgumentList @('--headless', '--path', ('"' + $clientRoot + '"'), '--editor', '--import', '--quit')
$null = Start-Process -FilePath $godotPath -Wait -WindowStyle Hidden -ArgumentList @('--headless', '--path', ('"' + $clientRoot + '"'), '--log-file', ('"' + $exportLog + '"'), '--export-release', '"Windows Desktop"', ('"' + (Join-Path $out 'ForgeUI.exe') + '"'))
if (-not (Test-Path -LiteralPath (Join-Path $out 'ForgeUI.exe'))) { Get-Content -LiteralPath $exportLog -Tail 20; throw 'Godot export failed' }
Remove-Item -LiteralPath $exportLog -Force

# Run the exported game itself: Main.gd only loads at match start, and export filters can drop what it needs.
$smokeLog = Join-Path $out 'smoke.log'
$smokeProcess = Start-Process -FilePath (Join-Path $out 'ForgeUI.exe') -PassThru -WindowStyle Hidden -ArgumentList @('--headless', '--log-file', ('"' + $smokeLog + '"'), '--', '--smoke')
if (-not $smokeProcess.WaitForExit(180000)) { Stop-Process -Id $smokeProcess.Id -Force; throw 'The exported game timed out in its smoke check' }
$smokeText = Get-Content -LiteralPath $smokeLog -Raw
if ($smokeText -match 'SCRIPT ERROR:|Parse Error:|Failed to load script' -or $smokeText -notmatch 'PASS: mock table smoke') { Write-Output ($smokeLog + ":`n" + $smokeText); throw 'The exported game failed its smoke check' }
Remove-Item -LiteralPath $smokeLog -Force

# Java runtime trimmed to what the bridge and Forge use.
$jdk = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { 'C:/Program Files/Java/jdk-17' }
if (-not (Test-Path -LiteralPath (Join-Path $jdk 'bin/jlink.exe'))) { throw 'A JDK 17 with jlink was not found. Set JAVA_HOME.' }
$modules = 'java.base,java.desktop,java.logging,java.management,java.naming,java.net.http,java.prefs,java.sql,java.xml,jdk.unsupported,jdk.crypto.ec,jdk.zipfs,jdk.localedata,jdk.charsets,jdk.management'
& (Join-Path $jdk 'bin/jlink.exe') --add-modules $modules --strip-debug --no-header-files --no-man-pages --compress=2 --output (Join-Path $out 'runtime')
if ($LASTEXITCODE -ne 0) { throw 'jlink failed' }

# Service: compiled bridge classes and libraries.
$service = Join-Path $out 'service'
New-Item -ItemType Directory -Path $service -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $bridgeRoot 'target/classes') -Destination (Join-Path $service 'classes') -Recurse
Copy-Item -LiteralPath (Join-Path $bridgeRoot 'target/lib') -Destination (Join-Path $service 'lib') -Recurse

# Forge rules and assets. Adventure mode data is not used by Commander.
$forgeGui = Join-Path $out 'forge-gui'
& robocopy (Join-Path $projectRoot 'forge/forge-gui/res') (Join-Path $forgeGui 'res') /E /XD adventure /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Copying Forge data failed' }

Set-Content -LiteralPath (Join-Path $out 'README.txt') -Encoding utf8 -Value @'
ForgeUI - Commander

Run ForgeUI.exe. The first start takes a minute while the card database loads.
Keep this folder together: ForgeUI.exe starts the Java service in runtime\ and service\ itself.

Online play: everyone needs the same copy of this folder. Windows Firewall asks about
"OpenJDK Platform binary" (runtime\bin\java.exe) the first time someone hosts; allow it.
Logs: %APPDATA%\Godot\app_userdata\ForgeUI - Commander prototype\service\service.log
'@

if (-not $NoZip) {
    $zip = Join-Path $distRoot 'ForgeUI-windows.zip'
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path $out -DestinationPath $zip -CompressionLevel Optimal
}
$global:LASTEXITCODE = 0 # robocopy reports 1 for a successful copy
'{0:N0} MB in {1}' -f ((Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), $out
