case $(uname -s) in
    Darwin)
        platform=macos
        build_dir=build
        plugin_path=reaper_reabattery.dylib
        ;;
    MINGW*|MSYS*)
        platform=windows
        build_dir=build-win-x64
        plugin_path=Release/reaper_reabattery.dll
        ;;
    *)
        printf 'Use macOS or Git Bash on Windows to run this script.\n' >&2
        exit 1
        ;;
esac

reaper_resource_path() {
    if [ "$platform" = windows ]; then
        resource=${1:-"${APPDATA:?Set APPDATA or pass the REAPER resource path.}/REAPER"}
        cygpath -u -- "$resource"
    else
        printf '%s\n' "${1:-"$HOME/Library/Application Support/REAPER"}"
    fi
}
