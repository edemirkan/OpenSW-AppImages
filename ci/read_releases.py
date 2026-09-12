import os
from pathlib import Path

import yaml


manifest_path = Path(os.environ.get("RELEASES_FILE", "resources/release.yml"))
output_path = os.environ.get("GITHUB_OUTPUT")
if not output_path:
    raise RuntimeError("GITHUB_OUTPUT is required")

with manifest_path.open(encoding="utf-8") as manifest_file:
    releases = yaml.safe_load(manifest_file)

output_lines = []
for name, release in releases.items():
    release_info = release["release"]
    version = str(release_info["version"])
    scm_url = release["scm"]["url"]
    description = release.get("description", "")
    output_lines.append(f"{name}|{version}|{scm_url}|{description}")

with open(output_path, "a", encoding="utf-8") as output_file:
    output_file.write("release<<EOF\n")
    output_file.write("\n".join(output_lines))
    output_file.write("\nEOF\n")
