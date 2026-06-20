# crew

Run several Claude Code agents on related tasks — each in its own git worktree — and see at a
glance who's **blocked**, **working**, or **done**. Create a worktree in herdr and crew wires
it into a ready agent automatically; or spawn one explicitly with `crew new`.

crew is **thin glue**, not a framework. It stands on two excellent tools and adds only the
piece they don't — turning a new worktree into a wired, message-connected agent.

- **[herdr](https://herdr.dev)** — terminal multiplexer for AI agents. Owns the *worktree +
  panes + state* plane; the sidebar shows every agent color-coded (🔴 blocked / 🟡 working /
  🔵 done / 🟢 idle) with pane-count badges.
- **[agmsg](https://agmsg.cc)** — cross-agent messaging over a shared SQLite room. Owns the
  *messaging* plane; agents `send`/`inbox` by name, push-delivered in ~5 s.

```
                ┌───────────────────────── crew ─────────────────────────┐
                │   crew new <branch> "<task>"          crew bridge        │
                └──────────┬───────────────────────────────────┬─────────┘
                  spawn + register                       poll state → message
                           ▼                                     ▼
        ┌──────────── herdr ───────────┐            ┌────────── agmsg ──────────┐
        │ worktree create → workspace  │            │ join (1 agent / worktree)  │
        │ pane run "claude"            │            │ delivery set monitor       │
        │ sidebar state · pane list    │──poll──────│ send / inbox / team        │
        └──────────────────────────────┘  status    └────────────────────────────┘
        one worktree = one herdr workspace = one agmsg agent (the branch slug)
```

## Requirements

- [`herdr`](https://herdr.dev/docs/install/) (≥ 0.7) — `brew install herdr`
- [`agmsg`](https://github.com/fujibee/agmsg) (≥ 1.0.5) — `git clone … && ./install.sh`
- `git`, `jq`, `sqlite3`, `bash` (sqlite3 + git ship with macOS)

## Install

```sh
git clone https://github.com/<you>/crew.git
cd crew
./install.sh                       # links crew/-bridge/-watch + starts the watch service
herdr integration install claude   # one time: wires Claude state detection into herdr
```

`install.sh` registers **`crew watch`** as a login service (launchd on macOS, systemd
`--user` on Linux) so worktrees you create in herdr become wired agents automatically. Skip it
with `./install.sh --no-service`; remove it later with `crew watch service uninstall`. Set your
team name in `~/.config/crew/crew.conf` (see [`crew.conf.example`](crew.conf.example)).

## Use

The simple path — **make a worktree in herdr**:

> spaces panel → **menu → New worktree** → name it
> (or the keybinding `prefix+shift+g`, where `prefix` = `ctrl+b`)

`crew watch` adopts it within seconds: its own agmsg identity, push-delivered messages, a
sidebar status, and a running `claude`. Nothing else to do.

Prefer the CLI? `crew new` does the same in one step and lets you attach a task label:

```sh
crew new api-layer "draft the REST handlers"
```

Either way: **one worktree = one herdr workspace = one agmsg agent**. Run `herdr` to watch and
attach to everyone.

Good to know:

- The plain **"new"** button makes a workspace on the *main* checkout — that can't be its own
  agent, so crew skips it and nudges you toward *New worktree*.
- A fresh agent ignores its very first message until it has taken one turn — send it a quick
  `hi` to prime it (an agmsg behavior, not a crew bug).
- If herdr opens panes already running `claude`, that agent may need one restart to receive
  *pushed* messages; when herdr opens a shell (the default), there's no such gap.

## How you do the rest (native commands)

crew deliberately does **not** re-wrap these — use the tools directly:

| You want… | Do this |
|-----------|---------|
| See who's blocked / working / done | the **herdr sidebar**, or `herdr agent list` |
| See the team roster | `~/.agents/skills/agmsg/scripts/team.sh <team>` (or `/agmsg team` inside an agent) |
| Send a message between agents | `/agmsg send <agent> <message>` (inside a Claude pane) |
| Check an inbox | `/agmsg` (inside a Claude pane) |
| Retire an agent | `herdr worktree remove --workspace <id>` then `…/agmsg/scripts/leave.sh <team> <name>` |

## The bridge

`crew bridge` polls `herdr pane list` and, when a crew agent transitions into a state listed in
`BRIDGE_TRANSITIONS` (default `blocked done`), sends a one-line note to every other crew agent
on the team — e.g. `api-layer → blocked (needs input)`. (herdr reports a finished-but-unviewed
agent as `done`, which is why that — not `idle` — is the default "free now" signal.) `crew new`
and `crew watch` start it in the background (singleton via a pidfile under
`~/.local/state/crew`); run it yourself with `crew bridge`, logs at
`~/.local/state/crew/bridge.log`.

## How identity stays stable per worktree

agmsg keys an agent identity on `(project_path, type)`. crew registers each agent under its
**worktree checkout path** (with `AGMSG_RESOLVE_PROJECT=0`, so agmsg stores the raw path
instead of collapsing the worktree back to the main repo root). The same checkout path is
baked into that worktree's monitor `SessionStart` hook, so the running Claude resolves to
exactly one identity — no `actas` disambiguation needed.

## Roadmap

- `crew status` — a single joined herdr + agmsg view.
- `crew msg` / `crew retire` — convenience wrappers (native commands work today).
- A `/crew` Claude Code skill to spawn/coordinate from inside an agent.
- **Event-driven watch + bridge** — `crew watch` ships the polling version today; replace the
  poll with herdr's `events.subscribe` (`worktree.*` / `pane.agent_status_changed`) socket
  stream once it's wired per-pane.
- **Remote** — herdr `--remote ssh://host` for herding agents on a remote box, with the
  agmsg room on that host.

## License

[MIT](LICENSE).
