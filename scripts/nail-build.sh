#!/usr/bin/env bash
# Transpile site.nail to Rust and build it.
#
#   ./scripts/nail-build.sh          # build
#   ./scripts/nail-build.sh --run    # build, then run it
#
# server/src/main.rs and server/Cargo.toml are both generated on every build -
# never edit them, and never commit main.rs. The dependency list comes from
# which stdlib functions site.nail actually calls, so it is regenerated too.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Where the Nail compiler and its runtime library live. The transpiled program
# depends on the `nail` crate for std_lib, so the source tree has to be present.
NAIL_PATH="${NAIL_PATH:-$HOME/Nail}"
NAILC="$NAIL_PATH/target/debug/nailc"

if [[ ! -x "$NAILC" ]]; then
	echo "nailc not found at $NAILC - build it with 'cargo build --bin nailc' in $NAIL_PATH" >&2
	exit 1
fi

mkdir -p server/src

# The pages carry Tailwind classes, and Tailwind only ships the classes it can
# see - so the stylesheet is regenerated from the Nail sources on every build,
# or a newly used class (a disabled state, a transition) would silently have no
# styling. The version is pinned and the binary cached under target/, rather
# than taken from PATH, so everyone generates the same stylesheet.
TAILWIND_VERSION="v3.4.19"
TAILWIND_BIN="target/tailwind-cli/$TAILWIND_VERSION/tailwindcss"
if [[ ! -x "$TAILWIND_BIN" ]]; then
	case "$(uname -s)-$(uname -m)" in
		Linux-x86_64)   TAILWIND_ASSET=tailwindcss-linux-x64 ;;
		Linux-aarch64)  TAILWIND_ASSET=tailwindcss-linux-arm64 ;;
		Darwin-x86_64)  TAILWIND_ASSET=tailwindcss-macos-x64 ;;
		Darwin-arm64)   TAILWIND_ASSET=tailwindcss-macos-arm64 ;;
		*) echo "no tailwindcss $TAILWIND_VERSION build for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
	esac
	echo "Downloading tailwindcss $TAILWIND_VERSION..."
	mkdir -p "$(dirname "$TAILWIND_BIN")"
	# Download to a temporary name and rename, so an interrupted download never
	# leaves a half-written binary that looks cached.
	curl -fsSL -o "$TAILWIND_BIN.part" \
		"https://github.com/tailwindlabs/tailwindcss/releases/download/$TAILWIND_VERSION/$TAILWIND_ASSET"
	chmod +x "$TAILWIND_BIN.part"
	mv "$TAILWIND_BIN.part" "$TAILWIND_BIN"
fi

echo "Regenerating static/styles/app.css..."
"$TAILWIND_BIN" -c tailwind.config.js -i styles/tailwind.css -o static/styles/app.css --minify

echo "Transpiling site.nail..."
"$NAILC" site.nail --transpile --stdout > server/src/main.rs

echo "Regenerating server/Cargo.toml..."
"$NAILC" site.nail --cargo-toml --nail-path="$NAIL_PATH" --package-name=portfolio_site > server/Cargo.toml

echo "Building..."
cd server && cargo build --release

if [[ "${1:-}" == "--run" ]]; then
	# Run from the repo root so static/ resolves.
	cd ..
	exec ./server/target/release/portfolio_site
fi
