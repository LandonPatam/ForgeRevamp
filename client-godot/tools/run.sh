#!/usr/bin/env bash
# Native Mac launcher; retain the PowerShell entry point on Windows Git Bash.
set -euo pipefail
if [[ "$(uname -s)" == Darwin ]]; then
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    exec python3 "$script_dir/run-macos.py" "$@"
fi
# Use Bash's own Windows-path conversion. A cygpath from Anaconda can have
# a different MSYS root than the Git Bash session running this script.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && builtin pwd -W)"
launcher="$script_dir/run.ps1"
exec powershell.exe -NoProfile -File "$launcher" "$@"
