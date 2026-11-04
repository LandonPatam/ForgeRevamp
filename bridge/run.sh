#!/bin/sh
# Start the bridge (run `mvn package` first). Extra args are passed through, e.g. --deck "Sauron"
cd "$(dirname "$0")"
exec java -Xmx4g -cp "target/classes;target/lib/*" forgeui.bridge.BridgeMain --assets ../forge/forge-gui "$@"
