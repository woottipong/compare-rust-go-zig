#!/bin/bash
# Default benchmark wrapper — runs Profile B (multi-scenario k6 throughput test).
# To run Profile A (wrk latency / high-concurrency) use: bash benchmark/run-profile-a.sh

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec bash "$SCRIPT_DIR/run-profile-b.sh" "$@"
