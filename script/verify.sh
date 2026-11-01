#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PYTHON="${PYTHON:-.venv/bin/python}"
if [[ ! -x "$PYTHON" ]]; then
    echo 'Create .venv and install the test extras: python3 -m venv .venv; .venv/bin/python -m pip install -e ".[google-tasks]"' >&2
    exit 1
fi
"$PYTHON" -B -m unittest discover -s tests -v
swift test
./script/build_and_run.sh --build
git diff --check
