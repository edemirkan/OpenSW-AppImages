#!/usr/bin/env bash
set -euo pipefail

# Publish AppImages as GitHub release
# Requires environment variables:
#   RELEASE_NAME - fixed GitHub release tag
#   RELEASE_STATE - release name and upstream source state marker
#   PACKAGE_BRANCH - branch in the packaging repository
#   GH_TOKEN - GitHub API token
#   GITHUB_SHA - commit SHA

release_date="$(date -u +%Y.%m.%d.%H%M%S)"
prerelease_flag=""
latest_flag=""
if [ "${PACKAGE_BRANCH}" = "main" ]; then
  latest_flag="--latest"
else
  prerelease_flag="--prerelease"
fi

printf '%s\n' "$RELEASE_STATE" > release-notes.md

if gh release view "$RELEASE_NAME" >/dev/null 2>&1; then
  gh release edit "$RELEASE_NAME" \
    --title "${RELEASE_NAME} (${release_date})" \
    --notes-file release-notes.md \
    ${prerelease_flag} ${latest_flag}
  gh release upload "$RELEASE_NAME" dist/* --clobber
else
  gh release create "$RELEASE_NAME" dist/* \
    --title "${RELEASE_NAME} (${release_date})" \
    --notes-file release-notes.md \
    --target "$GITHUB_SHA" \
    ${prerelease_flag} ${latest_flag}
fi
