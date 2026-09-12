import os
import json
import subprocess
import urllib.request
import urllib.error
import re
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


def resolve_published_builds():
    repository = os.environ.get("GITHUB_REPOSITORY")
    if not repository:
        return set()
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/releases?per_page=100",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "OpenSW-AppImages"},
    )
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request) as response:
            releases = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return set()
        raise
    published = set()
    for release in releases:
        for match in re.finditer(
            r"^- ([^:]+): release@([^ ]+) \([^)]*\), main@([^ ]+)",
            release.get("body", ""),
            re.MULTILINE,
        ):
            name, release_tag, main_sha = match.groups()
            published.add((name, "release", release_tag))
            published.add((name, "main", main_sha))
    return published


output_lines = []
release_notes = []
matrix = []
published_builds = resolve_published_builds()
for name, release in releases.items():
    repository = release["scm"]["url"]
    release_tag, version = resolve_latest_release(repository)
    description = release.get("description", "")
    output_lines.append(f"{name}|{version}|{repository}|{description}")
    slug = "".join(character.lower() for character in name if character.isalnum() or character == "-")
    executable_name = repository.rsplit("/", 1)[-1]
    project_prefix = executable_name.removeprefix("Open").upper()
    release_sha = ""
    main_sha = ""
    for kind, ref, build_version in (
        ("release", release_tag, version),
        ("main", "main", ""),
    ):
        sha = resolve_sha(repository, ref)
        if kind == "release":
            release_sha = sha
        else:
            main_sha = sha
        matrix.append({
            "build_label": f"release@{release_tag}, {sha}" if kind == "release" else f"main@{sha}",
            "description": description,
            "kind": kind,
            "name": name,
            "project_prefix": project_prefix,
            "ref": ref,
            "repository": repository,
            "sha": sha,
            "should_build": (name, kind, ref if kind == "release" else sha) not in published_builds,
            "slug": slug,
            "executable_name": executable_name,
            "update_filename": f"{slug}-{'main-' if kind == 'main' else ''}*-x86_64.AppImage.zsync",
            "version": build_version,
        })
    release_notes.append(f"- {name}: release@{release_tag} ({release_sha}), main@{main_sha}")

should_build = any(build["should_build"] for build in matrix)

with open(output_path, "a", encoding="utf-8") as output_file:
    output_file.write("release<<EOF\n")
    output_file.write("\n".join(output_lines))
    output_file.write("\nEOF\n")
    output_file.write("release_notes<<EOF\n")
    output_file.write("\n".join(release_notes))
    output_file.write("\nEOF\n")
    output_file.write(f"should_build={str(should_build).lower()}\n")
    output_file.write("matrix<<EOF\n")
    output_file.write(json.dumps(matrix, separators=(",", ":")))
    output_file.write("\nEOF\n")
