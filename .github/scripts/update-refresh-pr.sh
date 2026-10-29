#!/usr/bin/env bash
# The publish job runs this trusted helper, never R or code from the artifact.
set -euo pipefail
python3 "$(dirname "$0")/update-refresh-pr.py"
