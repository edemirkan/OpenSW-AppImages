#!/usr/bin/env bash
set -euo pipefail

# Build AppImages from release manifest
# Requires environment variables:
#   RELEASES - pipe-delimited release data
#   GITHUB_REPOSITORY - repository in owner/repo format

rm -rf build dist
mkdir -p build dist

while IFS='|' read -r name version download_url description; do
  [ -n "$name" ] || continue
  slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')"
  workdir="build/${slug}"
  appdir="${workdir}/${slug}.AppDir"
  update_scheme="gh-releases-zsync|${GITHUB_REPOSITORY//\//'|'}|latest|${slug}-${version}-x86_64.AppImage.zsync"

  mkdir -p "$appdir/usr/lib/$slug"
  curl --fail --location --silent --show-error "$download_url" --output "$workdir/release.tar.xz"
  tar --extract --file "$workdir/release.tar.xz" --directory "$appdir/usr/lib/$slug"

  executable="$(find "$appdir/usr/lib/$slug" -type f -perm /111 -print | head -n 1)"
  if [ -z "$executable" ]; then
    echo "No executable found in $download_url" >&2
    exit 1
  fi
  executable_path="${executable#"$appdir/usr/lib/$slug/"}"

  cat > "$appdir/AppRun" <<EOF
#!/bin/sh
set -e
HERE="\$(dirname "\$(readlink -f "\$0")")"
exec "\$HERE/usr/lib/$slug/$executable_path" "\$@"
EOF
  chmod +x "$appdir/AppRun"

  cat > "$appdir/$slug.desktop" <<EOF
[Desktop Entry]
Name=$name
X-AppImage-Version=$version
Comment=$description
Exec=$slug
Icon=$slug
Type=Application
Categories=Game;
EOF
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect width="256" height="256" fill="#20252b"/><text x="128" y="145" fill="white" font-size="64" text-anchor="middle">%s</text></svg>\n' "$name" > "$appdir/$slug.svg"

  ARCH=x86_64 ./appimagetool.AppImage -u "$update_scheme" "$appdir" "dist/${slug}-${version}-x86_64.AppImage"
  zsyncmake "dist/${slug}-${version}-x86_64.AppImage" \
    -o "dist/${slug}-${version}-x86_64.AppImage.zsync"
done <<< "$RELEASES"
