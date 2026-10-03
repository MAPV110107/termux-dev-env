#!/usr/bin/env bash
# Launcher. The implementation moved under src/ (src/core.sh, src/lib,
# src/components); this stays at the project root so every documented
# command — ./core.sh, ./core.sh --dry-run, ./core.sh --reinstall=N —
# and the maintenance scripts that call them keep working unchanged.
set -euo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src/core.sh" "$@"
