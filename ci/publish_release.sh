#!/usr/bin/env bash
set -euo pipefail

# Publish AppImages to the persistent latest GitHub release.
# Requires environment variables:
#   RELEASE_NAME - fixed GitHub release tag (latest)
#   PROJECT_SLUG - project asset-name prefix
#   BUILD_KIND - main or release
#   GH_TOKEN - GitHub API token
#   GITHUB_SHA - commit SHA

if ! gh release view "$RELEASE_NAME" >/dev/null 2>&1; then
  gh release create "$RELEASE_NAME" \
    --title "static OpenSW-AppImages" \
    --notes "Latest AppImages for all supported OpenSW projects." \
    --target "$GITHUB_SHA" \
    || gh release view "$RELEASE_NAME" >/dev/null
fi
gh release upload "$RELEASE_NAME" dist/* --clobber

case "$BUILD_KIND" in
  main) asset_prefix="$PROJECT_SLUG-main-" ;;
  release) asset_prefix="$PROJECT_SLUG-v" ;;
  *) echo "Unsupported build kind: $BUILD_KIND" >&2; exit 1 ;;
esac

current_assets=()
for asset in dist/*; do
  current_assets+=("$(basename "$asset")")
done

while IFS= read -r published_asset; do
  case "$published_asset" in
    "$asset_prefix"*)
      keep_asset=false
      for current_asset in "${current_assets[@]}"; do
        if [ "$published_asset" = "$current_asset" ]; then
          keep_asset=true
          break
        fi
      done
      if [ "$keep_asset" = false ]; then
        gh release delete-asset "$RELEASE_NAME" "$published_asset" --yes
      fi
      ;;
  esac
done < <(gh release view "$RELEASE_NAME" --json assets --jq '.assets[].name')
