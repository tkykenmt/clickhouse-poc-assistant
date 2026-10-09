#!/usr/bin/env bash
# Bundle every skill zip in dist/ into dist/poc-assistant-skills.zip, for a single download.
# Run after build.sh and fetch-public-skills.sh. ClickHouse Agents still takes one skill zip per upload.
set -euo pipefail
DIST="$(cd "$(dirname "$0")/.." && pwd)/dist"
rm -f "$DIST/poc-assistant-skills.zip"
(cd "$DIST" && zip -q poc-assistant-skills.zip ./*-skill.zip)
unzip -l "$DIST/poc-assistant-skills.zip"
