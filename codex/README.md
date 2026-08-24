# Control a LAN-local Codex session from Android

This directory contains the isolated implementation produced by Codex for the Android-to-Codex remote-control TODO.

The connection path is:

```text
Android / Termux
    -> SSH with a device key over the private LAN
Windows OpenSSH Server
    -> wsl.exe
WSL2 / tmux / Codex CLI
```

Use [README.ja.md](README.ja.md) as the primary procedure. The scripts automate Android key and command creation, Windows OpenSSH setup, local diagnostics, and tmux/Codex session attachment. Administrator approval, transferring the Android public key, checking the host fingerprint, and confirming that the router does not expose TCP port 22 remain manual safety boundaries.
