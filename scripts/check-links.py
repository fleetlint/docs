#!/usr/bin/env python3
"""Check every link in the built site: pages, anchors, and links to the site's own domain.

Hugo already fails the build on a link to a Markdown file that does not exist. This
covers what it cannot see: anchors, and the absolute https://fleetlint.org/ links the
generated rule pages carry (they come from the catalog).
"""
import glob
import html
import os
import posixpath
import re
import sys

SITE = "https://fleetlint.org"
# Added to public/ by `make demo` in the Pages workflow, not by the Hugo build this checks.
BUILT_SEPARATELY = {"/demo/report/"}
root = sys.argv[1] if len(sys.argv) > 1 else "public"

pages = {}
for path in glob.glob(os.path.join(root, "**", "*.html"), recursive=True):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    url = "/" + os.path.relpath(path, root).replace(os.sep, "/").replace("index.html", "")
    pages[url] = (text, set(re.findall(r'\sid="([^"]+)"', text)))

checked, broken = 0, []
for url, (text, _) in sorted(pages.items()):
    for href in re.findall(r'<a [^>]*href="([^"]+)"', text):
        href = html.unescape(href)
        if href.startswith(SITE):
            href = href[len(SITE):] or "/"
        elif re.match(r"[a-z]+:", href):
            continue
        checked += 1
        target, _, fragment = href.partition("#")
        target = target or url
        if not target.startswith("/"):
            # A relative link, as the fleet report under /demo/ writes them.
            target = posixpath.normpath(posixpath.join(posixpath.dirname(url), target))
        target = re.sub(r"/index\.html$", "/", target)
        if target in BUILT_SEPARATELY and target not in pages:
            continue
        if target not in pages:
            broken.append(f"{url}: {href} (no such page)")
        elif fragment and fragment not in pages[target][1]:
            broken.append(f"{url}: {href} (no such anchor)")

for line in broken:
    print(line, file=sys.stderr)
print(f"{checked} links checked, {len(broken)} broken")
sys.exit(1 if broken else 0)
