#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [REAPER resource path]\n' "$0" >&2
    exit 2
fi

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_dir/scripts/platform.sh"

resource_path=$(reaper_resource_path "${1:-}")
plugin_name=${plugin_path##*/}
source="$project_dir/$build_dir/$plugin_path"
if [ ! -f "$source" ]; then
    source="$project_dir/UserPlugins/$plugin_name"
fi
if [ ! -f "$source" ]; then
    printf 'ReaBattery binary is missing. Build the extension first.\n' >&2
    exit 1
fi

plugin_dir="$resource_path/UserPlugins"
target="$plugin_dir/$plugin_name"
mkdir -p -- "$plugin_dir"
if [ -d "$target" ]; then
    printf 'The install file path is a directory: %s\n' "$target" >&2
    exit 1
fi

# Stage the copy beside the target so an interrupted install leaves the old binary intact.
temporary=$(mktemp "$plugin_dir/.reaper_reabattery.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
trap 'exit 1' HUP INT TERM
install -m 755 -- "$source" "$temporary"
mv -f -- "$temporary" "$target"
printf 'Installed %s\nRestart REAPER to load ReaBattery.\n' "$target"
