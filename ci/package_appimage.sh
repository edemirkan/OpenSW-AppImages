#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_NAME:?PROJECT_NAME is required}"
: "${PROJECT_SLUG:?PROJECT_SLUG is required}"
: "${APPSTREAM_ID:?APPSTREAM_ID is required}"
: "${APP_SUMMARY:?APP_SUMMARY is required}"
: "${IMAGE_VERSION:?IMAGE_VERSION is required}"
: "${DESCRIPTION:?DESCRIPTION is required}"
: "${BUILD_KIND:?BUILD_KIND is required}"
: "${EXECUTABLE_NAME:?EXECUTABLE_NAME is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${RELEASE_NAME:?RELEASE_NAME is required}"
: "${UPDATE_FILENAME:?UPDATE_FILENAME is required}"

slug="$PROJECT_SLUG"
desktop_id="$slug"
display_name="$PROJECT_NAME"
if [ "$BUILD_KIND" = main ]; then
  desktop_id="$slug-main"
  display_name="$PROJECT_NAME (main)"
fi
template_dir="packaging/linux/$slug"
workdir="build/package-$slug"
appdir="$workdir/$slug.AppDir"
artifact=$(find build/artifacts -type f -name '*.tar.xz' -print -quit)
[ -n "$artifact" ] || { echo "No build artifact found for $PROJECT_NAME ($IMAGE_VERSION)" >&2; exit 1; }
[ -f "$template_dir/AppRun" ] || { echo "Missing AppRun template: $template_dir/AppRun" >&2; exit 1; }
[ -f "$template_dir/desktop.in" ] || { echo "Missing desktop template: $template_dir/desktop.in" >&2; exit 1; }
[ -f "$template_dir/metainfo.xml.in" ] || { echo "Missing AppStream template: $template_dir/metainfo.xml.in" >&2; exit 1; }

rm -rf "$workdir"
mkdir -p "$appdir/usr/lib/$slug" "$appdir/usr/share/metainfo" dist
tar --extract --file "$artifact" --strip-components=1 --directory "$appdir/usr/lib/$slug"

executable="$appdir/usr/lib/$slug/$EXECUTABLE_NAME"
[ -n "$executable" ] || { echo "No executable found in $artifact" >&2; exit 1; }
[ -x "$executable" ] || { echo "Expected executable not found: $executable" >&2; exit 1; }
executable_path=${executable#"$appdir/usr/lib/$slug/"}

export APP_ID="$APPSTREAM_ID"
export APP_SUMMARY
export APP_DISPLAY_NAME="$display_name"
export APP_SLUG="$slug"
export DESKTOP_ID="$desktop_id"
export IMAGE_VERSION DESCRIPTION EXECUTABLE_PATH="$executable_path"

envsubst '${APP_SLUG} ${EXECUTABLE_PATH}' \
  < "$template_dir/AppRun" > "$appdir/AppRun"
chmod +x "$appdir/AppRun"

envsubst '${APP_DISPLAY_NAME} ${APP_SLUG} ${DESKTOP_ID} ${IMAGE_VERSION} ${DESCRIPTION}' \
  < "$template_dir/desktop.in" > "$appdir/$desktop_id.desktop"
envsubst '${APP_ID} ${APP_SUMMARY} ${APP_DISPLAY_NAME} ${DESCRIPTION} ${DESKTOP_ID}' \
  < "$template_dir/metainfo.xml.in" > "$appdir/usr/share/metainfo/$APPSTREAM_ID.metainfo.xml"

for size in 48 64 96 128 256 512; do
  icon="$template_dir/icon-$size.png"
  [ -f "$icon" ] || { echo "Missing icon: $icon" >&2; exit 1; }
  install -D -m 0644 "$icon" \
    "$appdir/usr/share/icons/hicolor/${size}x${size}/apps/$desktop_id.png"
done
install -m 0644 "$template_dir/icon-512.png" "$appdir/$desktop_id.png"

repository_for_update=$(printf '%s' "$GITHUB_REPOSITORY" | tr '/' '|')
update_scheme="gh-releases-zsync|$repository_for_update|$RELEASE_NAME|$UPDATE_FILENAME"
image_version="$IMAGE_VERSION"
if [ "$BUILD_KIND" = release ]; then
  image_version="v$image_version"
fi
image_name="$slug-$image_version-x86_64.AppImage"
ARCH=x86_64 ./appimagetool.AppImage -u "$update_scheme" "$appdir" "dist/$image_name"
zsyncmake "dist/$image_name" -o "dist/$image_name.zsync"
