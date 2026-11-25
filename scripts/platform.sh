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
    Linux)
        platform=linux
        build_dir=build
        plugin_path=reaper_reabattery.so
        ;;
    *)
        printf 'Use macOS, Git Bash on Windows, or Linux to run this script.\n' >&2
        exit 1
        ;;
esac

reaper_resource_path() {
    case "$platform" in
        windows)
            resource=${1:-"${APPDATA:?Set APPDATA or pass the REAPER resource path.}/REAPER"}
            cygpath -u -- "$resource"
            ;;
        macos)
            printf '%s\n' "${1:-"$HOME/Library/Application Support/REAPER"}"
            ;;
        linux)
            printf '%s\n' "${1:-"${XDG_CONFIG_HOME:-"$HOME/.config"}/REAPER"}"
            ;;
    esac
}
