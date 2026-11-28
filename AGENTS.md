# AGENTS.md — moncenter

> Canonical instructions for this repository, read by Claude Code, Codex and other
> agents. Keep it short: no file tree and no symbol index, they rot. Use `ls`, `grep`
> and the module docs instead.

MonCenter is a gaming-style DDC/CI control panel for external monitors on Linux, on top of
`ddcutil`. Licence: MIT. This repository is public: nothing private (credentials, host names,
internal paths) goes in.

## Layout

- `app/moncenter.py` (Python, PySide6) — runs `ddcutil`, parses its output, exposes the monitor to QML, tray and global shortcuts.
- `app/Main.qml` — the window: picture modes, input and audio, device info.
- `package/` — the KDE Plasma 6 panel widget with the same controls.
- `install.sh` — dependencies, DDC/CI access, per-user install and uninstall.

## Rules worth knowing

- MonCenter writes to monitor hardware. Show only what the monitor's capabilities report, and keep the input auto-revert: an input with no picture must not leave the user with a black screen.
- Only standard MCCS codes; vendor-only picture modes are not exposed.
- The installer is safe to re-run and never removes system packages.

## Gate

Run this before opening a pull request. CI runs the same checks.

```sh
just check   # ruff, shellcheck, the file-size gate, then tests/run.sh
```

## Testing

`tests/run.sh` needs no monitor: it covers the output parsers, loads `Main.qml` offscreen and
checks the installer. Add a parser test with real `ddcutil` output for every monitor quirk you
fix; say in the pull request which monitor you tried a change on, or why you could not.

## Workflow

- Work in a git worktree on a branch, never on `main`. Fetch and base the branch on the latest `origin/main`.
- `main` is protected: every change is a pull request with green CI. Never push to `main`.
- Right after opening a pull request, turn on auto-merge: `gh pr merge --auto --squash`. GitHub merges it when the
  required checks pass; do not merge by hand and do not use `--admin`. Dependabot's pull requests get this from a workflow.
- Commit messages and pull request titles are [Conventional Commits](https://www.conventionalcommits.org)
  (`feat:`, `fix:`, `docs:`, `refactor:`, `ci:`, `chore:`).
- Files stay at or below 800 lines (`scripts/check-file-size.py`). Split the file; never raise the limit.
- Update README.md in the same pull request as the behaviour.
- Never commit secrets. CI scans for them; a finding is a blocker, not noise.
