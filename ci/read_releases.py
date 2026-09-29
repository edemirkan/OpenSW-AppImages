import os
import json
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

import yaml


manifest_path = Path(os.environ.get("RELEASES_FILE", "resources/meta.yml"))
output_path = os.environ.get("GITHUB_OUTPUT")
if not output_path:
    raise RuntimeError("GITHUB_OUTPUT is required")

with manifest_path.open(encoding="utf-8") as manifest_file:
    releases = yaml.safe_load(manifest_file)


def resolve_sha(repository, ref):
    output = subprocess.check_output(
        ["git", "ls-remote", f"https://github.com/{repository}.git", ref],
        text=True,
    )
    sha = output.split()[0]
    return sha[:7]


def resolve_latest_release(repository):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/releases/latest",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "OpenSW-AppImages"},
    )
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request) as response:
        release = json.load(response)
    tag = release["tag_name"]
    version = tag.removeprefix("v")
    return tag, version


def resolve_release_assets():
    request = urllib.request.Request(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/releases/tags/latest",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "OpenSW-AppImages"},
    )
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request) as response:
            release = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return set()
        raise
    return {asset["name"] for asset in release.get("assets", [])}


matrix = []
should_build = False
force_refresh = os.environ.get("FORCE_REFRESH", "").lower() == "true"
published_assets = resolve_release_assets()
for name, release in releases.items():
    repository = release["scm"]["url"]
    release_tag, version = resolve_latest_release(repository)
    description = release.get("description", "")
    slug = release["slug"]
    executable_name = repository.rsplit("/", 1)[-1]
    project_prefix = executable_name.removeprefix("Open").upper()
    for kind, ref, build_version in (
        ("release", release_tag, version),
        ("main", "main", ""),
    ):
        sha = resolve_sha(repository, ref)
        image_version = f"v{build_version}" if kind == "release" else f"main-{sha}"
        expected_asset = f"{slug}-{image_version}-x86_64.AppImage"
        if not force_refresh:
            if expected_asset in published_assets and f"{expected_asset}.zsync" in published_assets:
                continue
        should_build = True
        matrix.append({
            "build_label": f"release@{release_tag}, {sha}" if kind == "release" else f"main@{sha}",
            "description": description,
            "appstream_id": release["appstream_id"],
            "app_summary": release["summary"],
            "kind": kind,
            "name": name,
            "project_prefix": project_prefix,
            "ref": ref,
            "repository": repository,
            "release_name": "latest",
            "slug": slug,
            "executable_name": executable_name,
            "update_filename": f"{slug}-{'main-' if kind == 'main' else 'v'}*-x86_64.AppImage.zsync",
            "version": build_version,
        })
with open(output_path, "a", encoding="utf-8") as output_file:
    output_file.write("matrix<<EOF\n")
    output_file.write(json.dumps(matrix or [{"name": "No changes", "build_label": "skipped"}], separators=(",", ":")))
    output_file.write("\nEOF\n")
    output_file.write(f"should_build={str(should_build).lower()}\n")
