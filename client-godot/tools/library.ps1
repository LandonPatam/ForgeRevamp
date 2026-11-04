param([ValidateRange(1,65535)][int]$Port = 7778, [switch]$Decks)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$bridgeRoot = Join-Path $projectRoot 'bridge'
$artifactRoot = Join-Path $projectRoot 'client-godot/artifacts'
$godotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64.exe'
if ($env:FORGE_GODOT_PATH) { $godotPath = $env:FORGE_GODOT_PATH }
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'Godot not found. Set FORGE_GODOT_PATH.' }
if (-not (Test-Path -LiteralPath (Join-Path $bridgeRoot 'target/classes/forgeui/bridge/LibraryMain.class'))) { throw 'Build first: .\bridge\tools\test.ps1' }
$probe = [Net.Sockets.TcpClient]::new()
try { $probe.Connect('127.0.0.1', $Port); $inUse = $true } catch { $inUse = $false } finally { $probe.Dispose() }
if ($inUse) { throw "Port $Port is in use. Choose another port with -Port." }
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $artifactRoot '.gdignore') -Force | Out-Null
$statusPath = Join-Path $artifactRoot ('startup-' + [Guid]::NewGuid().ToString('N') + '.json')
function Write-StartupStage([string]$Stage, [string]$Title, [string]$Detail) {
    $statusJson = @{ stage = $Stage; title = $Title; detail = $Detail } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($statusPath, $statusJson, [Text.UTF8Encoding]::new($false))
}
Write-StartupStage 'starting' 'Starting Forge' 'Preparing the game library. This can take a minute.'
$bridgeProcess = $null
$clientProcess = $null
try {
    # Show the client before Java initialization; it reads real milestones from this file.
    $clientArguments = @('--path', ('"' + (Join-Path $projectRoot 'client-godot') + '"'), 'res://scenes/Application.tscn', '--', ('--library-url=ws://127.0.0.1:' + $Port + '/ws'), ('"--startup-status=' + $statusPath + '"'))
    if ($Decks) { $clientArguments += '--open-decks' }
    $clientProcess = Start-Process -FilePath $godotPath -ArgumentList $clientArguments -WindowStyle Normal -PassThru
    $null = $clientProcess.Handle
    Write-Output 'Opening Forge. Startup progress is shown in the application window.'
    $javaProbe = [Diagnostics.Process]::new()
    $javaProbe.StartInfo = [Diagnostics.ProcessStartInfo]::new('java', '-XshowSettings:properties -version')
    $javaProbe.StartInfo.UseShellExecute = $false
    $javaProbe.StartInfo.CreateNoWindow = $true
    $javaProbe.StartInfo.RedirectStandardError = $true
    $null = $javaProbe.Start()
    $javaSettings = $javaProbe.StandardError.ReadToEnd()
    $javaProbe.WaitForExit()
    $javaProbe.Dispose()
    $javaHomeLine = ($javaSettings -split "`n" | Where-Object { "$_" -match '^\s*java.home = ' } | Select-Object -First 1)
    if (-not $javaHomeLine) { throw 'Java was not found.' }
    $javaHomePath = ("$javaHomeLine" -replace '^\s*java.home = ', '').Trim()
    $javaPath = Join-Path $javaHomePath 'bin/java.exe'
    $bridgeProcess = Start-Process -FilePath $javaPath -ArgumentList @('-Xmx4g', '-cp', '"target/classes;target/lib/*"', 'forgeui.bridge.LibraryMain', '--assets', '"../forge/forge-gui"', '--port', "$Port", '--startup-status', ('"' + $statusPath + '"')) -WorkingDirectory $bridgeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $artifactRoot 'collection-engine.stdout.log') -RedirectStandardError (Join-Path $artifactRoot 'collection-engine.stderr.log')
    $null = $bridgeProcess.Handle
    $startupDeadline = [DateTime]::UtcNow.AddSeconds(180)
    $libraryReady = $false
    while (-not $clientProcess.WaitForExit(250)) {
        if ($bridgeProcess.HasExited) { throw 'Forge exited. See client-godot/artifacts/collection-engine.stderr.log for details.' }
        if (-not $libraryReady) {
            $libraryReady = (Get-Content -LiteralPath (Join-Path $artifactRoot 'collection-engine.stdout.log') -Raw -ErrorAction SilentlyContinue) -match 'Library ready:'
            if (-not $libraryReady -and [DateTime]::UtcNow -ge $startupDeadline) { throw 'Forge startup timed out. Close the application and try again.' }
        }
    }
} catch {
    if (-not $clientProcess) { throw }
    if ($bridgeProcess -and -not $bridgeProcess.HasExited) { Stop-Process -Id $bridgeProcess.Id }
    Write-StartupStage 'failed' 'Forge could not start' $_.Exception.Message
    # Keep the error visible until the user closes the window.
    while (-not $clientProcess.WaitForExit(500)) {}
} finally {
    if ($clientProcess -and -not $clientProcess.HasExited) { Stop-Process -Id $clientProcess.Id }
    if ($bridgeProcess -and -not $bridgeProcess.HasExited) { Stop-Process -Id $bridgeProcess.Id }
}
