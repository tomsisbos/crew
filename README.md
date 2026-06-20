# crew

Run several Claude Code agents on separate-but-related tasks — each in its own git
worktree — with one command to launch them and near-real-time awareness of who is
**blocked**, **working**, or **done**.

crew is **thin glue**, not a framework. It stands on two excellent tools and adds only
the piece they don't: a single spawn-and-wire command, plus a small state→message bridge.

- **[herdr](https://herdr.dev)** — terminal multiplexer for AI agents. Owns the *worktree +
  panes + state* plane. `herdr worktree create` makes a git worktree **and** opens it as a
  workspace; the sidebar shows every agent color-coded (🔴 blocked / 🟡 working / 🔵 done /
  🟢 idle) with pane-count badges.
- **[agmsg](https://agmsg.cc)** — cross-agent messaging over a shared SQLite room. Owns the
  *messaging* plane. Agents `send`/`inbox` by name; monitor mode push-delivers in ~5 s.

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
./install.sh                 # symlinks crew/-bridge/-watch + registers the watch service
herdr integration install claude   # one time: wires Claude state detection into herdr
```

`install.sh` also registers **`crew watch`** as a login service (launchd on macOS, systemd
`--user` on Linux) so any worktree you create in herdr becomes a wired agent automatically —
see [Auto-adopt from the herdr UI](#auto-adopt-from-the-herdr-ui-crew-watch). Skip it with
`./install.sh --no-service` (or `CREW_NO_SERVICE=1`); remove it later with
`crew watch service uninstall`.

Edit `~/.config/crew/crew.conf` to set your team name (defaults shown in
[`crew.conf.example`](crew.conf.example)).

## Use

From inside any git repository:

```sh
crew new api-layer "draft the REST handlers"
crew new db-schema "migration + models"
```

Each call:

1. `herdr worktree create` — new git worktree + workspace (under `~/.herdr/worktrees/…`).
2. `agmsg join` — registers the worktree as a team member named after the branch.
3. `agmsg delivery set monitor` — installs ~5 s push delivery into that worktree.
4. sets the herdr custom-status to your task description.
5. launches `claude` in the pane.
6. ensures the bridge is running.

Then just `herdr` to see and attach to everyone.

> First-message priming: in monitor mode a fresh agent won't react to its very first
> inbound message until it has taken one turn. If an agent seems silent, send it a quick
> `hi` to prime it (this is an agmsg behavior, not a crew bug).

## Auto-adopt from the herdr UI (`crew watch`)

`crew new` is the explicit path. But you can also create worktrees straight from herdr and
have crew wire them for you — `crew watch` polls herdr and adopts any **linked worktree** it
hasn't seen, running the exact same steps 2–6 above (join → delivery → status → registry →
launch claude → ensure bridge). This decouples *spawning an agent* from *how the worktree was
made*: the herdr menu button, the keybinding, the palette, or `herdr worktree create` on the
CLI all end up as fully-wired agents.

```
in herdr:  spaces panel → "menu" → New worktree → <branch>
           (or the new-worktree keybinding: prefix+shift+g, where prefix = ctrl+b)
                                   │  ~WATCH_INTERVAL s later
                                   ▼
crew watch:  join · delivery set monitor · custom-status · registry · run "claude" · ensure bridge
```

- **It's automatic.** `install.sh` registers `crew watch` as a login service
  (`RunAtLoad` + `KeepAlive`), so it starts at login, restarts on crash, and survives closing
  and reopening herdr (it idle-polls while herdr is down and resumes when it's back). Nothing
  to remember. Run it in the foreground for debugging with `crew watch`; logs go to
  `~/.local/state/crew/watch.log`.
- **Only worktrees become agents.** The plain **"new"** button makes a workspace on the
  *main* checkout, which shares the repo path and so can't be a distinct agmsg identity. crew
  ignores it — and (unless `WATCH_NUDGE=0`) pops a herdr toast nudging you to use *New
  worktree* instead.
- **Caveat — monitor mode on auto-launched panes.** If your herdr opens new panes already
  running `claude` (rather than a shell), the agent may have started *before* crew wrote its
  delivery hook; crew primes it with a `hi`, but it can need one restart to enter monitor
  mode. When herdr opens a shell (the default) and crew launches `claude` itself, there's no
  race.

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

`crew bridge` polls `herdr pane list` and, when a crew agent transitions into a state
listed in `BRIDGE_TRANSITIONS` (default `blocked done`), sends a one-line note to every
other crew agent on the team — e.g. `api-layer → blocked (needs input)`. (herdr reports a
finished-but-unviewed agent as `done`, which is why that — not `idle` — is the default
"free now" signal.) `crew new` starts
it in the background (singleton via a pidfile under `~/.local/state/crew`). Run it in the
foreground yourself with `crew bridge`; logs go to `~/.local/state/crew/bridge.log`.

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
