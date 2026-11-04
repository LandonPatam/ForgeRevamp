#!/usr/bin/env bash
# Windows Git Bash / Anaconda Bash entry point; use the same launcher as PowerShell.
set -euo pipefail
# Use Bash's own Windows-path conversion. A cygpath from Anaconda can have
# a different MSYS root than the Git Bash session running this script.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && builtin pwd -W)"
launcher="$script_dir/run.ps1"
exec powershell.exe -NoProfile -File "$launcher" "$@"
