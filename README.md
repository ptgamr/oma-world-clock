# Omarchy World Clock

A standalone world-clock and meeting-planner plugin for the Omarchy Quattro bar. It is designed to live beside the built-in `omarchy.clock`, not replace it.

## UI evolution

| v1 — clocks first | v2 — calendar first |
| --- | --- |
| [![v1 clocks-first panel](screenshots/world-clock-panel-v1.png)](screenshots/world-clock-panel-v1.png) | [![v2 calendar-first panel](screenshots/world-clock-panel-v2.png)](screenshots/world-clock-panel-v2.png) |
| v3 — compact | v4 — analog day/night |
| [![v3 compact panel](screenshots/world-clock-panel-v3.png)](screenshots/world-clock-panel-v3.png) | [![v4 analog day-night panel](screenshots/world-clock-panel-v4.png)](screenshots/world-clock-panel-v4.png) |

**v5 — aligned analog faces with seconds hand**

[![v5 aligned analog clocks with red seconds hand](screenshots/world-clock-panel-v5.png)](screenshots/world-clock-panel-v5.png)

**v6 — weekday and timezone columns**

[![v6 weekday and timezone columns](screenshots/world-clock-panel-v6.png)](screenshots/world-clock-panel-v6.png)

**v7 — simplified rows and appearance settings**

[![v7 simplified rows and appearance settings](screenshots/world-clock-panel-v7.png)](screenshots/world-clock-panel-v7.png)

**v8 — square appearance switch**

[![v8 square appearance switch](screenshots/world-clock-panel-v8.png)](screenshots/world-clock-panel-v8.png)

**v9 — timezone-aware three-clock first run (current)**

[![v9 timezone-aware first-run defaults](screenshots/world-clock-panel-v9.png)](screenshots/world-clock-panel-v9.png)

New UI captures increment the suffix (`v10`, `v11`, …) so earlier layouts remain available for comparison.

Version 0.1 includes:

- multiple named IANA timezones with one home location
- three-continent first-run defaults based on the machine's local timezone
- DST-correct conversion for the selected instant
- a ±12 hour planner with 15-minute snapping
- local-calendar date navigation that remains correct across DST changes
- aligned analog faces with light/day, dark/night dials and a live red seconds hand
- full local weekdays and aligned timezone details beneath each digital clock
- appearance settings for analog visibility and 12/24-hour time
- add, remove, rename, reorder, and set-home controls
- timezone search backed by the installed system timezone database
- configuration persistence in this plugin's own `shell.json` bar entry

## Requirements

- Omarchy 4 / Quattro
- Python 3.9 or newer with `zoneinfo`
- installed system timezone data (`tzdata` on Arch Linux)

The plugin runs `helpers/timezone.py` locally with fixed argument arrays. It does not use the network, start a service, request privileges, or execute a shell.

## Install

After publishing the repository:

```sh
omarchy plugin add https://github.com/ptgamr/oma-world-clock.git --enable
```

The manifest defaults to the right section so the normal Omarchy clock can remain in the center. Move it at any time with:

```sh
omarchy bar move io.github.ptgamr.world-clock --section right
```

## Use

Click the world-clock count in the bar to open the planner. On first run the
plugin detects the machine's IANA timezone, puts it first as `HOME`, and adds
two representative clocks from other regions:

- Asia home: Berlin and New York
- Europe home: Ho Chi Minh and New York
- Americas home: Berlin and Ho Chi Minh
- Africa home: Berlin and Ho Chi Minh
- Oceania home: Ho Chi Minh and New York
- UTC or an unclassified timezone: Berlin and Ho Chi Minh

This produces three clocks in three different regions. The result is saved as
normal location configuration, so detection runs only once and never replaces
locations the user has already configured.

- Drag or scroll the slider to move all clocks in 15-minute steps.
- Press Left/Right for 15 minutes; hold Shift for one hour.
- Press `T` or click `NOW` to return to the live current instant.
- Click a day in the calendar strip to plan on that home-timezone date.
- Use the calendar arrows to move one week at a time, or click `Today` to return.
- Click `Manage` to rename, reorder, remove, or change the home location.
- Click `Settings` to show or hide analog clocks and choose 12- or 24-hour time.
- To change the home location later, click `Manage`, click `Home` on its row, then click `Done`.
- Click `Add location` and search by a city such as `London` or an IANA ID such as `Europe/London`.

## Validate

```sh
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
python -m unittest discover -s tests
node tests/model-test.js
```

For a reviewer screenshot of the loaded panel while the session is unlocked,
ask the running widget to capture only its own QML content:

```sh
omarchy-shell io.github.ptgamr.world-clock capturePreview
# writes /tmp/omarchy-world-clock-preview.png
```

If the widget was just hot-reloaded and its old IPC handler is still retiring,
the equivalent bar-setting trigger is:

```sh
omarchy-shell shell setBarWidget io.github.ptgamr.world-clock _capturePreview true '{}'
# reset the one-shot trigger after the file is written
omarchy-shell shell setBarWidget io.github.ptgamr.world-clock _capturePreview false '{}'
```

A secure compositor lock can prevent the popup surface from mapping. The
checked-in screenshot was therefore rendered offscreen from the same panel
layout, current Omarchy theme values, and timezone-helper output.

## Configuration

Locations are written into this widget's own entry in `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.ptgamr.world-clock",
  "showAnalogClock": true,
  "hourFormat": "12",
  "locations": [
    {
      "id": "auckland",
      "name": "Auckland",
      "timezone": "Pacific/Auckland",
      "isHome": true
    },
    {
      "id": "ho-chi-minh",
      "name": "Ho Chi Minh",
      "timezone": "Asia/Ho_Chi_Minh",
      "isHome": false
    },
    {
      "id": "new-york",
      "name": "New York",
      "timezone": "America/New_York",
      "isHome": false
    }
  ]
}
```

No settings or files belonging to `omarchy.clock` are read or modified.
