# Changelog

## Unreleased

- Pet souls widget: up to 5 pets you're picking up souls for, each with its portrait, level, progress, souls per minute and time to the next level and to full; each goes 5 minutes after its last soul
- App window (tray → Open app, or `aion2-meter app`) with four pages:
  - Pets: every pet with your level and souls, by phase (collect, level 2, level 3), genus and the areas you farm, with collection progress, genus insight levels (read from the game), the next reward, and estimated levels marked
  - Map: where pets spawn, as their portraits on Verteron, Altgard and the Abyss (tiles, spawns and zones from Arkive), opening on your faction's map (Altgard for Asmodians, Verteron for Elyos), with a panel to pick the map and the pets and a card on hover; a pet's map icon on the Pets page opens it on that pet (on your faction's map when the pet spawns there too), ticking its genus if needed; when the filters hide everything, the filter that would show pets blinks; only the tiles on screen load, and closing the map lets them go; a Cube spots (partial) layer shows some of the spots where Verteron's and Altgard's hidden cubes can spawn
  - Notifications: turn in-game alerts on or off, and show a test one
  - Analytics: past runs grouped by player, class, boss or run, with filters, sorting, a DPS-per-run chart and best runs
- Hidden cube alerts: a banner and a chime at the top of the screen when a cube comes within about 100 m, and when someone else opens it (with their name when the game gave it, else just that it's being opened; the distance updates as you move); the nearby alert only shows while you have a Hidden Cube Key, read from your bag at login; every cube seen is saved as a spawn spot and shown on the Map page (Cubes seen by the meter), with the cube in range right now pulsing
- Event reminders: a countdown banner and a chime 1, 3, 5 or 10 minutes before the Shugo Festival (every hour at :00) and the Dimensional Invasion (every hour at :30), each turned on or off on the Notifications page
- Cube alerts and event reminders only show (and chime) while the overlay's widgets are on, and reminders only while the game is open; each has a ✕ to close it
- The chime is a softer, lower two-note tone
- Running the installer again to update only asks for sudo when the daemon changed
- The installer finds missing dependencies (Quickshell, setcap, Qt's image formats, curl, Noto Sans) and offers to install them with your package manager

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
