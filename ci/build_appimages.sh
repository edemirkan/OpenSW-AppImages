#!/usr/bin/env bash
set -euo pipefail

rm -rf build dist
mkdir -p build dist

while IFS='|' read -r name version repository_url description; do
  [ -n "$name" ] || continue
  slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')

  case "$slug" in
    opentie) project_prefix=TIE ;;
    openxwa) project_prefix=XWA ;;
    *) echo "Unsupported project name: $name" >&2; exit 1 ;;
  esac

  source_dir="build/source-$slug"
  git clone --recurse-submodules "$repository_url" "$source_dir"
  tag_ref="v$version"
  tag_sha=$(git -C "$source_dir" rev-parse "$tag_ref^{commit}")
  main_sha=$(git -C "$source_dir" rev-parse origin/main^{commit})

  for build_kind in release git; do
    if [ "$build_kind" = release ]; then
      ref=$tag_ref
      image_version=$version
      update_filename="$slug-*-x86_64.AppImage.zsync"
    else
      ref=origin/main
      image_version="git-${main_sha:0:7}"
      update_filename="$slug-git-*-x86_64.AppImage.zsync"
    fi

    git -C "$source_dir" checkout --force "$ref"
    git -C "$source_dir" submodule update --init --recursive

    workdir="build/$slug-$build_kind"
    artifact_dir="$workdir/artifacts"
    appdir="$workdir/$slug.AppDir"
    mkdir -p "$artifact_dir" "$appdir/usr/lib/$slug"

    build_args=(
      --build-arg "${project_prefix}_BUILD_TYPE=Release"
      --build-arg "${project_prefix}_VERSION=$image_version"
    )
    cache_args=(--cache-from "type=gha,scope=linux-$slug")
    if [ -n "${DOCKER_CACHE_TO:-}" ]; then
      cache_args+=(--cache-to "$DOCKER_CACHE_TO")
    fi

    docker buildx build \
      --platform linux/amd64 \
      --file "$source_dir/packaging/linux/Dockerfile" \
      --target artifact \
      "${build_args[@]}" \
      --output "type=local,dest=$artifact_dir" \
      "${cache_args[@]}" \
      "$source_dir"

    artifact=$(find "$artifact_dir" -type f -name '*.tar.xz' -print -quit)
    [ -n "$artifact" ] || { echo "No build artifact found for $name ($image_version)" >&2; exit 1; }
    tar --extract --file "$artifact" --strip-components=1 --directory "$appdir/usr/lib/$slug"

    executable=$(find "$appdir/usr/lib/$slug" -type f -perm /111 -print | head -n 1)
    [ -n "$executable" ] || { echo "No executable found in $artifact" >&2; exit 1; }
    executable_path=${executable#"$appdir/usr/lib/$slug/"}

    printf '%s\n' '#!/bin/sh' 'set -e' \
      'HERE="$(dirname "$(readlink -f "$0")")"' \
      "exec \"\$HERE/usr/lib/$slug/$executable_path\" \"\$@\"" \
      > "$appdir/AppRun"
    chmod +x "$appdir/AppRun"

    printf '%s\n' '[Desktop Entry]' "Name=$name" \
      "X-AppImage-Version=$image_version" "Comment=$description" \
      "Exec=$slug" "Icon=$slug" 'Type=Application' 'Categories=Game;' \
      > "$appdir/$slug.desktop"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect width="256" height="256" fill="#20252b"/><text x="128" y="145" fill="white" font-size="64" text-anchor="middle">%s</text></svg>\n' "$name" > "$appdir/$slug.svg"

    image_name="$slug-$image_version-x86_64.AppImage"
    repository_for_update=$(printf '%s' "$GITHUB_REPOSITORY" | tr '/' '|')
    update_scheme="gh-releases-zsync|$repository_for_update|latest|$update_filename"
    ARCH=x86_64 ./appimagetool.AppImage -u "$update_scheme" "$appdir" "dist/$image_name"
    zsyncmake "dist/$image_name" -o "dist/$image_name.zsync"
  done
done <<< "$RELEASES"
