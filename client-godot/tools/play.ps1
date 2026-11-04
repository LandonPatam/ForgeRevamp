param([string]$Deck = '', [ValidateRange(1,65535)][int]$Port = 7777, [switch]$Check)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$bridgeRoot = Join-Path $projectRoot 'bridge'
$artifactRoot = Join-Path $projectRoot 'client-godot/artifacts'
$godotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64.exe'
if ($env:FORGE_GODOT_PATH) { $godotPath = $env:FORGE_GODOT_PATH }
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'Godot not found. Set FORGE_GODOT_PATH.' }
if (-not (Test-Path -LiteralPath (Join-Path $bridgeRoot 'target/classes/forgeui/bridge/BridgeMain.class'))) { throw 'Build the bridge first: .\bridge\tools\test.ps1' }
$probe = [Net.Sockets.TcpClient]::new()
try { $probe.Connect('127.0.0.1', $Port); $inUse = $true } catch { $inUse = $false } finally { $probe.Dispose() }
if ($inUse) { throw "Port $Port is in use. Use run.ps1 -Connect to attach to an existing three-player bridge, or choose -Port." }
# Resolve the actual JVM, so cleanup owns it instead of an Oracle PATH shim.
$javaProbe = [Diagnostics.Process]::new()
$javaProbe.StartInfo = [Diagnostics.ProcessStartInfo]::new('java', '-XshowSettings:properties -version')
$javaProbe.StartInfo.UseShellExecute = $false
$javaProbe.StartInfo.CreateNoWindow = $true
$javaProbe.StartInfo.RedirectStandardError = $true
$null = $javaProbe.Start()
$javaSettings = $javaProbe.StandardError.ReadToEnd()
$javaProbe.WaitForExit()
$javaProbe.Dispose()
$javaHomeLine = $javaSettings -split "`n" | Where-Object { "$_" -match '^\s*java.home = ' } | Select-Object -First 1
if (-not $javaHomeLine) { throw 'Java was not found.' }
$javaHomePath = ("$javaHomeLine" -replace '^\s*java.home = ', '').Trim()
$javaPath = Join-Path $javaHomePath 'bin/java.exe'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $artifactRoot '.gdignore') -Force | Out-Null
$stdoutPath = Join-Path $artifactRoot 'engine.stdout.log'
$stderrPath = Join-Path $artifactRoot 'engine.stderr.log'
$bridgeArguments = @('-Xmx4g', '-cp', '"target/classes;target/lib/*"', 'forgeui.bridge.BridgeMain', '--assets', '"../forge/forge-gui"', '--opponents', '2', '--port', "$Port")
if ($Deck) {
    if ($Deck.Contains('"')) { throw 'Deck names containing double quotes are not supported by this launcher.' }
    $bridgeArguments += @('--deck', ('"' + $Deck + '"'))
}
if ($Check) { $bridgeArguments += @('--deck-file', '"../client-godot/tests/engine-commander.dck"') }
$bridgeProcess = $null
$clientProcess = $null
try {
    $bridgeProcess = Start-Process -FilePath $javaPath -ArgumentList $bridgeArguments -WorkingDirectory $bridgeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $null = $bridgeProcess.Handle
    Write-Output "Starting a new Commander game against two AIs. Engine log: $stdoutPath"
    $startupDeadline = [DateTime]::UtcNow.AddSeconds(90)
    do {
        if ($bridgeProcess.HasExited) { throw "Forge exited during startup. See $stderrPath" }
        if ((Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue) -match 'Bridge ready:') { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $startupDeadline)
    if ([DateTime]::UtcNow -ge $startupDeadline) { throw "Forge startup timed out. See $stdoutPath" }
    $clientArguments = @('--path', ('"' + (Join-Path $projectRoot 'client-godot') + '"'))
    if ($Check) { $clientArguments += '--headless' }
    $clientArguments += @('--', ('--live=ws://127.0.0.1:' + $Port + '/ws'))
    if ($Check) { $clientArguments += '--live-check' }
    $clientStdout = Join-Path $artifactRoot 'play.stdout.log'
    $clientStderr = Join-Path $artifactRoot 'play.stderr.log'
    $clientWindowStyle = 'Normal'
    if ($Check) { $clientWindowStyle = 'Hidden' }
    $clientProcess = Start-Process -FilePath $godotPath -ArgumentList $clientArguments -WindowStyle $clientWindowStyle -PassThru -RedirectStandardOutput $clientStdout -RedirectStandardError $clientStderr
    $null = $clientProcess.Handle
    Write-Output 'Close the Godot window to stop this match and its engine.'
    while (-not $clientProcess.WaitForExit(500)) {
        if ($bridgeProcess.HasExited) { Write-Warning "Forge exited. See $stderrPath"; break }
        if ($Check -and [DateTime]::UtcNow -gt $startupDeadline.AddSeconds(130)) { throw 'Godot live verification timed out' }
    }
    if ($Check) {
        $clientProcess.WaitForExit()
        $clientOutput = Get-Content -LiteralPath $clientStdout -Raw
        $clientErrors = Get-Content -LiteralPath $clientStderr -Raw
        Write-Output $clientOutput
        if ($clientErrors) { Write-Output $clientErrors }
        if ($clientProcess.ExitCode -ne 0 -or $clientErrors -match 'SCRIPT ERROR:|ERROR:' -or $clientOutput -notmatch 'PASS: Godot live integration') { throw 'Godot live verification failed' }
    }
} finally {
    if ($clientProcess -and -not $clientProcess.HasExited) { Stop-Process -Id $clientProcess.Id }
    if ($bridgeProcess -and -not $bridgeProcess.HasExited) { Stop-Process -Id $bridgeProcess.Id }
}
