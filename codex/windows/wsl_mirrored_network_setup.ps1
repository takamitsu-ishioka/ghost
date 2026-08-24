# WSL2をmirrored networkingへ設定し、WSLのSSH専用ポートだけをHyper-V firewallで許可する。
# Windows OpenSSH Serverは構成せず、通信経路にも使用しない。反映のためのwsl --shutdownは人が実行する。
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateRange(1024, 65535)]
    [int]$SshPort,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$scriptName = Split-Path -Leaf $PSCommandPath
$wslConfigPath = Join-Path $HOME ".wslconfig"
$backupPath = "$wslConfigPath.ghost-codex.bak"
$hyperVRuleName = "ghost-codex-wsl-ssh"
$wslVmCreatorId = "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

[Console]::Error.WriteLine("[input]")
[Console]::Error.WriteLine("  SSH port:       $SshPort")
[Console]::Error.WriteLine("[output]")
[Console]::Error.WriteLine("  WSL config:     $wslConfigPath")
[Console]::Error.WriteLine("  networkingMode: mirrored")
[Console]::Error.WriteLine("  Hyper-V rule:   $hyperVRuleName / TCP $SshPort inbound")

if ($DryRun) {
    [Console]::Error.WriteLine("${scriptName}: -DryRun, not making changes")
    [Console]::Error.WriteLine("Next: open PowerShell as Administrator and run without -DryRun.")
    exit 0
}

if (-not $isAdministrator) {
    [Console]::Error.WriteLine("${scriptName}: Administrator privileges are required")
    [Console]::Error.WriteLine("Next: open PowerShell as Administrator and run this command again.")
    exit 1
}

$lines = @()
if (Test-Path -LiteralPath $wslConfigPath -PathType Leaf) {
    $lines = @(Get-Content -LiteralPath $wslConfigPath)
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $wslConfigPath -Destination $backupPath
    }
}

$result = [System.Collections.Generic.List[string]]::new()
$insideWsl2 = $false
$foundWsl2 = $false
$setNetworkingMode = $false

foreach ($line in $lines) {
    if ($line -match '^\s*\[([^]]+)\]\s*$') {
        if ($insideWsl2 -and -not $setNetworkingMode) {
            $result.Add("networkingMode=mirrored")
            $setNetworkingMode = $true
        }
        $insideWsl2 = ($Matches[1] -eq "wsl2")
        if ($insideWsl2) { $foundWsl2 = $true }
        $result.Add($line)
        continue
    }

    if ($insideWsl2 -and $line -match '^\s*networkingMode\s*=') {
        if (-not $setNetworkingMode) {
            $result.Add("networkingMode=mirrored")
            $setNetworkingMode = $true
        }
        continue
    }

    $result.Add($line)
}

if ($insideWsl2 -and -not $setNetworkingMode) {
    $result.Add("networkingMode=mirrored")
    $setNetworkingMode = $true
}

if (-not $foundWsl2) {
    if ($result.Count -gt 0 -and $result[$result.Count - 1] -ne "") { $result.Add("") }
    $result.Add("[wsl2]")
    $result.Add("networkingMode=mirrored")
}

Set-Content -LiteralPath $wslConfigPath -Value $result -Encoding ascii

$existingRule = Get-NetFirewallHyperVRule -Name $hyperVRuleName -ErrorAction SilentlyContinue
if ($existingRule) {
    Remove-NetFirewallHyperVRule -Name $hyperVRuleName
}
New-NetFirewallHyperVRule `
    -Name $hyperVRuleName `
    -DisplayName "Ghost Codex direct WSL SSH" `
    -Direction Inbound `
    -VMCreatorId $wslVmCreatorId `
    -Protocol TCP `
    -LocalPorts $SshPort | Out-Null

[Console]::Error.WriteLine("${scriptName}: setup complete")
[Console]::Error.WriteLine("Next: save work in every WSL distribution, run wsl --shutdown manually, then reopen Ubuntu.")
