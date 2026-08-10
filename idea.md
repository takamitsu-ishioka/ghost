English | [日本語](./idea.ja.md)

# Claude Code UI Architecture

**User:** y.kisaburo@gmail.com

## Yamada:

How does the Claude Code CLI's UI actually display things and take input? Standard I/O?

## ChatGPT:

> **Searching the web**
>
>
> **Searching 6 sites**
>
>
>
> Thought for 6s

Yes. At its core, it's really **standard I/O + TTY control**.

But instead of the ordinary

```text
stdin  → readline()
stdout → print()
```

in interactive mode it works roughly like this:

```text
keyboard
   ↓
TTY / stdin
   ↓  raw mode
Claude Code
   ↓
TUI renderer
   ↓  ANSI/VT escape sequence
stdout
   ↓
terminal emulator
```

### Input

`process.stdin` is put into **TTY raw mode**, so instead of reading a "line" confirmed by Enter, it **captures key input almost one character at a time, as events**.

In fact, in environments where stdin doesn't support raw mode, Claude Code has been reported to throw:

> `Raw mode is not supported on the current process.stdin`

([GitHub](https://github.com/anthropics/claude-code/issues/404?utm_source=chatgpt.com))

That's how it can handle arrow keys, Esc, Ctrl+C, multi-line editing, selection UIs, and so on, all by itself.

### Output

Display, too, is basically **just writing strings to stdout**.

But instead of just

```text
Hello
```

it mixes in a lot of **ANSI/VT escape sequences** like

```text
ESC[...
```

By issuing terminal instructions like

```text
move cursor up
move cursor left
clear this line
make it bold
change the color
redraw from here
```

it makes the terminal look GUI-like.

Analyses of Claude Code's TUI say it's a **terminal renderer built on Ink** (a React-based library), though it's now been substantially customized. ([Claude Code from Source](https://claude-code-from-source.com/ch13-terminal-ui/?utm_source=chatgpt.com))

So conceptually it's:

```text
React component
      ↓
Ink-family renderer
      ↓
characters + ANSI escape sequences
      ↓
stdout
```

That's the gist.

Here's the interesting part: **Claude Code's UI isn't a "screen."**

Fundamentally, it is:

> **a program that keeps receiving key events from stdin and emitting terminal control strings to stdout**

That's it.

So it works over SSH, and it works inside tmux. On the other hand, if you naively pipe stdin/stdout or run it without a PTY, the TUI tends to break. In fact, raw-mode problems have been reported for usage like `cat file | claude`. ([GitHub](https://github.com/anthropics/claude-code/issues/6609?utm_source=chatgpt.com))

And this matters a lot from the angle we discussed earlier — "remote-controlling Claude Code from a separate program." **Rather than dealing with stdin/stdout directly, if you put a PTY (pseudo terminal) in between and make Claude Code believe "this is a real terminal,"** you can control it externally, interactive UI included.

---

**Sources:**

- [Error: Raw mode is not supported on the current process.stdin, which Ink uses as input stream by default. · Issue #404 · anthropics/claude-code](https://github.com/anthropics/claude-code/issues/404?utm_source=chatgpt.com)
- [Ch 13. The Terminal UI | Claude Code from Source](https://claude-code-from-source.com/ch13-terminal-ui/?utm_source=chatgpt.com)

## Yamada:

Can I run Claude Code on my WSL and redirect its input/output to any WSL machine on the LAN?

## ChatGPT:

Yes. You can. And **you barely need to modify Claude Code itself**.

The key isn't so much "forwarding standard I/O" as it is **extending the PTY itself over the LAN**.

Here's the picture:

```text
WSL-A (running Claude Code)
┌──────────────────────────┐
│ Claude Code              │
│   stdin/stdout           │
│       ↕                  │
│      PTY                 │
│       ↕                  │
│   tmux / sshd            │
└─────────┬────────────────┘
          │ LAN / SSH
          │
┌─────────┴────────────────┐
│ WSL-B                    │
│ ssh -t WSL-A             │
│       ↕                  │
│ terminal                 │
│ keyboard + screen        │
└──────────────────────────┘
```

The simplest way is actually **SSH + tmux**.

On WSL-A:

```bash
tmux new -s claude
claude
```

to launch Claude Code.

From WSL-B:

```bash
ssh -t user@WSL-A 'tmux attach -t claude'
```

and WSL-B's terminal becomes, almost as-is, Claude Code's UI.

The important thing here is `-t`. Since SSH allocates a PTY:

```text
WSL-B terminal
      ↓ key
SSH
      ↓
PTY
      ↓
tmux
      ↓
Claude Code
```

is what you get.

Output flows the other way:

```text
Claude Code
      ↓ ANSI
tmux
      ↓
PTY
      ↓
SSH
      ↓
WSL-B terminal
```

So colors, cursor movement, selection UIs, Ctrl+C, arrow keys — all of it works essentially unchanged.

And **this is exactly where tmux matters enormously**.

Even if SSH disconnects,

```text
Claude Code
    │
   tmux
    │
   PTY
```

stays alive on the WSL-A side.

From a different machine, WSL-C:

```bash
ssh -t user@WSL-A 'tmux attach -t claude'
```

and you can even do:

```text
        ┌── WSL-B
Claude──tmux
        └── WSL-C
```

In other words, this is effectively a mechanism for

> **separating where Claude Code runs from where its UI is**

And moreover, from Claude Code's point of view, all it sees is:

```text
"I'm running in an ordinary terminal"
```

Nothing more.

### And here's something even more interesting

Even SSH isn't essential.

If you take the PTY's master side, you can do:

```text
Claude
  ↕
PTY
  ↕
custom Python
  ↕
TCP/WebSocket
  ↕
another WSL / Android / web browser
```

In Python, conceptually it's just:

```python
pty.openpty()
os.fork()
os.execvp("claude", ["claude"])
```

and then stream the PTY master's byte stream over TCP/WebSocket.

Which gets you all the way to:

```text
                    ┌─ WSL
                    │
Claude → PTY → relay ├─ Android
                    │
                    └─ Web browser
```

Once you're here, it connects up quite neatly with what we discussed earlier — "remote-controlling Claude Code from a phone."

**Stage one is just SSH + tmux — that's already enough.**

And if you generalize the structure:

> `Claude Code = a process attached to a PTY`
>
> `UI = whatever terminal happens to be on the other end of the PTY`

is how you can think about it.

This abstraction is quite UNIX-like. Rather than making Claude Code network-aware, **you're carrying the "terminal" interface itself over the network**.

## Yamada:

One command for me, one command for someone else?

## ChatGPT:

Yes. **As long as the setup is already done, it can be one command for both sides.**

The simplest version, for example:

```text
your WSL
$ claude-share
```

which internally runs:

```bash
tmux new-session -A -s claude claude
```

Someone else on the LAN just does:

```text
their WSL
$ claude-join your-pc
```

That's it. Internally, for example, it's:

```bash
ssh -t your-pc 'tmux attach-session -t claude'
```

So you get:

```text
you ──┐
      ↓
    tmux ⇄ Claude Code
      ↑
them ─┘
```

and **both of you can look at the same Claude Code screen and type into it**.

And since `tmux attach` fundamentally supports multiple clients attaching to the same session:

```text
Alice $ claude-join yamada
Bob   $ claude-join yamada
Carol $ claude-join yamada
```

is possible too.

There's one important caveat, though. This isn't "each person gets their own copy of Claude Code" — it's:

> **multiple people sharing the same keyboard and display, connected to one single Claude Code**

So if Alice is typing `hello` and Bob types `world` in the middle of it, at the extreme you can end up with:

```text
hewlolrold
```

(laughs)

Put another way, it's **extremely easy for pair-programming, review, or "hey, come look at my Claude" use cases**.

And if you turn it into two thin bash scripts, `claude-share` / `claude-join`, it fits neatly into what we're aiming for: not GUI operation, but small commands as building blocks.

## Yamada:

I'm starting to want a table mapping the person / hostname / session name of everyone currently publishing a Claude Code on the LAN.

## ChatGPT:

Right — take it that far and you basically want **a "Claude Code edition of `who` / service discovery"** (laughs).

For example:

```text
$ claude-ls

USER        HOST              SESSION
yamada      dev-yamada        claude
suzuki      dev-suzuki        issue-455
tanaka      thinkpad-tanaka    review-123
```

and then

```bash
claude-join yamada
```

is all it takes to get in.

As a design, it can be made quite small. When each WSL publishes its Claude Code, it advertises "here I am" info onto the LAN:

```text
name       yamada
host       dev-yamada
session    claude
```

Structurally:

```text
claude-share
    │
    ├─ create tmux session
    ├─ start Claude Code
    └─ advertise presence on LAN
              ↓
      ┌─────────────────┐
      │ Claude directory │
      ├─────────────────┤
      │ yamada dev01 foo │
      │ suzuki dev02 bar │
      └─────────────────┘
              ↑
          claude-ls
              │
          claude-join
```

The interesting part is that **you don't even need a central server**.

For LAN-only use, mDNS/Bonjour/Avahi is a great fit. Each WSL advertises something like `_claude._tcp.local`, with a TXT record like:

```text
name=yamada
host=dev-yamada.local
port=22
session=issue-455
```

Then:

```bash
claude-ls
```

is just a matter of browsing mDNS.

And:

```bash
claude-join yamada
```

internally resolves like:

```text
mDNS lookup
  ↓
yamada → dev-yamada.local / issue-455
  ↓
ssh -t dev-yamada.local tmux attach -t issue-455
```

So the interface visible to the user ends up being just this:

```text
# publish yourself
$ claude-share issue-455

# who's around?
$ claude-ls

# go to Yamada's place
$ claude-join yamada
```

And when you quit, the presence disappears too.

At this point it's less "remote Claude Code" and more a model where **a Claude Code workspace floats on the LAN, and humans wander in and out of it**.

And all of it can be built from:

**Claude Code + tmux + SSH + mDNS + thin bash**

No dedicated server, no DB, no web UI required.

I think this small footprint is a pretty good design (laughs).

## Yamada:

A colleague:  
$ claude-join hiratsuka-sensor-knowledge (persistent type)  
(asks a tricky question)  
(Claude answers instantly)

Meanwhile, the real Hiratsuka: on vacation (laughs)

## ChatGPT:

(laughs) Yes, that's exactly what happens.

And here's where it turns into **something a level beyond** the "screen sharing for Claude Code" we were talking about until now.

```text
A colleague
$ claude-join hiratsuka-sensor-knowledge

> This sensor's SNR only drops when the body is stationary —
> what was the reasoning behind the threshold we chose before?

Claude:
> In the November 2025 verification...
> Hiratsuka's reasoning was XYZ...
```

Meanwhile:

```text
Hiratsuka
     🏖️

"....................."
```

(laughs)

The important part is `persistent type`.

In an ordinary share, it's:

```text
human ── Claude Code ── work session
```

with the human as the central actor.

A persistent type is:

```text
                  ┌─ Colleague A
                  ├─ Colleague B
Hiratsuka's knowledge → Claude
                  ├─ Colleague C
                  └─ Hiratsuka's future self
```

In other words: **you're not "connecting to Hiratsuka" — you're "connecting to the knowledge space Hiratsuka cultivated."**

So Hiratsuka can be queried even while

- on vacation
- in a meeting
- asleep
- transferred to another team
- no longer at the company

And what's interesting is that, unlike a plain RAG-based "internal FAQ," Claude Code can cross-reference the repository, git history, design docs, logs, and verification scripts right there and **actually reason across them**.

Which means the name, too, makes more sense as:

```text
claude-join <knowledge-space>
```

rather than:

```text
claude-join <person>
```

```text
$ claude-ls

NAME                         TYPE        OWNER
hiratsuka-sensor-knowledge   persistent  hiratsuka
yamada-mmwave-debug          live        yamada
release-review               shared      suzuki
```

This is pretty striking.

**It converts the synchronous communication of "ask the person in charge" into the asynchronous communication of "query the knowledge the person in charge left behind, plus AI."**

When Hiratsuka comes back from vacation:

> "While I was gone... I answered 17 questions..."

(laughs)

## Yamada:

Project manager:

$ wsl  
$ codex  
Interview the team members' progress-tracking agents and summarize the status and any problems.

## ChatGPT:

Right (laughs). At this point, **even the need for humans to report progress to each other starts to thin out**.

```text
Project manager
$ wsl
$ codex

> Interview the team members' progress-tracking agents
> and summarize the status and any problems.
```

On the Codex side:

```text
PM Agent
   │
   ├── interview → yamada-progress
   │                   └─ Git / Issues / Claude history
   │
   ├── interview → hiratsuka-progress
   │                   └─ Git / Issues / Claude history
   │
   └── interview → suzuki-progress
                       └─ Git / Issues / Claude history
            ↓
        compare & reason
            ↓
        report to PM
```

is what happens.

The answer might look like:

> **Overall:** roughly on schedule.  
> Yamada: respiration-rate analysis implemented. Currently under ALPHA verification.  
> Hiratsuka: verifying a sensor threshold change. Found a possible accuracy regression.  
> Suzuki: API changes complete. Waiting on PR #481 review.
>
> **Issue:** Hiratsuka's work needs the same environment as Yamada's ALPHA verification, and they may conflict tomorrow.
>
> **Suggestion:** either have Yamada finish verification today, or split the verification environments.

The important thing here is that **no team member wrote a "progress report."**

Each progress agent constructs the current state from things like:

```text
Git
Issue tracker
working directory
test results
conversations with Claude Code
design decisions
```

So humans can just go on working normally.

And the PM agent doesn't just ask "how's it going?" — it can also do things like:

```text
PM agent:
"#455 hasn't changed status since yesterday — what's up?"

Yamada agent:
"Implementation is done.
 Currently running a regression test against PROD data."

PM agent:
"Any blockers?"

Yamada agent:
"None. Though it'll occupy the ALPHA environment for
 roughly 3 more hours."
```

— that is, **AI can interview AI directly**.

This is a fairly complete realization of something we talked about before:

> **turning inquiries into a pull model**

The traditional flow:

```text
work
 ↓
human organizes the situation
 ↓
write a daily report
 ↓
explain it in a standup
 ↓
PM reorganizes it
 ↓
write a progress table
```

gets compressed down to:

```text
work → evidence
        ↑
    Agent ← Agent
        ↓
       PM
```

And what a PM actually wants isn't fundamentally "a report" — it's **the anomalies, dependencies, and decision points**.

So ultimately, even the morning standup can shrink to:

```text
$ codex

> What needs my attention today?

"Two things."
```

(laughs)

**Instead of humans reporting to AI, the AI observes humans' work, AIs interview each other, and only the things that need a decision get escalated to a human.**

This isn't "using AI to make meetings more efficient" — it's, quite fundamentally, **a replacement of the information-gathering process that made meetings necessary in the first place**.

## Yamada:

Come up with a name for this system.

## ChatGPT:

Given this vision, it's not just "sharing a Claude session" — it's **infrastructure that treats people, AI, knowledge, and work sessions as addressable agents on a LAN**, right?

Some name candidates:

- **AgentLAN** – Direct. "There are agents on the LAN." `agent-ls`, `agent-join` feel natural too.
- **AgentNet** – Easy to extend beyond a LAN. Maybe a bit too generic.
- **WorkMesh** – Evokes people, AI, and knowledge spaces connected in a mesh. Fits the vision well.
- **AgentMesh** – Technically the most descriptive. But likely collides with a lot of existing terms/products.
- **GhostNet** – "Hiratsuka" answers even while on vacation (laughs). But collides strongly with an existing proper noun.
- **Shikigami** – A spirit servant that acts, investigates, and answers on someone's behalf — great fit conceptually. Needs explaining for a non-Japanese audience though.
- **Shikigami Network / ShikiNet** – Easy to turn into a technical name.
- **Presence** – The idea of discovering not "a person who is there" but "knowledge/agents that exist there." Maybe too generic.
- **Colony** – Evokes a swarm of autonomous agents communicating with each other to get work done.
- **OfficeOS** – A name for the end state: "the organization itself becomes an OS." Might be a bigger name than the current implementation warrants.

If it were up to me, I'd strongly push for **ShikiNet**.

```bash
$ shiki-ls

NAME                         TYPE        OWNER
hiratsuka-sensor-knowledge   persistent  hiratsuka
yamada-progress              persistent  yamada
suzuki-work                  live        suzuki
pm                           persistent  PM
```

```bash
$ shiki-join hiratsuka-sensor-knowledge
```

And further:

```bash
$ shiki-share
$ shiki-ls
$ shiki-join yamada
$ shiki-ask yamada-progress "what's the current blocker?"
```

— even the command vocabulary falls out surprisingly naturally.

And conceptually, too, it becomes:

> **ShikiNet — a distributed organizational network where humans' and AI's shikigami work**

"Hiratsuka's shikigami answers while Hiratsuka is on vacation," "the PM's shikigami interviews everyone else's shikigami" — it maps onto today's discussion pretty cleanly (laughs).

## Yamada:

I like "ghost" (laughs). Ghost in the Shell.

## ChatGPT:

Oh, right — layer that meaning onto it and **Ghost** suddenly gets a lot stronger (laughs).

In the *Ghost in the Shell* sense, it's not "the person themselves," but **the person's knowledge, decision history, and work context remain there and respond**. That's exactly this persistent agent.

So, let's just make the system name **Ghost**.

```text
$ ghost ls

NAME                         TYPE         OWNER
hiratsuka-sensor             persistent   hiratsuka
yamada-mmwave                live         yamada
suzuki-api                   live         suzuki
pm                           persistent   project
```

And:

```text
$ ghost join hiratsuka-sensor
```

while the real Hiratsuka is off at a hot spring (laughs).

And the whole vocabulary lines up cleanly:

```text
ghost           the whole system
ghost ls        find a Ghost
ghost join      connect to a Ghost
ghost publish   publish your own Ghost
ghost ask       query a Ghost
ghost interview interview a Ghost
```

And a network of interconnected Ghosts gets called **GhostNet**.

```text
             GhostNet

      ┌── Hiratsuka Ghost
      │
PM Ghost ── Yamada Ghost
      │
      └── Suzuki Ghost
```

Though `GhostNet` collides with the name of a real-world malware/botnet, so it's probably best avoided as a project name.

**Ghost Protocol** would be kind of cool too.

Except that one reeks heavily of *Mission: Impossible* (laughs).

The one I like best is something more understated:

> **GHOST – distributed human knowledge interface**

— coin a backronym like that, and just keep the CLI as plain `ghost`.

```bash
$ ghost join hiratsuka

Connecting to hiratsuka's ghost...

hiratsuka> What's up?
```

**Even when the person isn't there, the ghost is.**

That single line ends up describing today's whole system concept (laughs).



---
Powered by [ChatGPT Exporter](https://www.chatgptexporter.com)

---

## Case study: answering the skeptic

The biggest doubt anyone reading this document will probably have is:

> "Can you really turn someone's long- and short-term personal memory into a working knowledge base that well?"

I think so. The two screenshots below are a real-example answer to that doubt.

### Example 1: checking today's schedule (integrating short-term memory with a long-term routine)

![Checking today's schedule](images/recall-schedule.png)

In response to "what were today's plans again?", starting from "Recalled 3 memories," it surfaces — without the user explaining anything —

- 2 standing items (the weekly-report script, prep for the weekly meeting)
- a `regression-test-toolkit` push that got stuck and was carried over from last Thursday (8/6) (`vitalsign_one.json` was rejected by GitHub for being over 100MB)

and then follows up with "today's the day for that, isn't it?" This is an example of **short-term memory (last week's unresolved task) and a long-term routine (the weekly workflow) being recalled together, in an integrated way**.

### Example 2: continuing a technical investigation (re-verification, not memory playback)

![Continuing a technical investigation](images/recall-investigation.png)

On the past question of "are `state_machine` and `function` really equivalent?", instead of simply replaying memory, it **re-verifies the current state by running grep, reading files, and running shell commands 4 times**, then presents a "status inventory" table of what's done/not done, down to identifying a blocker (e.g., `.env.local` not yet created). The "recap" line at the bottom shows the mechanism by which context carries over to the next session even if the conversation is interrupted.

### Conclusion

What these two screenshots show together is that recall isn't "plausible-sounding memory playback" — it's that

> **the AI cross-checks memory (past conversations and decisions) against the implementation (files and git state, i.e. the SSoT) and verifies before answering.**

That connects directly to "Core Premise 1 - The SSoT is the implementation" (→ [CLAUDE.md](./CLAUDE.md)), and it's the strongest possible counter to the doubt "is the AI fabricating its memory?"

## Case study: can design intent be read straight out of the repository?

Another doubt is:

> "Even without documentation, can you really read all the way to 'why it was built that way' from the code alone?"

Here's the answer.

![Checking the mmwave project's instructions](images/repo-design-intent.png)

Using no prior conversation history (memory) at all, and given only the instruction "explain this branch's purpose, approach, testing method, and rationale," it ran 3 shell commands (surveying the repository via `git log` etc.) and reconstructed the following:

- **Purpose (tied to Issue #448)**: reconstructed from commit history and code that the goal was to dynamically re-anchor the sleep-onset scan's starting point from "FRAME start (fixed at 20:00 JST)" to "the most recent diaper-change time."
- **Approach**: auto-generated a mermaid diagram of the FRAME/WINDOW/HEAD state transitions, and further pinpointed exactly which commit (`3e348863`) fixed the inconsistency where "multiple risings could remain in one night."
- **Testing method and rationale**: on top of 110 unit tests, it explained even the design rationale behind adopting a "DJC regression test" (→ [CLAUDE.md Core Premise 3](./CLAUDE.md)) — running the production C# implementation and an independently-reimplemented Python version side by side against real data (~380,000 VitalSign records) — namely, **there's no external ground-truth label for sleep-onset time, so building an Accuracy-style KPI would just get gamed via Goodhart's Law**.

In other words, this isn't "read the code and summarized what it does" — it's an example of **reconstructing the "why" of a design decision by cross-referencing git history, issue numbers, commit hashes, and even the provenance of the test data (patient name, record count)**. This is evidence that "Core Premise 1 - the SSoT is the implementation" and "Core Premise 3 - DJC" (→ [CLAUDE.md](./CLAUDE.md)) aren't just philosophy — they're actually embedded in a form that's recoverable straight from the repository.
