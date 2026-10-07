#!/usr/bin/env bash
# Scaffold a new box writeup folder from _template/.
# Usage: ./new-box.sh "BoxName"
set -euo pipefail

name="${1:-}"
if [[ -z "$name" ]]; then
  echo "usage: $0 \"BoxName\"" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")" && pwd)"
dest="$root/$name"

if [[ -e "$dest" ]]; then
  echo "error: $name/ already exists" >&2
  exit 1
fi

cp -R "$root/_template" "$dest"
# drop the .gitkeep placeholders now that the dirs are real
rm -f "$dest/exploits/.gitkeep" "$dest/screenshots/.gitkeep"
mkdir -p "$dest/exploits" "$dest/screenshots"

echo "created $name/"
echo "next:"
echo "  1. write $name/README.md"
echo "  2. drop scripts in $name/exploits/ , images in $name/screenshots/"
echo "  3. add a row to the Boxes + Techniques tables in the top-level README.md"
