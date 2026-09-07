#!/usr/bin/env python3
"""Open the dev → main PR when needed; tag only reviewed main content."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def next_version(tags, bump):
    versions = [tuple(map(int, match.groups())) for tag in tags
                if (match := re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag))]
    major, minor, patch = max(versions, default=(0, 0, 0))
    if bump == "patch": patch += 1
    elif bump == "minor": minor, patch = minor + 1, 0
    elif bump == "major": major, minor, patch = major + 1, 0, 0
    else: raise ValueError("Unknown server version increment")
    return f"v{major}.{minor}.{patch}"


def read(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    subprocess.run(["git", "fetch", "origin", "dev", "main", "--tags"], check=True)
    # Content equivalence accepts squash/rebase merges without requiring matching ancestry.
    comparison = subprocess.run(["git", "diff", "--quiet", "origin/main", "origin/dev"]).returncode
    if comparison not in (0, 1):
        raise RuntimeError("Could not compare main and dev")
    if comparison == 1:
        prs = json.loads(read("gh", "pr", "list", "--base", "main", "--head", "dev", "--state", "open", "--json", "url"))
        if prs:
            print("Merge the existing release PR, then rerun: " + prs[0]["url"])
        else:
            with tempfile.TemporaryDirectory() as folder:
                body = Path(folder) / "body.md"
                body.write_text("Promote the tested dev snapshot to production. Merge through the required PR checks, then rerun Release / main to tag and publish the server binaries. Mobile releases use their separate mobile-vX.Y.Z tags.\n")
                print(read("gh", "pr", "create", "--base", "main", "--head", "dev", "--title", "chore: promote dev to main", "--body-file", str(body)))
        return
    tag = next_version(read("git", "tag", "--list").splitlines(), os.environ["BUMP"])
    # Ref creation through the API avoids putting a PAT in Git remote URLs.
    sha = read("git", "rev-parse", "origin/main")
    existing_tags = read("git", "tag", "--points-at", sha).splitlines()
    if any(re.fullmatch(r"v\d+\.\d+\.\d+", item) for item in existing_tags):
        raise ValueError("This main commit already has a server release tag; resume its failed run instead")
    read("gh", "api", "--method", "POST", "repos/YourTongji/YourTJ-Hub/git/refs",
         "-f", f"ref=refs/tags/{tag}", "-f", f"sha={sha}")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"tag={tag}\n")
    print(f"Tagged reviewed main commit {sha}: {tag}")


if __name__ == "__main__":
    main()
