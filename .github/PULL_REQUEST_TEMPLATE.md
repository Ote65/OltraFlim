<!--
Thanks for contributing. Keep the PR focused and include actual verification.
Do not claim UI tests you did not run.
-->

## Summary

What changed and why?

Fixes/closes #

## Scope

Affected files/subsystems:

- [ ] Library / folders
- [ ] Renderer / shaders
- [ ] Inspector / curves
- [ ] Window chrome / canvas
- [ ] Export
- [ ] Docs / release

## Verification

Commands run:

```text
./script/build_and_run.sh --no-launch
```

Result:

- compile:
- warnings:
- headless checks:
- package/version checks:

## Manual test

- [ ] Not applicable
- [ ] Owner manual test required (describe exact steps below)
- [ ] I ran the app myself (state machine/OS and steps)

Manual steps / expected behavior:

```text

```

## Invariants

- [ ] `Uniforms` field order matches `RenderUniforms` (if renderer/shader)
- [ ] Preview and export both updated (if renderer)
- [ ] Library persistence rules preserved (if library)
- [ ] No nested clickable `Button` inside cards/rows (if UI)
- [ ] User-visible strings use `T(...)`
- [ ] No new dependencies
- [ ] No secrets, user photos, `dist/`, `.build/` added
- [ ] Upstream license/attribution intact

## Screenshots / notes

Only include screenshots you produced yourself. Do not attach user photos or
private library data to public PRs.

## Not verified

List anything not verified here. Do not leave it implicit.
