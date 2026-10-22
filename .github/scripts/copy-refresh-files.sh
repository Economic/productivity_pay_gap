#!/usr/bin/env bash
# Copies the build job's files from the unpacked artifact into the checkout.
# Run by the publish job of .github/workflows/refresh.yml.
#
# The build job ran freshly updated package code, so the artifact could hold
# anything. Only regular files at the expected paths are copied. Unpacked
# straight over the checkout, a file such as .git/config could run commands
# in later git calls, with the write token present.
set -euo pipefail

artifact="$1"
allowed='^(data_raw|data_outputs|data_final)/[A-Za-z0-9_-][A-Za-z0-9._-]*$|^renv\.lock$|^renv/activate\.R$|^reports/change_report\.md$'

cd "$artifact"

# no symlinks, devices or other special files
if [ -n "$(find . ! -type d ! -type f -print -quit)" ]; then
  echo "::error::The artifact contains something other than regular files."
  exit 1
fi

files=()
while IFS= read -r -d '' path; do
  path="${path#./}"
  if ! [[ "$path" =~ $allowed ]]; then
    # %q escapes the name, so it can't inject workflow commands into the log
    printf '::error::Unexpected file in the artifact: %q\n' "$path"
    exit 1
  fi
  files+=("$path")
done < <(find . -type f -print0)

for path in "${files[@]}"; do
  mkdir -p "$GITHUB_WORKSPACE/$(dirname "$path")"
  cp "$path" "$GITHUB_WORKSPACE/$path"
done
echo "Copied ${#files[@]} files."
