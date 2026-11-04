$ErrorActionPreference = 'Stop'
$bridgeRoot = Split-Path -Parent $PSScriptRoot
$mavenPath = Join-Path $bridgeRoot '..\.tools\apache-maven-3.9.9\bin\mvn.cmd'
& $mavenPath -o -f (Join-Path $bridgeRoot 'pom.xml') -DskipTests package
if ($LASTEXITCODE -ne 0) { throw 'Bridge package failed' }
$testClasspath = (Join-Path $bridgeRoot 'target\test-classes') + ';' + (Join-Path $bridgeRoot 'target\classes') + ';' + (Join-Path $bridgeRoot 'target\lib\*')
& java -cp $testClasspath forgeui.bridge.BridgeChecks
if ($LASTEXITCODE -ne 0) { throw 'Bridge regression checks failed' }
