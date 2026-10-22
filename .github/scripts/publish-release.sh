#!/usr/bin/env bash
# Publishes a release. Run by the release job of .github/workflows/release.yml,
# in a checkout of the commit to release, after the plan job chose the tag and
# the check passed on that commit. See "Release flow" in
# plans/2026-10-21-ci-data-release-workflow.md.
#
# Environment: SHA, TAG, TITLE, PREVIOUS_TAG, LATEST_QUARTER, DRY_RUN and
# CORRECTION ("true" or "false"), REASON, and REPORT (path to the change
# report, which may be missing).
set -euo pipefail

files=(
  data_final/epi_productivity_pay_gap.csv
  data_final/epi_productivity_pay_gap_web.csv
  data_final/epi_productivity_pay_gap_web_stats.csv
  data_final/epi_productivity_pay_gap_sources.csv
)

notes=$(mktemp)
{
  if [ "$CORRECTION" = "true" ]; then
    echo "Correction to $PREVIOUS_TAG: $REASON"
    echo
  fi
  echo "Latest updates through $LATEST_QUARTER"
  echo
  if [ -f "$REPORT" ]; then
    cat "$REPORT"
  else
    echo "The change report could not be built; see the check job of this run."
  fi
} > "$notes"

if [ "$DRY_RUN" = "true" ]; then
  {
    echo "## Dry run: would publish $TAG on commit ${SHA:0:7}"
    echo
    echo "Title: $TITLE"
    echo
    cat "$notes"
  } >> "$GITHUB_STEP_SUMMARY"
  echo "Dry run: would publish $TAG on ${SHA:0:7}."
  exit 0
fi

assets=("${files[@]}")
if [ -f "$REPORT" ]; then
  cp "$REPORT" change_report.md
  assets+=(change_report.md)
fi

# Until the release is published, any failure deletes the draft and the tag,
# so nothing half-made stays behind. Published releases are never touched.
published=false
cleanup() {
  if [ "$published" != "true" ]; then
    gh release delete "$TAG" --yes 2>/dev/null || true
    gh api -X DELETE "repos/$GITHUB_REPOSITORY/git/refs/tags/$TAG" 2>/dev/null || true
  fi
}

# The tag first, on the checked commit, through the API: it refuses a tag
# that already exists, while gh release create would reuse one
gh api "repos/$GITHUB_REPOSITORY/git/refs" -f ref="refs/tags/$TAG" -f sha="$SHA" > /dev/null
trap cleanup EXIT

gh release create "$TAG" --verify-tag --draft --title "$TITLE" --notes-file "$notes" "${assets[@]}"

# Before publishing: the tag points at the checked commit, and every attached
# file is byte for byte the file in the checkout
tagged=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$TAG" --jq .object.sha)
if [ "$tagged" != "$SHA" ]; then
  echo "::error::The tag $TAG points at $tagged, not $SHA."
  exit 1
fi
downloaded=$(mktemp -d)
gh release download "$TAG" --dir "$downloaded"
for asset in "${assets[@]}"; do
  if ! cmp -s "$asset" "$downloaded/$(basename "$asset")"; then
    echo "::error::The uploaded $(basename "$asset") differs from the file in the checkout."
    exit 1
  fi
done

gh release edit "$TAG" --draft=false --latest
published=true
echo "Published $TAG on ${SHA:0:7}: https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG"
