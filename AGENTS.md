# AGENTS.md

This file is the working agreement for agents changing Omarchy World Clock.
Read it before editing the repository.

## Project scope

This repository contains a keyboard-first world-clock plugin for Omarchy 4 /
Quattro. The released surface is the compact bar popup.

- `BarWidget.qml`: bar icon and popup entry point
- `Panel.qml`: compact calendar, clock list, editors, settings, and time slider
- `AnalogClock.qml`: analog clock face
- `Model.js`: clock, calendar, formatting, and default-location logic
- `components/WorldClockService.qml`: shared state and persistence
- `helpers/timezone.py`: local timezone lookup and conversion helper
- `FullView.qml`, `components/TimelineView.qml`, and
  `components/WorldMap.qml`: hidden meeting-planner prototype
- `assets/`: generated map and timezone-boundary data plus attribution
- `tests/`: JavaScript and Python tests

Do not expose the full view from the release UI unless the user explicitly asks
for it. Preserve the implementation because it remains on the roadmap.

## Product guardrails

Preserve these established decisions unless the task explicitly changes one:

- The plugin works alongside `omarchy.clock`; it does not replace or modify it.
- The calendar and World Clock header stay fixed at the top.
- The time slider and keyboard guide stay fixed at the bottom.
- Only the clock list scrolls, and it has no visible scrollbar.
- The compact panel supports mouse and complete keyboard operation.
- `j` / `k` selects, Shift+`j` / Shift+`k` reorders, `A` adds, `R`
  renames, `D` deletes, `H` sets Home, `S` opens Settings, and `T` returns
  to Now.
- Left / Right changes the selected time immediately in 15-minute steps;
  Shift+Left / Shift+Right uses one-hour steps. Do not debounce the slider.
- Add and Settings are replacement views. They hide the clock list instead of
  expanding inline and pushing the fixed footer away.
- Clock rows support drag-and-drop reordering with animated displacement.
- Stationary mouse hover must not steal selection back after keyboard reorder.
  Mouse selection should change only after actual pointer movement.
- The Home marker is a small square-corner label. Do not add `WORK`, `OFF`, or
  working-hours labels without a new product decision.
- Analog clocks are optional. Digital clocks support clear 12-hour AM/PM and
  24-hour formats.
- The planning slider spans -24 to +24 hours. The calendar can move across
  dates independently.
- Keep the compact popup anchored to its bar item rather than centered on the
  screen.

## State and safety

Plugin state lives only in the `io.github.ptgamr.world-clock` entry of
`~/.config/omarchy/shell.json`.

- Do not replace the whole `shell.json` file.
- Do not edit another plugin's entry or the built-in `omarchy.clock` entry.
- Treat the user's clock list, order, aliases, Home selection, and appearance
  settings as user data.
- Do not reset live state merely to make a screenshot.
- If a requested live test mutates state, record the original plugin entry and
  restore only the values changed by the test. Prefer restoring through the UI.
- Preserve unrelated worktree changes. Inspect `git status` and `git diff`
  before editing and before every commit.

The timezone helper must remain local-only. Do not add network lookup, a
background service, privilege escalation, or shell-string execution. Continue
to pass fixed argument arrays to the helper.

## Implementation workflow

1. Read the relevant QML, JavaScript, helper, and tests before changing code.
2. Reproduce or identify the behavior in the live panel when practical.
3. Make the smallest coherent change that addresses the request.
4. Add or update a focused automated test when logic changes.
5. Run the focused checks, then the complete validation suite below.
6. For user-visible QML changes, deploy to the existing shell and perform the
   live checks below.
7. Review the final diff and commit the completed chunk.

Use Omarchy's shared UI components from `/usr/share/omarchy/shell` where they
fit. Never edit files under `/usr/share/omarchy` as part of this plugin.

## Automated validation

Run these commands from the repository root after every completed change:

```sh
git diff --check
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell \
  BarWidget.qml Panel.qml FullView.qml components/*.qml
python3 -m unittest discover -s tests -p 'test_*.py'
node tests/model-test.js
node tests/timezone-lookup-test.js
```

All commands must pass before handoff. Use the explicit Qt 6 `qmllint` path;
the unqualified command may resolve to the incompatible Qt 5 linter on this
workstation. Import warnings are expected without the running shell's complete
module context, but the command must exit successfully. A silent
plugin-validation run is a successful run.

When changing generated geographic data, also read the regeneration and
license instructions in `assets/TIMEZONE_BOUNDARIES.md` and
`assets/NATURAL_EARTH.md`. Regenerate assets with the scripts under `tools/`;
do not hand-edit generated JSON.

## Live UI testing

Use the already running Omarchy shell. Do not launch a second Quickshell
instance.

On this workstation, the installed checkout is:

```text
~/.config/omarchy/plugins/io.github.ptgamr.world-clock
```

Before deploying, confirm both source and installed checkouts are clean enough
to fast-forward. Do not overwrite an unexpected installed change.

After committing a UI chunk, deploy and reload with:

```sh
git -C "$HOME/.config/omarchy/plugins/io.github.ptgamr.world-clock" \
  pull --ff-only
omarchy-restart-shell
omarchy-shell shell summon io.github.ptgamr.world-clock '{}'
```

The direct `summon` command is the repeatable launch check. On this workstation,
Super+Ctrl+2 should also open the compact popup rather than `FullView.qml`.

For a temporary visual record, use `/tmp`:

```sh
grim /tmp/oma-world-clock-check.png
```

Inspect the captured image rather than claiming success from static checks.
Only replace `preview.png` or add repository screenshots when the user asks.
When keeping multiple review screenshots, use sequential `v1`, `v2`, and so on
in their filenames.

### Compact-panel smoke test

For a user-visible change, test the affected behavior plus the nearest related
items. For a release-level check, cover all of the following:

1. The bar icon opens the compact popup beneath its bar position.
2. The calendar and header remain fixed while a long clock list scrolls.
3. The footer remains visible, and no scrollbar or right-edge scroll track is
   drawn.
4. Analog clocks tick while the panel is open, including the red seconds hand.
5. 12-hour mode shows AM/PM clearly; 24-hour mode removes it.
6. Dragging or scrolling the time slider updates every clock continuously.
7. Left / Right, Shift+Left / Shift+Right, and `T` operate the slider and Now
   state correctly. The offset tooltip and `T now` hint remain aligned.
8. `j` / `k` selects clocks and keeps the selected row revealed in a long list.
9. Shift+`j` / Shift+`k` and drag-and-drop reorder with visible animation.
10. With the pointer stationary over a row, keyboard reorder does not jump the
    selection back to the hovered row.
11. `A` hides the clocks, searches locally, accepts an Alias, adds a clock, and
    returns to the clock list.
12. `R`, `D`, and `H` rename, delete, and set Home through the keyboard.
13. `S` hides the clocks and opens Settings. `j` / `k`, Left / Right, Enter,
    Space, `A`, `1`, `2`, and Escape work there.
14. State survives an Omarchy shell restart without changing another plugin's
    configuration.

Do not perform destructive clock-list checks on the user's live configuration
unless the task calls for them. Use automated tests for logic coverage and keep
read-only live checks read-only.

## Commit discipline

Commit every meaningful completed chunk separately. A chunk is one coherent
behavior or documentation outcome, not every individual file and not an entire
unrelated batch.

- Keep implementation and its directly required test in the same commit.
- Put unrelated runtime, documentation, preview-image, and generated-asset
  changes in separate commits.
- Stage explicit paths. Do not use `git add -A` in a dirty worktree.
- Never include user-owned or unrelated changes just to make the tree clean.
- Review `git diff --cached --check` and the staged diff before committing.
- Use concise conventional messages such as `feat:`, `fix:`, `test:`,
  `refactor:`, `docs:`, or `chore:`.
- Each commit should pass the checks relevant to its content and be safe to
  review or revert on its own.
- Run the full validation suite before final handoff even when focused checks
  passed earlier.
- Do not push, rewrite published history, or submit marketplace forms unless
  the user explicitly requests it.

Examples of appropriate chunks:

- `fix: keep keyboard selection after reorder`
- `feat: add 24-hour display setting`
- `test: cover first-run timezone defaults`
- `docs: refresh readme preview`

## Handoff checklist

Before reporting completion:

- Confirm the requested outcome is implemented, not merely planned.
- Report automated checks actually run and their results.
- For UI work, report whether the installed plugin was updated and live-tested.
- List the commit hash and subject for each new chunk.
- Report any remaining dirty files and state explicitly that they were not
  included.
- Mention any limitation or untested interaction plainly.
