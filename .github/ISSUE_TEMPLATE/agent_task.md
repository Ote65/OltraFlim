name: Agent task
about: A scoped task for a coding agent or a multi-agent handoff
title: "[agent] "
labels: agent-task
assignees: ""
---

## Goal

One observable outcome. Not a vague area.

## Owner / machine

```yaml
agent: <id>
machine: <hostname>
branch: agent/<agent-id>/<issue>-<slug>
lock: [<hot files or "none">]
```

## Context

- Read: `CODE_MAP.md`, `STATUS.md`, `AGENTS.md`
- Relevant files:
- Related issue/PR:

## Acceptance criteria

- [ ] ...
- [ ] `./script/build_and_run.sh --no-launch` passes
- [ ] UI manual test explicitly marked (owner)
- [ ] No secrets / user data / dist in commit

## Out of scope

## Handoff

```yaml
status: ready | blocked | partial
verified:
not_verified:
risks:
next:
```
