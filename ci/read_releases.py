import os
import json
import subprocess
from pathlib import Path

import yaml


manifest_path = Path(os.environ.get("RELEASES_FILE", "resources/release.yml"))
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


output_lines = []
release_notes = []
matrix = []
for name, release in releases.items():
    release_info = release["release"]
    version = str(release_info["version"])
    repository = release["scm"]["url"]
    description = release.get("description", "")
    output_lines.append(f"{name}|{version}|{repository}|{description}")
    slug = "".join(character.lower() for character in name if character.isalnum() or character == "-")
    for kind, ref, build_version in (
        ("release", f"v{version}", version),
        ("main", "main", ""),
    ):
        sha = resolve_sha(repository, ref)
        release_notes.append(
            f"- {name}-{kind}: {f'v{version}' if kind == 'release' else sha}"
        )
        matrix.append({
            "build_label": f"release@v{version}, {sha}" if kind == "release" else f"main@{sha}",
            "description": description,
            "kind": kind,
            "name": name,
            "project_prefix": {"opentie": "TIE", "openxwa": "XWA"}[slug],
            "ref": ref,
            "repository": repository,
            "sha": sha,
            "slug": slug,
            "update_filename": f"{slug}-{'main-' if kind == 'main' else ''}*-x86_64.AppImage.zsync",
            "version": build_version,
        })

with open(output_path, "a", encoding="utf-8") as output_file:
    output_file.write("release<<EOF\n")
    output_file.write("\n".join(output_lines))
    output_file.write("\nEOF\n")
    output_file.write("release_notes<<EOF\n")
    output_file.write("\n".join(release_notes))
    output_file.write("\nEOF\n")
    output_file.write("matrix<<EOF\n")
    output_file.write(json.dumps(matrix, separators=(",", ":")))
    output_file.write("\nEOF\n")
