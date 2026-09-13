#!/usr/bin/env bash
set -euo pipefail

# Publish AppImages as GitHub release
# Requires environment variables:
#   RELEASE_NOTES - formatted release entries
#   RELEASE_NAME - fixed GitHub release tag
#   RELEASE_STATE - upstream source state marker
#   RELEASE_KIND - release or main
#   GH_TOKEN - GitHub API token
#   GITHUB_REF_NAME - branch name
#   GITHUB_SHA - commit SHA

release_date="$(date -u +%Y.%m.%d.%H%M%S)"
prerelease_flag=""
latest_flag=""
if [ "${RELEASE_KIND}" = "main" ]; then
  prerelease_flag="--prerelease"
else
  latest_flag="--latest"
fi

{
  echo "OpenSW-State: ${RELEASE_STATE}"
  echo
  echo "Unofficial AppImage for ${RELEASE_NAME}."
  echo
  echo "Versions used:"
  printf '%s\n' "$RELEASE_NOTES"
} > release-notes.md

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
