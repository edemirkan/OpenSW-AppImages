#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_NAME:?PROJECT_NAME is required}"
: "${IMAGE_VERSION:?IMAGE_VERSION is required}"
: "${DESCRIPTION:?DESCRIPTION is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${UPDATE_FILENAME:?UPDATE_FILENAME is required}"

slug=$(printf '%s' "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')
workdir="build/package-$slug"
appdir="$workdir/$slug.AppDir"
artifact=$(find build/artifacts -type f -name '*.tar.xz' -print -quit)
[ -n "$artifact" ] || { echo "No build artifact found for $PROJECT_NAME ($IMAGE_VERSION)" >&2; exit 1; }

rm -rf "$workdir"
mkdir -p "$appdir/usr/lib/$slug" dist
tar --extract --file "$artifact" --strip-components=1 --directory "$appdir/usr/lib/$slug"

executable=$(find "$appdir/usr/lib/$slug" -type f -perm /111 -print | head -n 1)
[ -n "$executable" ] || { echo "No executable found in $artifact" >&2; exit 1; }
executable_path=${executable#"$appdir/usr/lib/$slug/"}

printf '%s\n' '#!/bin/sh' 'set -e' \
  'HERE="$(dirname "$(readlink -f "$0")")"' \
  "exec \"\$HERE/usr/lib/$slug/$executable_path\" \"\$@\"" \
  > "$appdir/AppRun"
chmod +x "$appdir/AppRun"

printf '%s\n' '[Desktop Entry]' "Name=$PROJECT_NAME" \
  "X-AppImage-Version=$IMAGE_VERSION" "Comment=$DESCRIPTION" \
  "Exec=$slug" "Icon=$slug" 'Type=Application' 'Categories=Game;' \
  > "$appdir/$slug.desktop"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect width="256" height="256" fill="#20252b"/><text x="128" y="145" fill="white" font-size="64" text-anchor="middle">%s</text></svg>\n' "$PROJECT_NAME" > "$appdir/$slug.svg"

repository_for_update=$(printf '%s' "$GITHUB_REPOSITORY" | tr '/' '|')
update_scheme="gh-releases-zsync|$repository_for_update|latest|$UPDATE_FILENAME"
image_name="$slug-$IMAGE_VERSION-x86_64.AppImage"
ARCH=x86_64 ./appimagetool.AppImage -u "$update_scheme" "$appdir" "dist/$image_name"
zsyncmake "dist/$image_name" -o "dist/$image_name.zsync"
