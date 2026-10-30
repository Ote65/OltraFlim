# Multi-agent / multi-machine collaboration

This document is the operating protocol for several agents (or humans using
agents) working on OltraFlim from different machines. It complements
[`../AGENTS.md`](../AGENTS.md), [`../CODE_MAP.md`](../CODE_MAP.md) and
[`../STATUS.md`](../STATUS.md).

The goal is simple: **no two workers silently change the same hot file, and no
worker claims a UI test they did not perform.**

## 1. Source of truth

| Artifact | Role |
| --- | --- |
| GitHub Issues | task backlog, ownership, acceptance criteria |
| GitHub PRs | reviewed changes, verification evidence, handoff |
| `main` branch | integration truth |
| `CODE_MAP.md` | architecture truth |
| `STATUS.md` | release/verification truth |
| `AGENTS.md` | agent rules |
| This file | coordination protocol |

Private chat, local notes, or another agent's memory are **not** the source of
truth. If it is not in the issue/PR/main, it did not happen.

## 2. Roles

For a small team, use these roles. One person/agent may hold several roles, but
the same agent must not review its own change alone.

| Role | Owns | Responsibilities |
| --- | --- | --- |
| Coordinator | issues, merge order, release | triage, assign, resolve file locks, cut releases |
| Engine owner | `Renderer.swift`, `Shaders.metal`, `CurveTexture.swift` | uniform contract, LUT/curve/export correctness |
| Library owner | `AppModel.swift` library sections, `LibraryFolder`, `LibraryMetaStore`, `HomeLibraryView` | folder/photo index, filters, tags, persistence |
| Inspector owner | `InspectorView`, `CurveTabView`, sliders | controls, tabs, localisation of controls |
| Shell owner | `TopBar`, `WindowConfigurator`, `CanvasView`/`CanvasState` | window drag, traffic lights, canvas gestures |
| Release owner | build, DMG/ZIP, GitHub Release | version bump, checksums, notes |
| Reviewer | any PR | spec + standards review, verification audit |

## 3. File ownership and lock protocol

### 3.1 Hot files

The following files are serial-write:

```text
Stores/AppModel.swift
Engine/Renderer.swift
Resources/Shaders.metal
Views/HomeLibraryView.swift
Views/InspectorView.swift
Views/TopBar.swift
Views/CanvasView.swift
```

Only one branch may modify a hot file at a time. To take it:

1. Open/claim the issue.
2. Comment on the issue:
   ```text
   lock: AppModel.swift
   branch: agent/a/123-library-filter
   from: 2026-10-30T12:00Z
   until: 2026-10-30T18:00Z (or "until PR merged")
   ```
3. Put the same line in the PR description.
4. Release the lock when merged or abandoned.

If a second worker needs the same file, the coordinator must either:

- sequence the two PRs (preferred), or
- split the change into a separate file/type first, then merge, or
- grant an explicit exception with a time box and a rebase plan.

### 3.2 Safe parallel work

These can usually proceed in parallel with a hot file lock held by someone else:

- new `Views/*` file that does not edit `ContentView`/hot files
- tests/tools under `Tools/`
- docs under `docs/`, `README`, `STATUS`
- localization strings in `Localization.swift` (small, but avoid conflicting edits)
- isolated model file such as `LibraryFolder.swift`
- GitHub issue templates, CI, release scripts

Do not “just append a few lines” to a hot file without the lock. That is how
silent merge conflicts happen.

## 4. Branch and worktree rules

Branch names:

```text
agent/<agent-id>/<issue>-<slug>
human/<name>/<slug>
release/<version>
```

Examples:

```text
agent/library-a/128-folder-breadcrumb
agent/engine-b/131-grain-size
human/ote/130-topbar-centering
```

Per worker/machine:

```bash
git fetch origin
git worktree add ../Oflim-a -b agent/library-a/128-folder-breadcrumb origin/main
cd ../Oflim-a
./script/build_and_run.sh --no-launch
```

Rules:

- One worktree per active branch.
- Do not share `.build/` between worktrees; let each build its own.
- Do not copy `dist/` between machines.
- Never force-push a shared branch.
- Rebase on `origin/main` before review; resolve conflicts locally, then push.
- Keep branches short-lived (target < 2 working days).

## 5. Task lifecycle

```text
Backlog
  → Claim (assignee + lock comment)
  → Implement
  → Self-check (compile --no-launch + relevant headless checks)
  → PR (evidence + not-verified list)
  → Review (second agent)
  → Rebase / fix
  → Merge to main
  → Release (version bump + packages)
```

### Claim template

```yaml
task: <issue title>
agent: <id>
machine: <hostname>
branch: <branch>
lock: [<hot files or "none">]
eta: <time or "unknown">
```

### Acceptance criteria

An issue must state observable behavior, not implementation wishes. For UI:

- which screen/state
- what the user does
- what should happen
- what must not happen

For renderer:

- input/params
- expected pixel/visual effect
- preview and export both covered
- manual check required or not

## 6. Verification matrix

| Change type | Required |
| --- | --- |
| Swift-only, no UI | `./script/build_and_run.sh --no-launch`, type check |
| Shader/uniform | `--no-launch` + runtime shader check or headless RenderCheck + manual visual |
| Photo library/folder | `--no-launch` + manual folder flow by owner |
| Window/drag/traffic lights | `--no-launch` + **owner manual test only** |
| Persistence | `--no-launch` + owner restart test |
| Packaging/docs | version/plutil/hdiutil/shasum checks |
| License/asset | attribution/license check, no binary redistribution issue |

**Agent policy: do not launch the app.** The owner is the only UI tester unless
they explicitly delegate that run. A PR must list `UI: not verified (owner)`
when applicable.

## 7. Review protocol

Every PR gets two axes:

1. **Spec** — does it implement the issue's observable behavior?
2. **Standards** — does it follow the repo patterns (`DS`, `T`, uniform order,
   library invariants, no new dependencies, no nested Buttons, etc.)?

Reviewer must:

- read `CODE_MAP.md` hot-file notes,
- inspect verification commands; do not accept “compiles” as UI proof,
- check export path when a renderer parameter changes,
- check persistence when a library field changes,
- check license/notice files when assets change,
- call out any unverified manual test explicitly.

The reviewer should leave one of:

```text
APPROVE — spec + standards, manual test still owner’s
APPROVE WITH MANUAL TEST — list exact steps
REQUEST CHANGES — spec gap / standards gap / evidence gap
BLOCK — architecture/license/secret issue
```

## 8. Conflict resolution

### Two agents conflict on a hot file

1. Stop both; coordinator chooses the earlier PR to merge first.
2. The second branch rebases and resolves, preserving both behaviors.
3. If the resolution is non-trivial, the reviewer must inspect the combined
   diff, not just each side.
4. Re-run `--no-launch`; update `STATUS.md` if verification changed.

### Conflicting product behavior

Escalate to the owner with:

- current behavior
- proposed behavior
- files affected
- risk
- manual test needed

Do not silently pick one.

### License conflict

Stop. `THIRD_PARTY_NOTICES.md` is authoritative. Never relicense upstream LUTs
as noncommercial-only or remove attribution to resolve a conflict.

## 9. Handoff template

Copy into an issue/PR comment:

```yaml
handoff:
  from_agent: <id>
  to_agent: <id>
  machine: <hostname>
  branch: <branch>
  issue: #<number>
  status: ready | blocked | partial
  changed:
    - path
  verified:
    - command: result
  not_verified:
    - UI flow: owner manual test
  locks:
    - file
  risks:
    - risk
  next:
    - next action
  notes:
    - anything the next agent must not assume
```

The receiving agent must acknowledge with:

```text
ack: <agent> / <machine> / <branch> / <timestamp>
```

## 10. Cross-machine setup

Each machine must have:

- macOS 14+
- Command Line Tools, `swiftc`
- `git` with its own identity
- GitHub authentication (`gh auth login` or SSH key)
- Python 3 only if regenerating LUTs
- an independent `.build/` cache

Do not commit:

- keychain exports, tokens, SSH keys
- `~/Library/Application Support/OltraFlim` user state
- user photos/DNGs
- `dist/`, `.build/`, generated iconsets
- local `.codex/` environment files

If two machines need to compare builds, exchange **checksums and release notes**,
not the `dist/` directory or local user state.

## 11. Release coordination

Release owner only:

1. Confirm `main` is green by `--no-launch`.
2. Bump version in `Info.plist` + `SettingsView`.
3. Update `README.md`, `STATUS.md`, `CHANGELOG.md`.
4. Build `dist/OltraFlim.app` with `--no-launch`.
5. Create DMG/ZIP, record SHA-256.
6. Verify DMG mount and version.
7. Publish GitHub Release with DMG/ZIP.
8. Post owner manual-test checklist.

No release may claim a UI pass without the owner's explicit confirmation.

## 12. Current queue snapshot

Use GitHub Issues as the live queue. At the time of writing, the next
owner-facing manual checks are:

1. traffic lights centered and clickable
2. only top bar drags the window
3. canvas drag pans; Ctrl/Cmd wheel zooms; Space resets
4. folder import → folder page → breadcrumb/up → refresh
5. favourite/colour label persistence after restart
6. bottom-right fixed Reset/Export/Settings bar
7. tab transition and curve dragging

Update this snapshot only when the status actually changes.
