
# ReaBattery

ReaBattery shows battery level in REAPER's Transport Bar. Most useful when using on laptop in fullscreen mode.

<img width="201" height="116" alt="Screenshot 2026-11-24 at 02 04 51" src="https://github.com/user-attachments/assets/914f3752-0cbb-4cb2-ba55-0201ba0f9e2b" />
<img width="204" height="116" alt="Screenshot 2026-11-24 at 23 10 00" src="https://github.com/user-attachments/assets/e03e5319-aa49-4c9e-aadd-646970b9543c" />


Indication:
- 50-100% - green
- 20-49% - yellow
- 1-19% - red
- plugged-in - blue

## Install

Use [ReaPack](https://reapack.com/) 1.2.3.1 or later with REAPER >= 7.51

1. In REAPER, open **Extensions → ReaPack → Import repositories…** and paste the repository URL.

   ```text
   https://raw.githubusercontent.com/ll-antn/ReaBatteryReapack/main/index.xml
   ```

2. Open **Extensions → ReaPack → Browse packages…**, search for **ReaBattery**, choose **Install**, and click **Apply**.
3. Restart REAPER. Open **Extensions → ReaBattery** to adjust the indicator, or right-click it in the docked Transport Bar.

## Build from source
To get install path open REAPER and click **Options → Show REAPER resource path**

#### macOS && Linux

```sh
git clone https://github.com/justinfrankel/reaper-sdk.git third_party/reaper-sdk
git clone https://github.com/justinfrankel/WDL.git third_party/WDL
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
cmake --install build --prefix "/path/to/REAPER/resource-folder"
```

#### Windows x64

Requires Visual Studio with the **Desktop development with C++** workload and a Windows SDK

```sh
git clone https://github.com/justinfrankel/reaper-sdk.git third_party/reaper-sdk
cmake -S . -B ./build -G "Visual Studio 18 2026" -A x64
cmake --build build --config Release --parallel
cmake --install build --prefix "/path/to/REAPER/resource-folder"
```
