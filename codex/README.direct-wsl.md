# Option 3: Connect directly from Android to WSL2

This option removes Windows OpenSSH and `wsl.exe` from the SSH transport path. Android connects to the WSL2 `sshd` on TCP port 2222, then attaches directly to the tmux/Codex session.

Windows is still the host OS for the WSL2 VM. One host-side configuration step remains necessary: mirrored networking and a narrowly scoped Hyper-V firewall rule. See [README.direct-wsl.ja.md](README.direct-wsl.ja.md) for the primary procedure.
