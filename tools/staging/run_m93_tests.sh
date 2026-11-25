#!/usr/bin/env bash
set -euo pipefail
mode=${1:?m93 or m93asan}
case "$mode" in m93|m93asan) ;; *) exit 2;; esac
docker exec "ragoff-companion-$mode" python3 /tests/check_m93.py
docker exec "ragoff-companion-$mode" python3 /tests/check_m93_faults.py
