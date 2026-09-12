#!/usr/bin/env bash
set -euo pipefail

# Publish AppImages as GitHub release
# Requires environment variables:
#   RELEASES - pipe-delimited name, version, repository, description data
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
  echo "Unofficial AppImages built from the upstream releases."
  echo
  echo "Versions used:"
  while IFS='|' read -r name version repository_url description; do
    [ -n "$name" ] || continue
    printf -- '- %s: tag v%s and current main HEAD\n' "$name" "$version"
  done <<< "$RELEASES"
} > release-notes.md

gh release create "$tag" dist/* \
  --title "OpenSW AppImages ${release_date}" \
  --notes-file release-notes.md \
  --target "$GITHUB_SHA" \
  ${prerelease_flag} \
  $(if [ "${GITHUB_REF_NAME}" = "main" ]; then echo "--latest"; fi)
