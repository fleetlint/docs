#!/usr/bin/env bash
# The docs of earlier releases, built from their git tags.
#   versions.sh DIR LATEST   build the newest tag of every minor except LATEST into DIR/<vX.Y>/,
#                            and list them in DIR/versions.json for the version switcher
# Each tag builds with its own `make snapshot`; needs the tags (checkout with fetch-depth: 0).
set -euo pipefail

dir=$(realpath "${1:?usage: versions.sh DIR LATEST}") latest=${2:?usage: versions.sh DIR LATEST}
work=$(mktemp -d)
trap 'rm -rf "$work"; git worktree prune' EXIT

versions=()
for tag in $(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sort -rV); do
  v=$(echo "$tag" | cut -d. -f1,2)
  [ "$v" = "$latest" ] && continue
  printf '%s\n' "${versions[@]}" | grep -qxF "$v" && continue # an older patch of a minor already built
  git worktree add --quiet --detach "$work/$v" "$tag"
  make -C "$work/$v" --no-print-directory snapshot >/dev/null
  rm -rf "${dir:?}/$v"
  mv "$work/$v/snapshot" "$dir/$v"
  versions+=("$v")
  echo "added $v from $tag"
done

python3 -c 'import json, sys; print(json.dumps({"latest": sys.argv[1], "versions": sys.argv[2:]}))' "$latest" "${versions[@]}" >"$dir/versions.json"
