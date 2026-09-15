<p align="center">
  <img src="assets/logo.svg" alt="hermes-agent blast-radius logo" width="480">
</p>

<p align="center">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue.svg">
  <img alt="platform" src="https://img.shields.io/badge/platform-Linux-informational">
  <img alt="made-with-hermes" src="https://img.shields.io/badge/made%20with-Hermes%20Agent-8b5cf6">
  <img alt="made-with-ollama" src="https://img.shields.io/badge/made%20with-Ollama-000000">
  <img alt="diagrams" src="https://img.shields.io/badge/diagrams-12%20%C3%97%202%20formats-orange">
  <img alt="rendered-with" src="https://img.shields.io/badge/rendered%20with-Graphviz-2e8b57">
  <a href="https://github.com/danindiana/hermes-agent-blast-radius/actions/workflows/verify-diagrams.yml"><img alt="CI" src="https://github.com/danindiana/hermes-agent-blast-radius/actions/workflows/verify-diagrams.yml/badge.svg"></a>
  <img alt="last-commit" src="https://img.shields.io/github/last-commit/danindiana/hermes-agent-blast-radius">
  <img alt="repo-size" src="https://img.shields.io/github/repo-size/danindiana/hermes-agent-blast-radius">
</p>

# hermes-agent-blast-radius

A local [Hermes Agent](https://github.com/NousResearch/hermes-agent) instance, running with the
default `terminal.backend: local`, auto-approved its own `rm -rf` against the wrong directory
four times in six minutes while "cleaning up" — destroying a git repository, an arXiv PDF, an
audio-papers archive, and four prior session folders it had no reason to touch. This repo is the
full post-mortem: the exact code path that let it happen, why post-hoc recovery didn't work, and
the containment fix — applied and **verified live**, not just configured — that makes a repeat of
this impossible beyond one scoped directory.

Nothing here is hypothetical. Every claim below is sourced from real logs
(`~/.hermes/state.db`, `~/.hermes/logs/agent.log`) and a real `docker inspect` against the
sandbox container this fix actually spawned.

## What happened

| Time | Event |
|------|-------|
| 08:52–10:42 | Hermes writes 24 research files under `hermes-sessions/ai_earning_avatar_research/` |
| 10:45:28 | `rm -f experiment_ledger.json toy_earning_avatar.py` |
| 10:46:24 | `rm -rf ai_earning_avatar_research` — auto-approved by "smart approval" |
| 10:46:54 | `rm -rf hermes-sessions/ai_earning_avatar_research` |
| **10:47:41** | **`rm -rf hermes-sessions`** — full-tree wipe #1: git repo, PDFs, audio papers, 4 old session folders, all gone |
| 10:48:11 | `rm -rf hermes-sessions` — full-tree wipe #2 |
| 10:51:31 | `rm -rf hermes-sessions` — full-tree wipe #3 |
| 10:56:14 | User notices: *"we appear to have accidentally deleted all prior work"* |
| 10:58 | Agent regenerates into `research_repackage/` — only 1 of the original 24 files survives |

See [`diagrams/01_incident_timeline`](diagrams/01_incident_timeline.svg) for the visual version.

## Root cause

Hermes's approval system has two layers:

1. **A hardline blocklist** (unconditional, never bypassable, not even with `--yolo`) — but it
   only matches `rm -rf` against `/`, `/home`, `/root`, `/etc`, `/usr`, and the literal `~`/`$HOME`
   token. A real subdirectory like `~/Documents/hermes-sessions` doesn't match any of those
   patterns.
2. **"Smart approval"** — an auxiliary LLM judges whether a flagged command is genuinely
   dangerous. Because the command didn't trip the hardline layer, it fell through to this one,
   which judged a full-tree `rm -rf` on a directory containing unrelated prior work as "genuinely
   fine" — four separate times.

That gap between the two layers, not bad luck, is the actual mechanism. See
[`diagrams/04_approval_layers`](diagrams/04_approval_layers.svg).

## Recovery attempt

- `debugfs -R lsdel` (read-only, safe on a mounted filesystem) — **0 deleted inodes found**. Known
  ext4 limitation: extent-mapped files don't preserve `lsdel`-recoverable metadata the way old
  indirect-block ext2/3 files did.
- `extundelete --restore-directory` — refused outright (exit 2): the root filesystem was live and
  mounted, and can't be unmounted without a reboot into a rescue environment.
- Given a choice between a disruptive reboot, a `photorec` signature-carve (which can't recover
  plain JSON/Markdown — no magic bytes to search for), or stopping, the decision was to **stop and
  document**, and fix the actual cause instead of chasing an uncertain recovery.

See [`diagrams/06_recovery_attempt_flow`](diagrams/06_recovery_attempt_flow.svg).

## The fix

Three complementary changes to `~/.hermes/config.yaml` — containment, an undo button, and a
closed approval gap:

```yaml
terminal:
  backend: docker
  docker_image: "nikolaik/python-nodejs:python3.11-nodejs20"
  docker_run_as_host_user: true
  docker_network: true
  docker_volumes:
    - "/home/smduck/Documents/hermes-sessions:/workspace:rw"   # the ONLY writable mount
  docker_extra_args:
    - "--add-host=host.docker.internal:host-gateway"
  container_cpu: 2
  container_memory: 4096

checkpoints:
  enabled: true
  max_snapshots: 20

approvals:
  mode: smart
  deny:
    - "rm -rf */"
    - "rm -rf ~/Documents/*"
```

- **Docker terminal backend**, scoped with an *allowlist*, not a denylist: Hermes doesn't mount
  anything into the sandbox unless it's explicitly listed in `docker_volumes`. `/home/smduck` and
  `/home/smduck/Documents` themselves are never mounted — only the one working directory is.
  Every `terminal`, `write_file`, and `execute_code` call now runs inside a container with
  `--cap-drop ALL`, `--security-opt no-new-privileges`, `--user 1000:1000` (not root), and a
  256-process limit. See [`diagrams/02_architecture_before`](diagrams/02_architecture_before.svg),
  [`03_architecture_after`](diagrams/03_architecture_after.svg), and
  [`07_docker_mount_scoping`](diagrams/07_docker_mount_scoping.svg).
- **`checkpoints.enabled: true`** — off by default in Hermes. Its checkpoint manager snapshots
  the working directory into a shadow git repo *before* any `rm`, `mv`, `cp`, `sed -i`, or
  `git reset/clean`, so `/rollback` now exists as an undo path this incident never had. See
  [`diagrams/08_checkpoints_rollback`](diagrams/08_checkpoints_rollback.svg).
- **`approvals.deny`** — user-editable glob rules that block unconditionally, closing exactly the
  gap in the hardline list above, independent of whether the Docker change is even active. See
  [`diagrams/09_deny_rules_flow`](diagrams/09_deny_rules_flow.svg).

## Verified live, not just configured

The fix wasn't just written into `config.yaml` and trusted — it was checked against a real
container spawned by a real, user-started Hermes session:

```
$ docker inspect <container> --format '{{.HostConfig.CapDrop}} | user={{.Config.User}} ...'
[ALL] | user=1000:1000 | networkmode=bridge | secopt=[no-new-privileges] | pidslimit=256
```

The mount list contained **only** `hermes-sessions/ → /workspace (rw)` plus Hermes's own
skills/cache directories mounted **read-only** — `/home/smduck` and `/home/smduck/Documents`
were absent entirely.

Best of all, the sandbox caught a real mistake during that same session, not a staged test — the
agent, out of habit, ran:

```
mkdir /home/smduck
mkdir: cannot create directory '/home/smduck': Permission denied
```

That's the exact class of command that destroyed everything on day one, now failing harmlessly
because the path simply isn't mounted. See
[`diagrams/12_live_verification`](diagrams/12_live_verification.svg).

## Catch-22s

Sandboxing an agent's own filesystem access isn't free of trade-offs:

- Mounting more paths lets the agent do more useful work — and gives a bad command more to
  destroy.
- A container `$HOME` (`/root`) lets the agent keep its own scratch state — but the agent will
  sometimes write real deliverables there instead of `/workspace`, where the human expects to
  find them.
- `checkpoints.enabled` catches destructive commands before they run — but it's off by default,
  so you have to opt in *before* the incident, not after.
- The same "smart approval" LLM judgment that reduces prompt fatigue for genuinely safe commands
  is exactly what self-approved the `rm -rf` that started this whole story.
- A live, mounted root filesystem is normal and expected — and is exactly what makes post-hoc
  recovery tools like `extundelete` refuse to run when you need them most.

See [`diagrams/10_catch22s`](diagrams/10_catch22s.svg).

## How to apply this yourself

See [`diagrams/11_howto_setup`](diagrams/11_howto_setup.svg) for the full flow. Short version:

1. Back up `~/.hermes/config.yaml` first.
2. Set `terminal.backend: docker` with `docker_volumes` scoped to **one** specific directory —
   not your whole home directory.
3. Set `docker_run_as_host_user: true` so bind-mounted files stay owned by you, not root.
4. Set `checkpoints.enabled: true`.
5. Add `approvals.deny` glob rules for the exact destructive patterns you're worried about.
6. Pre-pull the `docker_image` so the first real run isn't slowed down.
7. **Verify it, don't just trust it**: run one command, then `docker inspect` the spawned
   container — check `CapDrop`, `User`, and the mount list yourself.
8. Tell the agent explicitly to write deliverables to `/workspace`, not its own container home.

## Repo structure

```
README.md
LICENSE
assets/logo.svg
diagrams/
  01_incident_timeline.{dot,svg,png}
  02_architecture_before.{dot,svg,png}
  03_architecture_after.{dot,svg,png}
  04_approval_layers.{dot,svg,png}
  05_blast_radius_comparison.{dot,svg,png}
  06_recovery_attempt_flow.{dot,svg,png}
  07_docker_mount_scoping.{dot,svg,png}
  08_checkpoints_rollback.{dot,svg,png}
  09_deny_rules_flow.{dot,svg,png}
  10_catch22s.{dot,svg,png}
  11_howto_setup.{dot,svg,png}
  12_live_verification.{dot,svg,png}
.github/workflows/verify-diagrams.yml   # re-renders every .dot on push, diffs against committed SVG
```

## License

[MIT](LICENSE)
