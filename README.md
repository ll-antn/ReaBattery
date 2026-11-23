# ReaBattery

ReaBattery shows battery level and charging status in REAPER's docked Transport Bar.

## Install

Use [ReaPack](https://reapack.com/) 1.2.3.1 or later with REAPER >= 7.51

1. In REAPER, open **Extensions → ReaPack → Import repositories…** and paste the repository URL.

   ```text
   https://raw.githubusercontent.com/ll-antn/ReaBatteryReapack/main/index.xml
   ```

2. Open **Extensions → ReaPack → Browse packages…**, search for **ReaBattery**, choose **Install**, and click **Apply**.
3. Restart REAPER. Open **Extensions → ReaBattery** to adjust the indicator, or right-click it in the docked Transport Bar.

## Build from source

#### macOS

```sh
git clone https://github.com/justinfrankel/reaper-sdk.git third_party/reaper-sdk
git clone https://github.com/justinfrankel/WDL.git third_party/WDL
./scripts/build.sh
./scripts/install.sh
```
