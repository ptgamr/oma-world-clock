# Omarchy World Clock

A standalone world-clock and meeting-planner plugin for the Omarchy Quattro bar. It is designed to live beside the built-in `omarchy.clock`, not replace it.

Version 0.1 includes:

- multiple named IANA timezones with one home location
- DST-correct conversion for the selected instant
- a ±12 hour planner with 15-minute snapping
- local-calendar date navigation that remains correct across DST changes
- working-hours, edge-hours, and off-hours indicators
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

Click the world-clock count in the bar to open the planner. The initial set
contains Wellington, London, New York, Ho Chi Minh, Berlin, Hanoi, and Pacific
Time (`America/Los_Angeles`, so it follows PST/PDT automatically).

- Drag or scroll the slider to move all clocks in 15-minute steps.
- Press Left/Right for 15 minutes; hold Shift for one hour.
- Press `T` or click `NOW` to return to the live current instant.
- Use the date arrows to plan on another local calendar date in the home timezone.
- Click `Manage` to rename, reorder, remove, or change the home location.
- Click `Add location` and search by a city such as `London` or an IANA ID such as `Europe/London`.

Green/theme-accent `WORK` means Monday-Friday 09:00-17:00, `EDGE` means 07:00-09:00 or 17:00-20:00, and `OFF` covers nights and weekends.

## Validate

```sh
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
python -m unittest discover -s tests
node tests/model-test.js
```

For a reviewer screenshot of the real loaded panel—even when the desktop is
locked—ask the running widget to capture only its own QML content:

```sh
omarchy-shell io.github.ptgamr.world-clock capturePreview
# writes /tmp/omarchy-world-clock-preview.png
```

## Configuration

Locations are written into this widget's own entry in `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.ptgamr.world-clock",
  "locations": [
    {
      "id": "home",
      "name": "Wellington",
      "timezone": "Pacific/Auckland",
      "isHome": true
    }
  ]
}
```

No settings or files belonging to `omarchy.clock` are read or modified.
