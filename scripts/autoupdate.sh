#!/bin/bash
# Update _commit in PKGBUILDs marked with:
#   # AutoUpdate: <owner/repo> <branch>
#
# Usage: scripts/autoupdate.sh [--push]
# The workflow passes --push; local runs only modify the working tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUSH=0
[ "${1:-}" = "--push" ] && PUSH=1

changed=0
summary=""

while IFS= read -r -d '' pkgbuild; do
	meta="$(grep -m1 '^# AutoUpdate:' "$pkgbuild" || true)"
	[ -n "$meta" ] || continue

	read -r repo branch <<<"${meta#\# AutoUpdate: }"
	[ -n "$repo" ] && [ -n "$branch" ] || {
		echo "bad AutoUpdate line in $pkgbuild" >&2
		exit 1
	}

	sha="$(git ls-remote "https://github.com/$repo.git" \
		"refs/heads/$branch" | awk '{print $1; exit}')"
	[ -n "$sha" ] || {
		echo "cannot resolve $repo $branch" >&2
		exit 1
	}

	cur="$(grep -m1 '^_commit=' "$pkgbuild" | cut -d= -f2- || true)"
	[ -n "$cur" ] || {
		echo "no _commit= in $pkgbuild" >&2
		exit 1
	}
	[ "$cur" = "$sha" ] && continue

	pkgdir="$(basename "$(dirname "$pkgbuild")")"
	pkgrel="$(date -u +%Y%m%d%H%M%S)"
	sed -i "s/^_commit=.*/_commit=$sha/; s/^pkgrel=.*/pkgrel=$pkgrel/" "$pkgbuild"
	echo "$pkgdir: ${cur:0:12} -> ${sha:0:12} (pkgrel $pkgrel)"
	summary+="$pkgdir: ${cur:0:12} -> ${sha:0:12}"$'\n'
	changed=1
done < <(find "$ROOT" -mindepth 2 -maxdepth 2 -name PKGBUILD -print0)

if [ "$changed" -eq 0 ]; then
	echo "auto-update: everything is current"
	exit 0
fi

git -C "$ROOT" config user.name "Kulesha Evgeniy"
git -C "$ROOT" config user.email "voovdop@gmail.com"
git -C "$ROOT" add -A
git -C "$ROOT" commit -F - <<EOF
CI: update auto-updated packages

$summary
Signed-off-by: Kulesha Evgeniy <voovdop@gmail.com>

[skip ci]
EOF

if [ "$PUSH" -eq 1 ]; then
	git -C "$ROOT" push origin HEAD:main
fi
