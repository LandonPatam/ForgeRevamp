param([switch]$Editor, [switch]$Check, [switch]$Capture, [switch]$Live, [switch]$Connect, [switch]$Decks, [switch]$Mock, [string]$Deck = '', [int]$Port = 7777)
$ErrorActionPreference = 'Stop'
$clientRoot = Split-Path -Parent $PSScriptRoot
if ($Decks) {
    if ($Check -or $Capture) {
        $libraryCheck = Join-Path $PSScriptRoot 'library-check.mjs'
        if ($Capture) { & node $libraryCheck --render } else { & node $libraryCheck }
        if ($LASTEXITCODE -ne 0) { throw 'Deck collection checks failed' }
        exit
    }
    $libraryPort = if ($PSBoundParameters.ContainsKey('Port')) { $Port } else { 7778 }
    & (Join-Path $PSScriptRoot 'library.ps1') -Port $libraryPort -Decks
    exit
}
if ($Live) {
    & (Join-Path $PSScriptRoot 'play.ps1') -Deck $Deck -Port $Port -Check:$Check
    exit
}
if (-not ($Editor -or $Check -or $Capture -or $Connect -or $Mock)) {
    $libraryPort = if ($PSBoundParameters.ContainsKey('Port')) { $Port } else { 7778 }
    & (Join-Path $PSScriptRoot 'library.ps1') -Port $libraryPort
    exit
}
$godotPath = Join-Path $clientRoot '..\.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if ($env:FORGE_GODOT_PATH) { $godotPath = $env:FORGE_GODOT_PATH }
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'Godot was not found. Set FORGE_GODOT_PATH to your Godot 4 executable.' }
$existingArtifacts = Join-Path $clientRoot 'artifacts'
if (Test-Path -LiteralPath $existingArtifacts) { New-Item -ItemType File -Path (Join-Path $existingArtifacts '.gdignore') -Force | Out-Null }
if ($Check) {
    $importOutput = & $godotPath --headless --path $clientRoot --editor --import --quit 2>&1
    $importExit = $LASTEXITCODE
    $importOutput | ForEach-Object { Write-Output $_ }
    if ($importExit -ne 0 -or ($importOutput -join "`n") -match 'SCRIPT ERROR:|ERROR:') { throw 'Godot import failed' }
    $smokeOutput = & $godotPath --headless --path $clientRoot --quit-after 900 -- --smoke 2>&1
    $smokeExit = $LASTEXITCODE
    $smokeOutput | ForEach-Object { Write-Output $_ }
    $smokeText = $smokeOutput -join "`n"
    if ($smokeExit -ne 0 -or $smokeText -match 'SCRIPT ERROR:|ERROR:' -or $smokeText -notmatch 'PASS: mock table smoke') { throw 'Godot smoke failed' }
} elseif ($Capture) {
    $artifactRoot = Join-Path $clientRoot 'artifacts'
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $artifactRoot '.gdignore') -Force | Out-Null
    $stdoutPath = Join-Path $artifactRoot 'visual.stdout.log'
    $stderrPath = Join-Path $artifactRoot 'visual.stderr.log'
    $captureArgument = '--visual-checks=' + $artifactRoot.Replace('\', '/')
    $captureProcess = Start-Process -FilePath $godotPath -ArgumentList @('--path', ('"' + $clientRoot + '"'), '--resolution', '1600x1000', '--position', '-20000,-20000', '--', ('"' + $captureArgument + '"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $null = $captureProcess.Handle
    if (-not $captureProcess.WaitForExit(60000)) {
        Stop-Process -Id $captureProcess.Id -Force
        throw 'Godot visual capture timed out'
    }
    $captureProcess.WaitForExit()
    $captureOutput = Get-Content -LiteralPath $stdoutPath -Raw
    Write-Output $captureOutput
    $captureErrors = Get-Content -LiteralPath $stderrPath -Raw
    if ($captureErrors) { Write-Output $captureErrors }
    if (($null -ne $captureProcess.ExitCode -and $captureProcess.ExitCode -ne 0) -or $captureErrors -match 'SCRIPT ERROR:|ERROR:' -or $captureOutput -notmatch 'PASS: rendered visual checks') { throw 'Godot visual capture failed' }
} elseif ($Editor) {
    Start-Process -FilePath $godotPath -ArgumentList @('--editor', '--path', ('"' + $clientRoot + '"')) -WindowStyle Normal
} else {
    $clientArguments = @('--path', ('"' + $clientRoot + '"'))
    if ($Mock) { $clientArguments += @('--', '--mock') }
    if ($Connect) { $clientArguments += @('--', ('--live=ws://127.0.0.1:' + $Port + '/ws')) }
    Start-Process -FilePath $godotPath -ArgumentList $clientArguments -WindowStyle Normal
}
