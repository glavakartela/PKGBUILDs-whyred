#!/bin/bash
# Update _commit in PKGBUILDs marked with:
#   # AutoUpdate: <owner/repo or https URL> <branch>
#
# A package that vendors a git submodule can also add:
#   # AutoUpdateSubmodule: <path> <owner/repo or https URL>
# The submodule's gitlink is stored in _<path>_commit and is refreshed from the
# parent commit, so the PKGBUILD stays reproducible.
#
# Usage: scripts/autoupdate.sh [--push]
# The workflow passes --push; local runs only modify the working tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUSH=0
[ "${1:-}" = "--push" ] && PUSH=1
export GIT_TERMINAL_PROMPT=0

repo_url() {
	case "$1" in
	*://*) printf '%s\n' "$1" ;;
	*) printf 'https://github.com/%s.git\n' "$1" ;;
	esac
}

branch_sha() {
	git ls-remote "$1" "refs/heads/$2" | awk 'NR == 1 { print $1 }'
}

submodule_sha() {
	local url="$1" branch="$2" parent="$3" path="$4" tmp got=""
	tmp="$(mktemp -d)"
	if git clone -q --depth 1 --no-checkout --branch "$branch" \
		"$url" "$tmp/repo" 2>/dev/null; then
		# The parent branch may have moved after ls-remote; prefer the exact
		# commit we resolved, then fall back to the fetched branch tip.
		git -C "$tmp/repo" fetch -q --depth 1 origin "$parent" 2>/dev/null || true
		got="$(git -C "$tmp/repo" ls-tree "$parent" "$path" 2>/dev/null |
			awk '$2 == "commit" { print $3; exit }')"
		[ -n "$got" ] || got="$(git -C "$tmp/repo" ls-tree HEAD "$path" 2>/dev/null |
			awk '$2 == "commit" { print $3; exit }')"
	fi
	rm -rf "$tmp"
	printf '%s\n' "$got"
}

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

	url="$(repo_url "$repo")"
	sha="$(branch_sha "$url" "$branch")"
	[ -n "$sha" ] || {
		echo "cannot resolve $url $branch" >&2
		exit 1
	}

	cur="$(grep -m1 '^_commit=' "$pkgbuild" | cut -d= -f2- || true)"
	[ -n "$cur" ] || {
		echo "no _commit= in $pkgbuild" >&2
		exit 1
	}

	pkg_changed=0
	if [ "$cur" != "$sha" ]; then
		sed -i "s/^_commit=.*/_commit=$sha/" "$pkgbuild"
		pkg_changed=1
	fi

	while IFS= read -r submeta; do
		[ -n "$submeta" ] || continue
		read -r path subrepo <<<"${submeta#\# AutoUpdateSubmodule: }"
		[ -n "$path" ] && [ -n "$subrepo" ] || {
			echo "bad AutoUpdateSubmodule line in $pkgbuild" >&2
			exit 1
		}

		var="_$(printf '%s' "$path" | sed 's/[^A-Za-z0-9_]/_/g')_commit"
		subcur="$(grep -m1 "^$var=" "$pkgbuild" | cut -d= -f2- || true)"
		[ -n "$subcur" ] || {
			echo "no $var= in $pkgbuild" >&2
			exit 1
		}

		subsha="$(submodule_sha "$url" "$branch" "$sha" "$path")"
		[ -n "$subsha" ] || {
			echo "cannot resolve submodule $path at $sha" >&2
			exit 1
		}
		if [ "$subcur" != "$subsha" ]; then
			sed -i "s/^$var=.*/$var=$subsha/" "$pkgbuild"
			echo "$path: ${subcur:0:12} -> ${subsha:0:12}"
			pkg_changed=1
		fi
	done < <(grep '^# AutoUpdateSubmodule:' "$pkgbuild" || true)

	[ "$pkg_changed" -eq 1 ] || continue

	pkgdir="$(basename "$(dirname "$pkgbuild")")"
	pkgrel="$(date -u +%Y%m%d%H%M%S)"
	sed -i "s/^pkgrel=.*/pkgrel=$pkgrel/" "$pkgbuild"
	if [ "$cur" != "$sha" ]; then
		echo "$pkgdir: ${cur:0:12} -> ${sha:0:12} (pkgrel $pkgrel)"
		summary+="$pkgdir: ${cur:0:12} -> ${sha:0:12}"$'\n'
	else
		echo "$pkgdir: submodule update (pkgrel $pkgrel)"
		summary+="$pkgdir: submodule update"$'\n'
	fi
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
	branch="${GITHUB_REF_NAME:-main}"
	git -C "$ROOT" push origin "HEAD:$branch"
fi
