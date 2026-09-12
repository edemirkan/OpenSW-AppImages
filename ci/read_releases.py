import os
import json
from pathlib import Path

import yaml


manifest_path = Path(os.environ.get("RELEASES_FILE", "resources/release.yml"))
output_path = os.environ.get("GITHUB_OUTPUT")
if not output_path:
    raise RuntimeError("GITHUB_OUTPUT is required")

with manifest_path.open(encoding="utf-8") as manifest_file:
    releases = yaml.safe_load(manifest_file)

output_lines = []
matrix = []
for name, release in releases.items():
    release_info = release["release"]
    version = str(release_info["version"])
    scm_url = release["scm"]["url"]
    description = release.get("description", "")
    output_lines.append(f"{name}|{version}|{scm_url}|{description}")
    slug = "".join(character.lower() for character in name if character.isalnum() or character == "-")
    for kind, ref, build_version in (
        ("release", f"v{version}", version),
        ("git", "main", ""),
    ):
        matrix.append({
            "description": description,
            "kind": kind,
            "name": name,
            "project_prefix": {"opentie": "TIE", "openxwa": "XWA"}[slug],
            "ref": ref,
            "repository": scm_url,
            "slug": slug,
            "update_filename": f"{slug}-{'git-' if kind == 'git' else ''}*-x86_64.AppImage.zsync",
            "version": build_version,
        })

with open(output_path, "a", encoding="utf-8") as output_file:
    output_file.write("release<<EOF\n")
    output_file.write("\n".join(output_lines))
    output_file.write("\nEOF\n")
    output_file.write("matrix<<EOF\n")
    output_file.write(json.dumps(matrix, separators=(",", ":")))
    output_file.write("\nEOF\n")
