#!/usr/bin/env bash
# The frozen docs of each release, kept in the Gitea generic package registry.
#   snapshots.sh upload VERSION DIR   store DIR as VERSION, replacing an earlier upload of it
#   snapshots.sh fetch DIR LATEST     unpack every stored version except LATEST into DIR/<version>/,
#                                     and list them in DIR/versions.json for the version switcher
# Needs GITEA_URL, GITEA_OWNER and GITEA_TOKEN (read:package; write:package to upload).
set -euo pipefail

PACKAGE=fleetlint-docs
FILE=site.tar.gz
base="$GITEA_URL/api/packages/$GITEA_OWNER/generic/$PACKAGE"
auth=(-H "Authorization: token $GITEA_TOKEN")

case "${1:-}" in
  upload)
    version=$2 dir=$3
    tmp=$(mktemp -d)
    tar -czf "$tmp/$FILE" -C "$dir" .
    # a patch release replaces its minor's snapshot; 404 when the version is new
    code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "${auth[@]}" "$base/$version")
    case "$code" in 204 | 404) ;; *)
      echo "::error::deleting $PACKAGE $version returned HTTP $code"
      exit 1
      ;;
    esac
    curl -fsS "${auth[@]}" --upload-file "$tmp/$FILE" "$base/$version/$FILE"
    echo "stored $PACKAGE $version"
    ;;
  fetch)
    dir=$2 latest=$3
    versions=$(curl -fsS "${auth[@]}" "$GITEA_URL/api/v1/packages/$GITEA_OWNER?type=generic&q=$PACKAGE&limit=50" |
      python3 -c 'import json, sys; print("\n".join(p["version"] for p in json.load(sys.stdin) if p["name"] == sys.argv[1]))' "$PACKAGE" |
      grep -vxF "$latest" | sort -rV || true)
    for v in $versions; do
      mkdir -p "$dir/$v"
      curl -fsS "${auth[@]}" "$base/$v/$FILE" | tar -xz -C "$dir/$v"
      echo "added $v"
    done
    # shellcheck disable=SC2086 # one argument per version
    python3 -c 'import json, sys; print(json.dumps({"latest": sys.argv[1], "versions": sys.argv[2:]}))' "$latest" $versions >"$dir/versions.json"
    ;;
  *)
    sed -n '2,6p' "$0"
    exit 2
    ;;
esac
