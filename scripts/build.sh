#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_dir/scripts/platform.sh"

if [ "$platform" = windows ]; then
    project_dir=$(cygpath -m -- "$project_dir")
    cmake -S "$project_dir" -B "$project_dir/$build_dir" -G "Visual Studio 17 2022" -A x64 "$@"
    cmake --build "$project_dir/$build_dir" --config Release --parallel
else
    cmake -S "$project_dir" -B "$project_dir/$build_dir" -DCMAKE_BUILD_TYPE=Release "$@"
    cmake --build "$project_dir/$build_dir" --parallel
fi
