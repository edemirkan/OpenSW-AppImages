#!/usr/bin/env bash
set -euo pipefail

# Publish AppImages as GitHub release
# Requires environment variables:
#   RELEASE_NAME - fixed GitHub release tag
#   RELEASE_TITLE_NAME - original project name from meta.yml
#   RELEASE_TITLE_VALUE - release tag or main@sha
#   RELEASE_STATE - release name and upstream source state marker
#   PACKAGE_BRANCH - branch in the packaging repository
#   GH_TOKEN - GitHub API token
#   GITHUB_SHA - commit SHA

printf '%s\n' "$RELEASE_STATE" > release-notes.md
release_title="${RELEASE_TITLE_NAME} ${RELEASE_TITLE_VALUE}"

if gh release view "$RELEASE_NAME" >/dev/null 2>&1; then
  if [ "${PACKAGE_BRANCH}" = "main" ]; then
    gh release edit "$RELEASE_NAME" --prerelease=false
    gh release edit "$RELEASE_NAME" \
      --title "$release_title" \
      --notes-file release-notes.md
  else
    gh release edit "$RELEASE_NAME" \
      --title "$release_title" \
      --notes-file release-notes.md \
      --prerelease
  fi
  gh release upload "$RELEASE_NAME" dist/* --clobber
else
  if [ "${PACKAGE_BRANCH}" = "main" ]; then
    gh release create "$RELEASE_NAME" dist/* \
      --title "$release_title" \
      --notes-file release-notes.md \
      --target "$GITHUB_SHA"
  else
    gh release create "$RELEASE_NAME" dist/* \
      --title "$release_title" \
      --notes-file release-notes.md \
      --target "$GITHUB_SHA" \
      --prerelease
  fi
fi
