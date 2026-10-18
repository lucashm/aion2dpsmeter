# Changelog

## Unreleased

- Pet souls widget: up to 5 pets you're picking up souls for, each with its portrait, level, progress, souls per minute and time to the next level and to full; each goes 5 minutes after its last soul
- App window (tray → Open app, or `aion2-meter app`) with three pages:
  - Pets: every pet with your level and souls, by phase (collect, level 2, level 3), genus and the areas you farm, with collection progress, genus insight levels (read from the game), the next reward, and estimated levels marked
  - Map: where pets spawn, as their portraits on Verteron, Altgard and the Abyss (tiles, spawns and zones from Arkive), with a panel to pick the map and the pets and a card on hover; a pet's map icon on the Pets page opens it on that pet, ticking its genus if needed; when the filters hide everything, the filter that would show pets blinks; only the tiles on screen load, and closing the map lets them go
  - Analytics: past runs grouped by player, class, boss or run, with filters, sorting, a DPS-per-run chart and best runs

## 0.1.0

First public release.

- Live DPS meter, skill breakdown, boss HP and ping widgets drawn over the game
- Saved boss fights with a history panel (damage or DPS view)
- Customize panel (tray menu or Ctrl+`): widget toggles, monitor, meter target, snap grid, size and opacity
- Three saved layouts, and a default layout that fits any 16:9 or 21:9 screen
- Optional dragging of widgets in game while Alt frees the cursor (off by default)
- In-game shortcuts, Ctrl+` for Customize and Alt+` to hide or show the widgets, changeable in Customize
- Tray icon and app menu entry to control the meter
- Works on Hyprland; other Wayland desktops through the standard window list
- Static release binaries for any x86_64 Linux
