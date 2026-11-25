# ReaBattery

ReaBattery shows battery level and charging status in REAPER's docked Transport Bar.

## Install

Use [ReaPack](https://reapack.com/) 1.2.3.1 or later and native Apple Silicon REAPER 7.51 or later.

1. In REAPER, open **Extensions → ReaPack → Import repositories…** and paste the repository URL.

   ```text
   https://raw.githubusercontent.com/ll-antn/ReaBattery/refs/heads/main/index.xml
   ```

2. Open **Extensions → ReaPack → Browse packages…**, search for **ReaBattery**, choose **Install**, and click **Apply**.
3. Restart REAPER. Open **Extensions → ReaBattery** to adjust the indicator, or right-click it in the docked Transport Bar.

If you already imported ReaBattery and a download fails, run **Extensions → ReaPack → Synchronize packages** to refresh the repository index, then retry.

## Build from source

#### macOS

```sh
git clone https://github.com/justinfrankel/reaper-sdk.git third_party/reaper-sdk
git clone https://github.com/justinfrankel/WDL.git third_party/WDL
./scripts/build.sh
./scripts/install.sh
```

#### Windows x64

Install Git for Windows, CMake 3.21 or later, and Visual Studio 2022 with the **Desktop development with C++** workload and a Windows SDK. Quit REAPER before installing or uninstalling the plugin. Run these commands in Git Bash from the repository root.

```sh
git clone https://github.com/justinfrankel/reaper-sdk.git third_party/reaper-sdk
./scripts/build.sh
./scripts/install.sh
```

The build writes `build-win-x64/Release/reaper_reabattery.dll`. The installer copies it to `%APPDATA%\REAPER\UserPlugins` by default. Start REAPER to load the plugin.

### Uninstall a manual installation

Run `./scripts/uninstall.sh` on macOS or in Git Bash on Windows. For portable REAPER, pass its resource path as the first argument to `install.sh` or `uninstall.sh`. Quote the path if it contains spaces.
