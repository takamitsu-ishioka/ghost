# Windows OpenSSH Serverを導入・起動し、現在のWindowsユーザーにAndroidの公開鍵を登録する。
# 管理者PowerShellで実行する。既存の同一公開鍵は重複登録しない。
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$PublicKeyPath,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$scriptName = Split-Path -Leaf $PSCommandPath

function Show-Usage([string]$Message) {
    [Console]::Error.WriteLine("${scriptName}: $Message")
    [Console]::Error.WriteLine("usage: $scriptName <android_public_key_path> [-DryRun]")
    [Console]::Error.WriteLine("example: $scriptName `$HOME\Downloads\id_ed25519_ghost_codex.pub")
}

if (-not (Test-Path -LiteralPath $PublicKeyPath -PathType Leaf)) {
    Show-Usage "Public key file does not exist: $PublicKeyPath"
    exit 1
}

$keyLine = (Get-Content -LiteralPath $PublicKeyPath -Raw).Trim()
if ($keyLine -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\s+[A-Za-z0-9+/=]+(?:\s+.*)?$') {
    Show-Usage "Invalid SSH public key"
    exit 1
}
$keyMaterial = (($keyLine -split '\s+')[0..1] -join ' ')

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdministrator) {
    $authorizedKeys = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
} else {
    $authorizedKeys = Join-Path $HOME ".ssh\authorized_keys"
}

[Console]::Error.WriteLine("[input]")
[Console]::Error.WriteLine("  public key:      $PublicKeyPath")
[Console]::Error.WriteLine("  Windows user:    $env:USERNAME")
[Console]::Error.WriteLine("[output]")
[Console]::Error.WriteLine("  capability:      OpenSSH.Server~~~~0.0.1.0")
[Console]::Error.WriteLine("  service:         sshd (Automatic / Running)")
[Console]::Error.WriteLine("  firewall:        TCP 22 inbound")
[Console]::Error.WriteLine("  authorized_keys: $authorizedKeys")

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

$capability = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0"
if ($capability.State -ne "Installed") {
    Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" | Out-Null
}

Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

$builtInFirewallName = "OpenSSH-Server-In-TCP"
$firewallName = "ghost-codex-sshd-lan"
if (Get-NetFirewallRule -Name $builtInFirewallName -ErrorAction SilentlyContinue) {
    Disable-NetFirewallRule -Name $builtInFirewallName
}
if (-not (Get-NetFirewallRule -Name $firewallName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -Name $firewallName `
        -DisplayName "Ghost Codex SSH from private LAN" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 `
        -RemoteAddress LocalSubnet `
        -Profile Private | Out-Null
} else {
    Enable-NetFirewallRule -Name $firewallName
    Set-NetFirewallRule -Name $firewallName -Direction Inbound -Action Allow -Profile Private
    Get-NetFirewallRule -Name $firewallName | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress LocalSubnet
}

$authorizedDirectory = Split-Path -Parent $authorizedKeys
New-Item -ItemType Directory -Path $authorizedDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath $authorizedKeys)) {
    New-Item -ItemType File -Path $authorizedKeys -Force | Out-Null
}

$alreadyPresent = Select-String -LiteralPath $authorizedKeys -SimpleMatch $keyMaterial -Quiet
if (-not $alreadyPresent) {
    Add-Content -LiteralPath $authorizedKeys -Value $keyLine
}

& icacls.exe $authorizedKeys /inheritance:r /grant '*S-1-5-18:F' /grant '*S-1-5-32-544:F' | Out-Null
Restart-Service -Name sshd

[Console]::Error.WriteLine("${scriptName}: setup complete")
[Console]::Error.WriteLine("Next: find this PC's private IPv4 address with ipconfig, then test SSH from Android.")
