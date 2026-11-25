#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [REAPER resource path]\n' "$0" >&2
    exit 2
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/platform.sh"

resource_path=$(reaper_resource_path "${1:-}")
target="$resource_path/UserPlugins/${plugin_path##*/}"

if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    printf 'ReaBattery is already absent from %s\n' "$resource_path"
    exit 0
fi

rm -f -- "$target"
printf 'Removed %s\nRestart REAPER if it is running.\n' "$target"
