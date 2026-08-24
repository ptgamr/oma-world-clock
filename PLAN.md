# PLAN.md

# Omarchy World Clock Plugin

## Goal

Build a **new, standalone Omarchy Quattro plugin** for world clocks and meeting planning, inspired by **The Clock** for macOS.

This plugin is **separate from the built-in `omarchy.clock` plugin**.

The existing clock can be cloned during development because it provides useful scaffolding and examples of how an Omarchy Quattro bar widget should behave, but the resulting plugin must have its own plugin ID, configuration, components, and lifecycle.

The built-in clock should continue to exist independently.

The core question this plugin should answer is:

> **When is a good time for people in different time zones to meet?**

The first version should focus on:

- multiple world clocks
- meeting-time exploration
- selectable planning dates
- DST-correct timezone conversion
- working-hours visibility

It should **not** attempt to replicate every feature of The Clock.

---

# 1. Relationship With `omarchy.clock`

The built-in Omarchy clock is **reference implementation and scaffolding**, not the foundation of the final product.

During development we can start with:

```bash
omarchy plugin clone omarchy.clock --edit
```

This gives us working examples for:

- plugin manifest structure
- `BarWidget.qml`
- popup anchoring
- Omarchy theme integration
- keyboard/focus handling
- IPC patterns
- configuration persistence
- Quickshell `SystemClock`
- panel loading
- hot reload

From there, convert the clone into a completely separate plugin.

Conceptually:

```text
omarchy.clock
      │
      │ clone for scaffolding
      ▼
temporary development copy
      │
      │ extract useful patterns
      ▼
world-clock plugin
```

Final state:

```text
Omarchy shell
│
├── omarchy.clock
│     └── normal built-in clock
│
└── world-clock
      └── world clock + meeting planner
```

The two plugins must be able to coexist.

---

# 2. Do Not Depend on the Built-In Clock

The new plugin should not:

- replace `omarchy.clock`
- override `omarchy.clock`
- mutate files belonging to `omarchy.clock`
- depend on internal runtime state from `omarchy.clock`
- assume the built-in clock is enabled
- share configuration with the built-in clock

The clone is simply a convenient way to learn and reuse patterns.

As implementation progresses, remove code inherited from `omarchy.clock` that is irrelevant to the world-clock use case.

---

# 3. Product Scope

## Primary use case

The bar should provide a compact indication that this is the world-clock/planning tool.

Possible bar presentation:

```text
󰥔  WLG 10:42
```

or simply:

```text
󰥔
```

Clicking it opens the world-clock panel:

```text
Wellington      10:42
London          23:42  Yesterday
New York        18:42  Yesterday
Ho Chi Minh     05:42
```

The user can then move the planning time:

```text
NOW
────────●──────────────────
```

to:

```text
+4h
──────────────●────────────
```

and every clock updates simultaneously:

```text
Wellington      14:45  🟢
London          03:45  🔴
New York        22:45  🔴
Ho Chi Minh     09:45  🟢
```

The user should immediately see whether that proposed meeting time is reasonable.

---

# 4. Design Principles

## Feel Native to Omarchy

Use the built-in clock as a reference for:

- spacing
- typography
- borders
- popup positioning
- theme values
- animations
- keyboard interaction
- panel behavior

Do not recreate The Clock's macOS appearance.

The goal is:

> The Clock's concepts, implemented as an Omarchy-native tool.

---

## Independent Plugin

The world clock should own:

```text
manifest
bar widget
panel
configuration
locations
timezone calculations
planner state
working-hour preferences
```

There should be no hidden coupling with `omarchy.clock`.

---

## World Clocks Can Represent People

Store timezone and display name independently.

Example:

```json
{
  "name": "US Team",
  "timezone": "America/New_York"
}
```

Other useful names:

```text
James
Customer
Family
London Office
Production
```

The timezone defines the clock.

The name defines what that clock means to the user.

---

## Always Use Real Timezone Rules

Never store:

```text
New York = UTC-5
```

Store:

```text
America/New_York
```

and calculate the correct offset for the exact planning instant.

This is required because DST rules change offsets throughout the year.

---

# 5. Plugin Structure

Initial structure:

```text
world-clock/
├── manifest.json
├── BarWidget.qml
├── Panel.qml
├── Model.js
│
├── components/
│   ├── WorldClockList.qml
│   ├── WorldClockRow.qml
│   ├── MeetingPlanner.qml
│   ├── DatePicker.qml
│   ├── WorkingHoursIndicator.qml
│   ├── AddLocation.qml
│   └── LocationMenu.qml
│
├── services/
│   └── TimezoneService.qml
│
└── helpers/
    └── timezone.py
```

Do not split everything into components immediately.

Start with:

```text
BarWidget.qml
Panel.qml
Model.js
```

and extract components when the implementation becomes large enough to justify it.

---

# 6. Bar Widget

This plugin should have its **own bar widget**.

It should not attempt to duplicate the normal local clock unless useful.

Possible designs:

### Minimal

```text
󰥔
```

### Show configured locations

```text
󰥔 4
```

### Show home time

```text
󰥔 10:42
```

### Show another important timezone

```text
NZ 10:42 · UK 23:42
```

The exact default should stay compact because users may already have `omarchy.clock` visible.

Recommended MVP:

```text
󰥔
```

or:

```text
󰥔 4
```

where `4` is the number of configured clocks.

Click opens the planner.

---

# 7. Panel Layout

Proposed initial panel:

```text
┌──────────────────────────────────────────┐
│ WORLD CLOCK                         NOW  │
│                                          │
│ Wellington                       10:42   │
│ Home                                🟢   │
│                                          │
│ London                           23:42   │
│ Yesterday · -11h · BST             🔴   │
│                                          │
│ New York                         18:42   │
│ Yesterday · -16h · EDT             🟡   │
│                                          │
│ Ho Chi Minh                      05:42   │
│ -5h · ICT                          🔴    │
│                                          │
├──────────────────────────────────────────┤
│ Mon 24 Aug 2026                         │
│                                          │
│ -12h ───────────●────────────── +12h    │
│                 NOW                     │
│                                          │
│              + Add location             │
└──────────────────────────────────────────┘
```

The world clocks should be the primary content.

The calendar/date picker is secondary and exists to support planning.

---

# 8. Date Selection

Unlike the built-in Omarchy clock, this plugin does not need a full read-only calendar as its main feature.

Its date UI exists specifically for meeting planning.

Possible initial UI:

```text
‹  Mon 24 Aug 2026  ›
```

Click the date to expand a calendar:

```text
       AUGUST 2026

Mo Tu We Th Fr Sa Su
                1  2
 3  4  5  6  7  8  9
10 11 12 13 14 15 16
17 18 19 20 21 22 23
24 25 26 27 28 29 30
31
```

Maintain:

```qml
property date selectedDate
```

Default:

```text
selectedDate = today
```

Selecting a date changes the date used by the meeting planner.

---

# 9. Core Time Model

Use one canonical planning instant.

```text
selected date/time
        ↓
planningInstant
        ↓
timezone conversion
```

Every location renders the same instant.

Example:

```text
                     planningInstant
                           │
            ┌──────────────┼─────────────┐
            ↓              ↓             ↓
     Pacific/Auckland Europe/London America/New_York
            ↓              ↓             ↓
          14:00          03:00         22:00
```

Never independently modify individual world clocks.

---

# 10. Meeting Planner

The planner is the main feature.

Initial state:

```text
-12h ───────────●────────── +12h
                NOW
```

Dragging changes the common planning instant.

Recommended interaction:

```text
drag                  15-minute increments
Shift + drag          30-minute increments

Left / Right          ±15 minutes
Shift + Left/Right    ±1 hour

T                     return to now
Escape                close panel
```

Show the offset clearly:

```text
+3h 15m
```

When the planner is at the current instant:

```text
NOW
```

---

# 11. Planner Representation

Prefer storing an **absolute planning timestamp** rather than separate timezone-specific times.

Conceptually:

```qml
property double planningTimestamp
```

The current time mode is:

```text
planningTimestamp = now
```

Dragging:

```text
planningTimestamp += 15 minutes
```

Changing date updates the date portion while preserving an appropriate planning time.

Each location then asks:

```text
What local date/time corresponds to this timestamp
in America/New_York?
```

This keeps the architecture simple.

---

# 12. World Clock List

Each row should show:

- display name
- local time
- relative date
- timezone difference from home
- optional timezone abbreviation
- working-hours state

Example:

```text
Wellington                           10:45
HOME                                   🟢

London                               23:45
Yesterday · -11h · BST                 🔴

New York                             18:45
Yesterday · -16h · EDT                 🟡

Ho Chi Minh                          05:45
-5h · ICT                              🔴
```

Avoid unnecessary information when values are obvious.

For example, do not display:

```text
Today · +0h
```

for the home clock.

---

# 13. Home Location

One configured location should act as the reference timezone.

Example:

```json
{
  "id": "home",
  "name": "Wellington",
  "timezone": "Pacific/Auckland",
  "isHome": true
}
```

Relative offsets are calculated against it.

Example:

```text
London       -11h
New York     -16h
Vietnam      -5h
```

On first run, the home location defaults to the detected system IANA timezone.
The plugin adds two representative locations from other regions so the initial
panel contains three geographically useful clocks. The user can change the
home location later; automatic detection never replaces saved locations.

---

# 14. Location Data Model

Suggested model:

```json
{
  "locations": [
    {
      "id": "home",
      "name": "Wellington",
      "timezone": "Pacific/Auckland",
      "isHome": true,
      "latitude": -41.2866,
      "longitude": 174.7756
    },
    {
      "id": "london",
      "name": "London",
      "timezone": "Europe/London"
    },
    {
      "id": "new-york",
      "name": "US Team",
      "timezone": "America/New_York"
    }
  ]
}
```

Later:

```json
{
  "workingHours": {
    "monday": [["09:00", "17:00"]],
    "tuesday": [["09:00", "17:00"]],
    "wednesday": [["09:00", "17:00"]],
    "thursday": [["09:00", "17:00"]],
    "friday": [["09:00", "17:00"]]
  }
}
```

---

# 15. Location Management

Users should be able to:

- add
- remove
- rename
- reorder
- choose home location

UI:

```text
+ Add location
```

Search:

```text
Search city or timezone

> london

London
Europe/London

> new york

New York
America/New_York
```

Initially, IANA timezone search is sufficient.

A richer city database can come later.

---

# 16. Timezone Service

Do not manually calculate DST offsets.

Use the system timezone database.

Investigate whether Qt's timezone APIs provide everything required.

Preferred architecture if supported:

```text
QML / Qt
   ↓
IANA timezone
   ↓
system tzdata
```

Fallback:

```text
QML
 ↓
TimezoneService
 ↓
Python zoneinfo
 ↓
system tzdata
```

Python provides:

```python
from zoneinfo import ZoneInfo
```

Examples:

```python
ZoneInfo("Pacific/Auckland")
ZoneInfo("Europe/London")
ZoneInfo("America/New_York")
```

The service should take:

```json
{
  "timestamp": 1787553600,
  "zones": [
    "Pacific/Auckland",
    "Europe/London",
    "America/New_York"
  ]
}
```

and return:

```json
[
  {
    "timezone": "Pacific/Auckland",
    "date": "2026-08-24",
    "time": "09:00",
    "utcOffsetMinutes": 720,
    "abbreviation": "NZST"
  }
]
```

---

# 17. DST Requirements

DST correctness is a core feature.

Test:

```text
Pacific/Auckland
Europe/London
America/New_York
Australia/Adelaide
```

Also test non-whole-hour zones:

```text
Asia/Kathmandu       UTC+5:45
Asia/Kolkata         UTC+5:30
Australia/Adelaide   half-hour + DST
```

Test cases should include:

- summer
- winter
- DST start
- DST end
- future dates
- past dates
- crossing midnight
- crossing year boundaries

The same two locations may have different relative offsets depending on the selected date.

That behavior must be correct.

---

# 18. Day Relationship

Describe each location's calendar date relative to the home location.

Possible values:

```text
Yesterday
Today
Tomorrow
```

Only show them when useful.

Example:

```text
London
Yesterday · -11h · BST
```

---

# 19. Working Hours

Default working hours:

```text
Monday-Friday
09:00-17:00
```

Visual state:

```text
🟢 normal working hours
🟡 early/late but potentially reasonable
🔴 clearly outside normal hours
```

Initial heuristic:

```text
GREEN
09:00-17:00

AMBER
07:00-09:00
17:00-20:00

RED
everything else
```

Use Omarchy theme colors/icons rather than literal traffic-light colors if appropriate.

Later support custom working hours per location.

---

# 20. Location Interaction

Suggested right-click menu:

```text
Rename
Set as home
Working hours
Move up
Move down
Remove
```

Keep the normal row visually simple.

Avoid permanent edit/delete buttons unless needed.

---

# 21. Configuration

The new plugin owns its own configuration.

Possible schema:

```json
{
  "showTimezoneAbbreviation": true,
  "showRelativeOffset": true,
  "showWorkingHours": true,
  "plannerStepMinutes": 15,
  "locations": []
}
```

Do not reuse or modify `omarchy.clock` settings.

Configuration should remain valid regardless of whether the built-in clock plugin is enabled.

---

# 22. Development Phases

## Phase 1 — Scaffold From Omarchy Clock

Use the clone only to get a working Quattro plugin environment.

Tasks:

- clone `omarchy.clock`
- assign a new plugin ID
- assign a new display name
- make sure it can coexist with `omarchy.clock`
- remove unnecessary clock-specific functionality
- retain useful panel/bar scaffolding
- verify independent configuration
- verify hot reload

Acceptance criteria:

```text
built-in clock visible
+
world-clock plugin visible

both running independently
```

---

## Phase 2 — Basic World Clock Panel

Hard-code:

```text
Pacific/Auckland
Europe/London
America/New_York
Asia/Ho_Chi_Minh
```

Render:

- location name
- current local time
- relative date
- timezone abbreviation
- offset from home

No editing yet.

Acceptance criteria:

All locations show the correct current time simultaneously.

---

## Phase 3 — Timezone Engine

Formalize timezone conversion into a service/model.

Add automated tests.

Acceptance criteria:

Known timezone and DST cases produce correct results.

---

## Phase 4 — Configurable Locations

Add:

- add location
- remove location
- rename location
- reorder
- choose home location
- persistence

Acceptance criteria:

Locations survive shell restart.

---

## Phase 5 — Meeting Planner

Add:

- canonical planning instant
- slider
- ±12-hour visible range
- 15-minute snapping
- keyboard controls
- offset display
- reset to now

Acceptance criteria:

Moving the planner updates every location simultaneously.

---

## Phase 6 — Date Planning

Add:

- selected planning date
- compact date selector
- optional expanded calendar
- future/past date calculations

Acceptance criteria:

Selecting a future date recalculates timezone offsets using DST rules for that exact date.

---

## Phase 7 — Working Hours

The compact row labels are intentionally hidden for now because persistent
`WORK` / `EDGE` / `OFF` text competes with the clock information. Keep the
availability model for the future expanded timeline, where the full-day bands
provide useful context without cluttering every compact row.

Add:

- default hours
- availability indicator
- changing status while moving planner

Acceptance criteria:

Users can visually identify reasonable meeting times without manually interpreting each clock.

---

## Phase 8 — UX Polish

Improve:

- animations
- keyboard focus
- scrolling
- location search
- context menu
- empty state
- error handling
- panel sizing
- theme integration

## Phase 9 — Expanded Planner Window (implemented)

The compact panel now exposes `Open full view`, which opens a separate resizable
Omarchy `FloatingWindow`. Both surfaces use one session service, so location
changes and the canonical planning instant stay synchronized.

Implemented:

- compact-panel `Open full view` action
- shared clocks, preferences, and selected instant
- DST-correct horizontal 24-hour timeline
- click/drag meeting-start selection with 15-minute snapping
- adjustable meeting duration and `Copy meeting time`
- bundled Natural Earth world map with precise city markers
- selected-time day/night terminator
- projection-preserving 2:1 map canvas at every window width
- bundled geographic timezone boundaries with hover and click hit-testing
- explicit add-clock confirmation for a map-selected timezone

Acceptance criteria:

The compact panel and expanded window show the same clock order and selected
time, and a copied meeting summary contains the correct local range for every
timezone.

---

# 23. MVP

Version `0.1` should include:

- standalone Omarchy plugin
- independent bar widget
- multiple world clocks
- home location
- add/remove locations
- rename
- reorder
- timezone abbreviation
- relative timezone difference
- Yesterday/Today/Tomorrow
- DST-correct conversion
- meeting planner
- planning date
- reset to now
- working-hours indicator
- resizable expanded planner
- horizontal 24-hour timezone timeline
- meeting range and copy action
- local day/night world map
- interactive timezone-region selection and add-clock action

It must coexist with `omarchy.clock`.

---

# 24. Version 1.0

A polished `1.0` should add:

- excellent keyboard support
- configurable working hours
- polished timezone search
- smooth planner interaction
- reliable DST handling
- saved coordinates for custom labels that do not identify a known city

Example:

```text
Tuesday, 25 August 2026

Wellington — 9:00 AM
London — 10:00 PM
New York — 5:00 PM
```

---

# 25. Future Features

## Expanded Planner Window (MVP implemented)

Keep the bar popup compact for quick clock checks. Rich planning views should
open in a separate, resizable Omarchy `FloatingWindow` exposed through a
`panel` entry point alongside the existing `bar-widget` entry point.

The expanded workspace now includes:

- a horizontal 24-hour availability timeline for every location
- a selected meeting-time range shared by all rows
- a world map with location markers and a day/night overlay
- geographic timezone boundaries that can be hovered, selected, and added
- larger calendar navigation and copy/share controls

The compact panel and expanded window share the same locations and one
canonical planning timestamp. New search selections save coordinates from the
installed IANA timezone tables, known existing city labels are migrated to
their precise coordinates, and other saved clocks fall back to the timezone's
representative point. The bundled Natural Earth geometry keeps the map local,
and the simplified timezone-boundary-builder database performs point lookup
without an external map service.

## Find Best Meeting Time

Instead of manually moving the slider, calculate good overlap.

```text
BEST OVERLAP

Wellington      07:00
London          20:00
New York        15:00
```

---

## 24-Hour Availability View

```text
          00   06   12   18   24

Wellington ████████░░░░░░██████
London     ░░░░████████░░░░░░░░
New York   █████░░░░░░█████████

OVERLAP    ───────────██────────
```

---

## Calendar Integration

Potential sources:

- khal
- vdirsyncer
- ICS
- Nextcloud
- Google Calendar

Keep provider logic outside the world-clock UI:

```text
Calendar Source
       ↓
Adapter
       ↓
Normalized Events
       ↓
Planner
```

---

## Holidays

Use holidays when evaluating whether a time is reasonable.

---

## Sunrise / Sunset

Store coordinates separately from timezone:

```json
{
  "timezone": "Europe/London",
  "latitude": 51.5072,
  "longitude": -0.1276
}
```

Calculate locally.

---

# 26. Explicitly Out of Scope

Do not initially implement:

- moon phases
- Pomodoro
- break reminders
- cloud synchronization
- custom theme engine
- Dropbox/iCloud-style backup
- analog clock collections
- world maps inside the compact bar popup
- floating clocks

These do not strengthen the primary use case enough to justify the complexity.

---

# 27. Important Technical Questions

## Can Qt Handle All Timezone Conversion?

Investigate before committing to Python.

If Qt supports:

```text
arbitrary IANA timezone
+
arbitrary timestamp
+
DST-aware conversion
```

prefer a native implementation.

Use Python `zoneinfo` as fallback or test oracle.

---

## Best Location Dataset

Investigate:

```text
/usr/share/zoneinfo/zone1970.tab
```

and other installed tzdata files.

Avoid introducing an external API.

---

## Best Planner State

Prefer:

```text
absolute planning timestamp
```

over:

```text
selected date
+
offset minutes
+
per-timezone calculation state
```

Keep one source of truth.

---

# 28. Success Criteria

The plugin succeeds when someone can answer:

> Can Wellington, London and New York meet tomorrow?

with:

```text
click World Clock
      ↓
choose tomorrow
      ↓
drag planning time
      ↓
watch availability indicators
      ↓
find useful time
```

in a few seconds.

The product should not be thought of as:

> another clock widget

It should be:

> **a meeting-time planner that happens to use world clocks.**
