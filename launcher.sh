#!/usr/bin/env bash
# Entry point for termux-dev-env. Delegates execution to src/orchestrator.sh.
set -euo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src/orchestrator.sh" "$@"