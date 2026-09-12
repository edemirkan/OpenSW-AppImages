#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_NAME:?PROJECT_NAME is required}"
: "${IMAGE_VERSION:?IMAGE_VERSION is required}"
: "${DESCRIPTION:?DESCRIPTION is required}"
: "${BUILD_KIND:?BUILD_KIND is required}"
: "${EXECUTABLE_NAME:?EXECUTABLE_NAME is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${UPDATE_FILENAME:?UPDATE_FILENAME is required}"

slug=$(printf '%s' "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')
desktop_id="$slug"
display_name="$PROJECT_NAME"
if [ "$BUILD_KIND" = main ]; then
  desktop_id="$slug-main"
  display_name="$PROJECT_NAME (main)"
fi
workdir="build/package-$slug"
appdir="$workdir/$slug.AppDir"
artifact=$(find build/artifacts -type f -name '*.tar.xz' -print -quit)
[ -n "$artifact" ] || { echo "No build artifact found for $PROJECT_NAME ($IMAGE_VERSION)" >&2; exit 1; }

rm -rf "$workdir"
mkdir -p "$appdir/usr/lib/$slug" dist
tar --extract --file "$artifact" --strip-components=1 --directory "$appdir/usr/lib/$slug"

executable="$appdir/usr/lib/$slug/$EXECUTABLE_NAME"
[ -n "$executable" ] || { echo "No executable found in $artifact" >&2; exit 1; }
[ -x "$executable" ] || { echo "Expected executable not found: $executable" >&2; exit 1; }
executable_path=${executable#"$appdir/usr/lib/$slug/"}

printf '%s\n' '#!/bin/sh' 'set -e' \
  'HERE="$(dirname "$(readlink -f "$0")")"' \
  "exec \"\$HERE/usr/lib/$slug/$executable_path\" \"\$@\"" \
  > "$appdir/AppRun"
chmod +x "$appdir/AppRun"

printf '%s\n' '[Desktop Entry]' "X-AppImage-Version=$IMAGE_VERSION" \
  "Comment=$DESCRIPTION" \
  "Name=$display_name" "Exec=$slug" "Icon=$desktop_id" \
  'Type=Application' 'Categories=Game;' \
  > "$appdir/$desktop_id.desktop"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect width="256" height="256" fill="#20252b"/><text x="128" y="145" fill="white" font-size="64" text-anchor="middle">%s</text></svg>\n' "$display_name" > "$appdir/$desktop_id.svg"

repository_for_update=$(printf '%s' "$GITHUB_REPOSITORY" | tr '/' '|')
update_scheme="gh-releases-zsync|$repository_for_update|latest|$UPDATE_FILENAME"
image_name="$slug-$IMAGE_VERSION-x86_64.AppImage"
ARCH=x86_64 ./appimagetool.AppImage -u "$update_scheme" "$appdir" "dist/$image_name"
zsyncmake "dist/$image_name" -o "dist/$image_name.zsync"
