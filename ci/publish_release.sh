#!/usr/bin/env bash
set -euo pipefail

# Publish AppImages as GitHub release
# Requires environment variables:
#   RELEASE_NOTES - formatted release entries
#   GH_TOKEN - GitHub API token
#   GITHUB_REF_NAME - branch name
#   GITHUB_SHA - commit SHA

release_date="$(date -u +%Y.%m.%d.%H%M%S)"
tag="appimages-${release_date}-${GITHUB_SHA::7}"
prerelease_flag=""
if [ "${GITHUB_REF_NAME}" != "main" ]; then
  prerelease_flag="--prerelease"
fi

{
  printf '%s\n' "$RELEASE_NOTES"
} > release-notes.md

gh release create "$tag" dist/* \
  --title "OpenSW AppImages ${release_date}" \
  --notes-file release-notes.md \
  --target "$GITHUB_SHA" \
  ${prerelease_flag} \
  $(if [ "${GITHUB_REF_NAME}" = "main" ]; then echo "--latest"; fi)
