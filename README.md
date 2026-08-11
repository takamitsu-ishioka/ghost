English | [日本語](./README.ja.md)

<img width="1280" height="670" alt="510" src="https://github.com/user-attachments/assets/c2376c36-0c1e-4ad5-a3f4-00cb0e79a627" />

# Ghost

**Even when the person isn't there, the ghost is.**

Ghost is a concept-and-implementation repository for treating people, AI, knowledge, and work sessions as addressable "agents" on a LAN. See [`docs/idea.md`](./docs/idea.md) for the full story of how the idea developed.

## What is this system for?

The Claude Code UI is, at its core, "a program that keeps receiving key events from stdin and emitting terminal control strings (ANSI/VT escapes) to stdout." Starting from that fact, the idea develops as follows:

1. **Extend the PTY.** — If you carry the PTY itself over the LAN via tmux + SSH, you can connect to Claude Code's interactive UI, in full, from another machine.

2. **Connect to a knowledge space.**
      ```
      $ ghost join <server-host> <session-name>
      ```
      This command connects you to a "ghost (knowledge space)" made up of:
      - a specific repository
      - the session logs of that repository's developer and their agents
      - the developer's design philosophy
      - the developer's implementation rules

      With a ghost, you can query someone even while they're on vacation, on a business trip, in a meeting, or after they've left the company.

3. **AI interviews AI.**
   For the PM to grasp status, the PM's agent interviews each member's ghost and aggregates progress and blockers — no human reporting required.

The name that captures this in one word is **Ghost** (from *Ghost in the Shell*).

Checked items are already implemented:

- [x] `ghost` — the whole system
- [x] `ghost ls` — find a Ghost
- [x] `ghost join` — connect to a Ghost
- [x] `ghost publish` — publish your own Ghost

A network of interconnected ghosts is called **GhostNet**.

```text
             GhostNet

      ┌── Hiratsuka Ghost
      │
PM Ghost ── Yamada Ghost
      │
      └── Suzuki Ghost
```

## Glossary

- **Ghost** — a knowledge/work space published via `ghost publish`, addressable as `<host> <session_name>`.
- **Ghost Server** — the host that runs `ghost publish` (owns the tmux session; the SSH server side of a join).
- **Ghost Client** — the side that runs `ghost join <ghost server hostname> <ghost server session name>` (the SSH client side).
- **GhostNet** — a network of Ghosts interconnected via publish/join.

## Answering "can it really do that?"

This isn't just a concept — `docs/idea.md` includes, at the end, real examples of the AI cross-checking memory (past conversations and decisions) against the implementation (files and git state, i.e. the SSoT) before answering.

- Integrating short-term memory with a long-term routine (`docs/images/recall-schedule.png`)
- Re-verifying instead of just replaying memory, via grep/shell (`docs/images/recall-investigation.png`)
- Reconstructing design intent and rationale from git history alone, with no conversation history (`docs/images/repo-design-intent.png`)

## CLAUDE.md (the source for "Core Premises" and DJC)

The annotations in `docs/idea.md` such as "Core Premise 1" and "Core Premise 3 - DJC" link to [`docs/CLAUDE.md`](./docs/CLAUDE.md). It's a real copy of the developer's global `~/.claude/CLAUDE.en.md` (the English translation of `~/.claude/CLAUDE.md`), synced from `docs/_CLAUDE.en.md` (a symlink to that file, `.gitignore`d) via [`tools/claude_md_sync.sh`](./tools/claude_md_sync.sh). The Japanese original is likewise tracked as [`docs/CLAUDE.ja.md`](./docs/CLAUDE.ja.md), synced from `docs/_CLAUDE.md`. Since git pushes a symlink as a symlink rather than its target's content, what actually ships in the repository is the synced copy, not the link itself.

## Usage

The `ghost` CLI lives in [`bin/`](./bin). Run `bin/ghost-initialize` once per machine to install the required apt packages, put `bin/` on your `PATH`, and generate a dedicated `~/.ssh/id_ed25519_ghost` keypair for passwordless `ghost join`.

Since GhostNet has no central registry, a Ghost Server's administrator has to be given the joining side's public key out-of-band (chat, email, ...) and register it themselves:

```bash
# on the Ghost Client (the joining side), after ghost-initialize:
$ cat ~/.ssh/id_ed25519_ghost.pub
# → send this line to the Ghost Server's administrator

# on the Ghost Server, once the key has been received
$ echo '<the public key line>' | ghost trust yamada
# → adds it to ~/.ssh/authorized_keys, skips if already trusted
```

Then sharing a live Claude Code session over the LAN via tmux + SSH. `ghost publish` also advertises the session on the LAN via mDNS (`_ghost._tcp`), tied to the tmux session's own lifetime — the advertisement disappears automatically once the session is killed:

```bash
# on the Ghost Server (the machine running Claude Code)
$ ghost publish work
# → creates (or attaches to) tmux session "work" running claude,
#   and advertises it as _ghost._tcp on the LAN

# anything after "--" is passed straight through to claude
$ ghost publish work -- --dangerously-skip-permissions

# from any machine on the LAN, find what's published
$ ghost ls
SESSION                  HOST
work                     dev-yamada.local

# on the Ghost Client, once trusted
$ ghost join dev-yamada.local work
# → ssh -i ~/.ssh/id_ed25519_ghost -t dev-yamada.local tmux attach -t work
```

Run `ghost` with no arguments to see the available subcommands.

## Known issues

The underlying principle: a Ghost Client's *intent* when pressing a key should match the Ghost Server's actual behavior. Two known gaps, not yet fixed:

- **Submit-key mismatch**: Claude Code's default submit key is Enter, but unless the *Ghost Server*'s `~/.tmux.conf` has
  ```
  set -s extended-keys on
  set -as terminal-features 'xterm*:extkeys'
  ```
  tmux collapses Enter and modified-Enter (Alt+Enter, Shift+Enter) into the same byte sequence, so a Ghost Client's "press Enter to submit" intent may not reach the shared `claude` process correctly. This is a server-side tmux setting, not something each client can fix locally.
- **Exit-key mismatch**: `ghost join` currently has no way to tell a Ghost Client what's actually running in the session (e.g., `claude` exits on Ctrl+D twice, `codex` exits on Ctrl+D once). `ghost publish` doesn't yet record or advertise which command it launched, so this isn't surfaced anywhere.

## Current status

`ghost initialize`, `ghost trust`, `ghost publish`, `ghost join`, and `ghost ls` (setup, the tmux + SSH PTY-sharing primitive, and mDNS-based LAN discovery) are implemented — see `docs/idea.md` / `docs/idea.ja.md` for the design discussion behind the project.
