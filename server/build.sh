#!/usr/bin/env bash
set -euo pipefail
profile=${1:?Usage: server/build.sh production|playable [output-directory]}
case "$profile" in production|playable) ;; *) exit 2 ;; esac
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output_dir=${2:-"$repo_dir/build/server-$profile"}
python3 "$repo_dir/server/prepare.py" "$profile" --output "$output_dir" --verify
extra_flags=
if [[ "$profile" == playable ]]; then
    extra_flags='-Isrc/map -Isrc/map/population_engine'
fi
make -C "$output_dir" -f Makefile.dgx -j"${BUILD_JOBS:-2}" O=build BIN=bin \
    SQLITE_LIB=-l:libsqlite3.so.0 "EXTRA_CXXFLAGS=$extra_flags" \
    bin/login-server bin/char-server bin/map-server
