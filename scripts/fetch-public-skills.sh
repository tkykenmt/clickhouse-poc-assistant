#!/usr/bin/env bash
# Download public ClickHouse skills (ClickHouse/agent-skills, Apache-2.0) unmodified, pinned to a commit,
# and zip each one into dist/ for upload to ClickHouse Agents.
set -euo pipefail
REPO="ClickHouse/agent-skills"
SHA="${AGENT_SKILLS_SHA:-356a8c1b9a7392adb389a132f5ad3fec38532a03}"
SKILLS=(clickhouse-architecture-advisor)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$ROOT/dist"
curl -sSL "https://codeload.github.com/$REPO/tar.gz/$SHA" | tar -xz -C "$TMP"
src="$(ls -d "$TMP"/agent-skills-*)"
for s in "${SKILLS[@]}"; do
  # Apache-2.0 requires a copy of the license with redistributed files.
  cp "$src/LICENSE" "$src/skills/$s/LICENSE"
  (cd "$src/skills" && zip -qr "$ROOT/dist/$s-skill.zip" "$s")
  echo "dist/$s-skill.zip from $REPO@${SHA:0:12}"
done
