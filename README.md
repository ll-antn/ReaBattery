# ReaBattery

ReaBattery shows your MacBook’s battery percentage at the right edge of REAPER’s Transport Bar. It updates automatically and follows the bar when it is docked in the main window. Apple Silicon and native REAPER 7.51 or later are required.

| Battery state | Color |
| --- | --- |
| Plugged in, including when fully charged | Blue |
| 50–100% on battery | Green |
| 20–49% on battery | Yellow |
| 0–19% on battery | Red |

The indicator appears with the main-window Transport Bar when there is room for it. To put it at the bottom edge, right-click the Transport Bar and choose **Dock transport in main window**, then **Docked transport position → Bottom of main window**.

Right-click the battery icon and uncheck **Show Percentage** to display just the icon. Check **Show Only in Fullscreen** to hide the indicator whenever the main REAPER window leaves fullscreen. To turn the setting off, enter fullscreen and uncheck it from the same menu. REAPER remembers both settings after a restart.

**Show when plugged-in** is on by default. Uncheck it to show the indicator only when your Mac is running on battery. To turn it back on, disconnect external power and check it in the same menu. REAPER remembers this setting.

Use **Position** in the battery menu to choose **Right Corner** (the default), **Left Corner**, or **Center**. Center places the indicator next to the time display and falls back to the right corner when the display is hidden or too narrow. REAPER remembers your choice.

## Build and install

Run these commands from the project directory on an Apple Silicon Mac with CMake and Xcode Command Line Tools.

```sh
git clone https://github.com/justinfrankel/reaper-sdk.git third_party/reaper-sdk
git clone https://github.com/justinfrankel/WDL.git third_party/WDL
./scripts/build.sh
./scripts/install.sh
```

If you downloaded the prebuilt archive, run `./scripts/install.sh` from the extracted directory. For a portable installation, pass its resource path as the first argument. You can find it under **Options → Show REAPER resource path in explorer/finder**. Restart REAPER after installing.

To uninstall, quit REAPER and remove `reaper_reabattery.dylib` from `UserPlugins`.
