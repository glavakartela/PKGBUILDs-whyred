#!/bin/bash
# Build only the packages that changed or whose version is not present in the
# whyred pacman repository.  Packages are built in dependency order and the
# ones that other packages need are installed locally, so a package update does
# not race the GitHub Pages repository while it is being republished.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="${ARTIFACTS:-$ROOT/artifacts}"
CHANGED=""
FORCE_ALL=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
	case "$1" in
	--changed)
		CHANGED="${2:-}"
		shift 2
		;;
	--artifacts)
		ARTIFACTS="${2:-}"
		shift 2
		;;
	--force-all)
		FORCE_ALL=1
		shift
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	*)
		echo "unknown argument: $1" >&2
		exit 2
		;;
	esac
done

mkdir -p "$ARTIFACTS"
rm -f "$ARTIFACTS"/*.pkg.tar.* 2>/dev/null || true

# Packages that other packages or the device package need to have installed in
# the build container.  The two kernel packages conflict, so only the whyred
# one is installed; the other is still built and published.
declare -A INSTALL=(
	[qrtr]=1
	[pd-mapper]=1
	[qcom-diag]=1
	[rmtfs]=1
	[tqftpserv]=1
	[qbootctl]=1
	[msm-modem]=1
	[q6voiced]=1
	[swclock-offset]=1
	[firmware-xiaomi-whyred]=1
	[sdm660-linux-whyred]=1
	[llvm-mingw]=1
)

# Build order.  New package directories not listed here are appended at the end.
PACKAGES=(
	qrtr
	pd-mapper
	qcom-diag
	rmtfs
	tqftpserv
	qbootctl
	msm-modem
	q6voiced
	swclock-offset
	bootmac
	buffyboard
	sdm660-linux
	sdm660-linux-whyred
	firmware-xiaomi-whyred
	device-xiaomi-whyred
	sdm660-libcamera
	sdm660-mesa-a5xx
	sdm660-audio
	sdm660-venus
	whyred-plasma
	llvm-mingw
	box64
	wine-aarch64
	whyred-gaming
)

while IFS= read -r dir; do
	found=0
	for p in "${PACKAGES[@]}"; do
		[ "$p" = "$dir" ] && { found=1; break; }
	done
	[ "$found" -eq 0 ] && PACKAGES+=("$dir")
done < <(find "$ROOT" -mindepth 2 -maxdepth 2 -name PKGBUILD -printf '%h\n' |
	sed "s|^$ROOT/||" | sort)

pkg_meta() {
	local pkgbuild="$1" name ver rel ep
	(
		set +u
		# shellcheck disable=SC1090
		. "$pkgbuild" >/dev/null 2>&1
		printf '%s\t%s\t%s\t%s\n' \
			"${pkgname[0]:-}" "${pkgver:-}" "${pkgrel:-}" "${epoch:-}"
	) 2>/dev/null
}

repo_version() {
	pacman -Si "$1" 2>/dev/null |
		awk -F': ' '/^Version[[:space:]]*:/ { print $2; exit }' ||
		true
}

built=0

for dir in "${PACKAGES[@]}"; do
	pkgbuild="$ROOT/$dir/PKGBUILD"
	[ -f "$pkgbuild" ] || continue

	IFS=$'\t' read -r name ver rel ep < <(pkg_meta "$pkgbuild")
	if [ -z "$name" ] || [ -z "$ver" ] || [ -z "$rel" ]; then
		echo "cannot parse $pkgbuild" >&2
		exit 1
	fi

	full="${ep:+$ep:}$ver-$rel"
	repo="$(repo_version "$name")"
	need=0

	[ "$FORCE_ALL" -eq 1 ] && need=1
	case " $CHANGED " in
	*" $dir "*) need=1 ;;
	esac
	if [ "$repo" != "$full" ]; then
		need=1
	fi
	if [ "$need" -eq 0 ]; then
		echo "skip $dir: $full is already in the repository"
		continue
	fi

	echo "build $dir: $full (repository: ${repo:-missing})"
	if [ "$DRY_RUN" -eq 1 ]; then
		built=$((built + 1))
		continue
	fi
	rm -f "$ROOT/$dir"/*.pkg.tar.* 2>/dev/null || true
	attempt=1
	ok=0
	while [ "$attempt" -le 5 ]; do
		log="/tmp/build-$dir-$attempt.log"
		if su builder -c "cd '$ROOT/$dir' && makepkg -s --noconfirm --needed" 2>&1 |
			tee "$log"; then
			ok=1
			break
		fi
		if grep -qE 'invalid or corrupted package \(checksum\)|failed retrieving file|failed to commit transaction|failed to install missing dependencies|Could not resolve host' "$log"; then
			echo "::warning::package download/checksum failed; retrying $dir (attempt $attempt/5)"
			pacman -Scc --noconfirm >/dev/null 2>&1 || true
			pacman -Syy --noconfirm >/dev/null 2>&1 || true
			sleep $((attempt * 30))
			attempt=$((attempt + 1))
			continue
		fi
		break
	done
	if [ "$ok" -ne 1 ]; then
		echo "build failed: $dir (see $log)" >&2
		exit 1
	fi

	pkgfiles=("$ROOT/$dir"/*.pkg.tar.*)
	if [ "${#pkgfiles[@]}" -eq 0 ] || [ ! -e "${pkgfiles[0]}" ]; then
		echo "no package file produced for $dir" >&2
		exit 1
	fi
	# GitHub Actions artifact names cannot contain a colon, which
	# appears in package filenames when a package has an epoch.
	for _pkgfile in "${pkgfiles[@]}"; do
		_name="$(basename "$_pkgfile")"
		cp -f "$_pkgfile" "$ARTIFACTS/${_name//:/_}"
	done
	if [ "${INSTALL[$dir]:-0}" -eq 1 ]; then
		if [ "$dir" = "sdm660-linux-whyred" ]; then
			pacman -Rdd --noconfirm linux-qcom-sdm636-whyred sdm660-linux \
				>/dev/null 2>&1 || true
		fi
		pacman -U --noconfirm --needed "${pkgfiles[@]}"
	fi
	built=$((built + 1))
done

echo "packages built: $built"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "built=$built" >>"$GITHUB_OUTPUT"
fi
