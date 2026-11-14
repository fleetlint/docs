#!/usr/bin/env python3
"""Load the configuration and catalog examples of the pages with the fleetlint on PATH.

A fenced yaml block whose first line is `version: 1` is a repository's .fleetlint.yaml
(a sources file when it has a top-level `catalogs:`, a fleet file when it has `repos:`,
which cannot be loaded on its own and is skipped); one whose first line is
`apiVersion: fleetlint.org/v1` is a catalog. Each is loaded in a scratch repository
(`fleetlint hierarchy`); an error or a warning on stderr fails the check. A block that is
partial on purpose or names an example host carries `<!-- example: unchecked -->` on the
line before its fence; the comment does not render. $FLEETLINT names the binary when the
one on PATH is not the one to use.

  check-examples.py [PAGE.md ...]   default: content/*.md
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

FENCE = re.compile(r"^(\s*)(```+|~~~+)\s*([\w-]*)")
UNCHECKED = "<!-- example: unchecked"
# A hook exports these; they would point `git init` at the hook's repository.
GIT_REDIRECTS = {"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR", "GIT_PREFIX"}


def blocks(path):
    """(line, lines, unchecked) for every yaml block of a page."""
    lines = open(path, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if not m:
            i += 1
            continue
        indent, fence, lang = len(m.group(1)), m.group(2), m.group(3)
        j = i + 1
        while j < len(lines) and not lines[j].strip().startswith(fence[:3]):
            j += 1
        if lang in ("yaml", "yml"):
            before = next((l.strip() for l in reversed(lines[:i]) if l.strip()), "")
            yield i + 1, [l[indent:] for l in lines[i + 1 : j]], before.startswith(UNCHECKED)
        i = j + 1


def kind(body):
    first = body[0].strip() if body else ""
    if first == "apiVersion: fleetlint.org/v1":
        return "catalog"
    if first != "version: 1":
        return None
    keys = {l.split(":", 1)[0] for l in body if re.match(r"^[a-z_]+:", l)}
    if "repos" in keys:
        return "fleet"
    return "sources" if "catalogs" in keys else "config"


def load(fleetlint, kind_, text, env):
    """fleetlint's stderr and exit code for the example in a scratch repository."""
    with tempfile.TemporaryDirectory(prefix="fleetlint-example-") as tmp:
        subprocess.run(["git", "-C", tmp, "init", "-q"], check=True, env=env)
        files = {
            "config": {".fleetlint.yaml": text},
            "sources": {"sources.yaml": text, ".fleetlint.yaml": "version: 1\nsources: sources.yaml\n"},
            "catalog": {"catalog.yaml": text, ".fleetlint.yaml": "version: 1\nextends: [catalog.yaml]\n"},
        }[kind_]
        for name, body in files.items():
            with open(os.path.join(tmp, name), "w", encoding="utf-8") as f:
                f.write(body)
        run = subprocess.run([fleetlint, "-C", tmp, "hierarchy"], capture_output=True, text=True, env=env)
        return run.stderr.strip(), run.returncode


def main(pages):
    fleetlint = os.environ.get("FLEETLINT") or shutil.which("fleetlint")
    if not fleetlint:
        sys.exit("check-examples.py: fleetlint is not on PATH (make tools)")
    version = subprocess.run([fleetlint, "version"], capture_output=True, text=True).stdout.split("\n")[0]
    env = {k: v for k, v in os.environ.items() if k not in GIT_REDIRECTS}
    loaded, unchecked, failed = 0, 0, []
    for page in pages:
        for line, body, skip in blocks(page):
            k = kind(body)
            if k is None or k == "fleet":
                continue
            if skip:
                unchecked += 1
                continue
            err, code = load(fleetlint, k, "\n".join(body) + "\n", env)
            loaded += 1
            if code != 0 or err:
                failed.append(f"{page}:{line}: {k} (exit {code})\n    " + err.replace("\n", "\n    "))
    for f in failed:
        print(f, file=sys.stderr)
    print(f"{loaded} examples loaded with {version}, {unchecked} marked unchecked, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    if any(a.startswith("-") for a in sys.argv[1:]):
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1:] or sorted(glob.glob("content/*.md"))))
