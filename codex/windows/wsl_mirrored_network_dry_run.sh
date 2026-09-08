#!/bin/bash
# WSLからWindows PowerShell上のmirrored-networking dry-runを起動する。
set -euo pipefail

SCRIPT_IN_WSL="/home/developer/ghost/codex/windows/wsl_mirrored_network_setup.ps1"

echo "[1/2] Copying the setup script to the Windows temporary directory..."
echo "[2/2] Running the read-only check in Windows PowerShell..."

power_shell_command='$localScript = Join-Path $env:TEMP "wsl_mirrored_network_setup.ps1"; '
power_shell_command+="wsl.exe -d Ubuntu --exec cat $SCRIPT_IN_WSL | Set-Content -Encoding UTF8 \$localScript; "
power_shell_command+='if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; '
power_shell_command+='& $localScript 2222 -DryRun; exit $LASTEXITCODE'

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$power_shell_command"

echo "Done. No settings were changed."
