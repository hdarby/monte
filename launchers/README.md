# Launchers

Double-clickable, for when you just want to play rather than think about Flutter.

| File | What it does |
|---|---|
| **Play Monte** | Release build on macOS. Fast, smooth, no debugger. This is the one. |
| **Debug Monte** | Hot reload and breakpoints, slower to run. |
| **Monte in Browser** | Release build in Chrome. |
| **Run All Tests** | The full suite (~7 minutes). |
| **Create Player** | The interactive player creator, in a real terminal — it cannot run in a debug console. |

Drag any of them to the Dock for a permanent icon. To change the icon itself:
select the file in Finder, ⌘I, click the small icon top-left, and paste an image.

All of them are one-liners over `../run.sh`, which is where the actual logic
lives — so there is one place to fix if something breaks.
