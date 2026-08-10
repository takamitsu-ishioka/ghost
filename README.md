English | [日本語](./README.ja.md)

# Ghost

**Even when the person isn't there, the ghost is.**

Ghost is a concept-and-implementation repository for treating people, AI, knowledge, and work sessions as addressable "agents" on a LAN. See [`idea.md`](./idea.md) for the full story of how the idea developed.

## What is this system for?

The Claude Code UI is, at its core, "a program that keeps receiving key events from stdin and emitting terminal control strings (ANSI/VT escapes) to stdout." Starting from that fact, the idea develops as follows:

1. **Extend the PTY.** — If you carry the PTY itself over the LAN via tmux + SSH, you can connect to Claude Code's interactive UI, in full, from another machine.

2. **Connect to a knowledge space.**
      ```
      $ claude-join <ghost-knowledge-space-name>
      ```
      This command connects you to a "ghost (knowledge space)" made up of:
      - a specific repository
      - the session logs of that repository's developer and their agents
      - the developer's design philosophy
      - the developer's implementation rules

      With a ghost, you can query someone even while they're on vacation, in a meeting, or after they've left the company.

3. **AI interviews AI.**
   For the PM to grasp status, the PM's agent interviews each member's ghost and aggregates progress and blockers — no human reporting required.

The name that captures this in one word is **Ghost** (from *Ghost in the Shell*).

```text
ghost           the whole system
ghost ls        find a Ghost
ghost join      connect to a Ghost
ghost publish   publish your own Ghost
ghost ask       query a Ghost
ghost interview interview a Ghost
```

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

This isn't just a concept — `idea.md` includes, at the end, real examples of the AI cross-checking memory (past conversations and decisions) against the implementation (files and git state, i.e. the SSoT) before answering.

- Integrating short-term memory with a long-term routine (`images/recall-schedule.png`)
- Re-verifying instead of just replaying memory, via grep/shell (`images/recall-investigation.png`)
- Reconstructing design intent and rationale from git history alone, with no conversation history (`images/repo-design-intent.png`)

## CLAUDE.md (the source for "Core Premises" and DJC)

The annotations in `idea.md` such as "Core Premise 1" and "Core Premise 3 - DJC" link to [`CLAUDE.md`](./CLAUDE.md) at the root of this repository. It's a real copy of the developer's global `~/.claude/CLAUDE.en.md` (the English translation of `~/.claude/CLAUDE.md`), synced from `_CLAUDE.en.md` (a symlink to that file, `.gitignore`d) via [`claude_md_sync.sh`](./claude_md_sync.sh). The Japanese original is likewise tracked as [`CLAUDE.ja.md`](./CLAUDE.ja.md), synced from `_CLAUDE.md`. Since git pushes a symlink as a symlink rather than its target's content, what actually ships in the repository is the synced copy, not the link itself.

## Usage

The `ghost` CLI lives in [`bin/`](./bin). So far it implements the two commands the whole idea depends on — sharing a live Claude Code session over the LAN via tmux + SSH:

```bash
# on the machine running Claude Code
$ bin/ghost publish work
# → tmux new-session -A -s work claude

# from another machine on the LAN
$ bin/ghost join dev-yamada work
# → ssh -t dev-yamada tmux attach -t work
```

Run `bin/ghost` with no arguments to see the available subcommands.

## Current status

`ghost publish` / `ghost join` (the tmux + SSH PTY-sharing primitive) are implemented. `ghost ls` (LAN discovery), `ghost ask` / `ghost interview` (persistent knowledge spaces) are not yet implemented — see `idea.md` / `idea.ja.md` for the design discussion behind them.
