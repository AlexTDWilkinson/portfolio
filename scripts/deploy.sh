#!/usr/bin/env bash
# Build the site locally from its Nail sources and ship the binary to the
# droplet.
#
#   ./scripts/deploy.sh root@<droplet-ip>            # binary + static assets
#   ./scripts/deploy.sh root@<droplet-ip> --push-env # also upload local .env
#
# Host can also come from DEPLOY_HOST in the environment or in .env.
# Nothing is built on the droplet - it only ever receives a finished binary.
#
# The binary links only libc/libm/libgcc (rustls means no OpenSSL) and needs at
# most GLIBC_2.34, so it runs on any droplet at Ubuntu 22.04 or newer.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Reads a key out of .env without sourcing it, so odd characters in a value
# (quotes, backslashes, $) stay literal.
env_val() {
	[[ -f .env ]] || return 0
	grep -E "^$1=" .env | tail -1 | cut -d= -f2- | sed 's/^"\(.*\)"$/\1/'
}

HOST="${1:-${DEPLOY_HOST:-}}"
if [[ "${HOST:-}" == --* ]]; then HOST=""; fi
[[ -z "$HOST" ]] && HOST="$(env_val DEPLOY_HOST)"
if [[ -z "$HOST" ]]; then
	echo "usage: $0 user@host [--push-env]   (or set DEPLOY_HOST)" >&2
	exit 1
fi

# DEPLOY_PASSWORD in .env means no prompts. The value is handed to sshpass
# through the environment, never on a command line, so it stays out of `ps`.
# Leave it unset to authenticate normally (key or typed password).
SSH=(ssh -o StrictHostKeyChecking=accept-new)
SCP=(scp -o StrictHostKeyChecking=accept-new)
RSH="ssh -o StrictHostKeyChecking=accept-new"
DEPLOY_PASSWORD="${DEPLOY_PASSWORD:-$(env_val DEPLOY_PASSWORD)}"
if [[ -n "$DEPLOY_PASSWORD" ]]; then
	if ! command -v sshpass >/dev/null; then
		echo "DEPLOY_PASSWORD is set but sshpass is not installed (apt install sshpass)" >&2
		exit 1
	fi
	export SSHPASS="$DEPLOY_PASSWORD"
	SSH=(sshpass -e "${SSH[@]}")
	SCP=(sshpass -e "${SCP[@]}")
	RSH="sshpass -e $RSH"
fi

PUSH_ENV=false
for arg in "$@"; do [[ "$arg" == "--push-env" ]] && PUSH_ENV=true; done

# This app's identity on the box - must match what add-app.sh registered.
# BIN is the name the systemd unit execs (/srv/portfolio/$BIN); the build
# produces portfolio_site and it is renamed on the way up. Changing either name
# means re-running deploy/add-app.sh on the droplet to rewrite the unit.
APP=portfolio
APP_PORT=3002
BIN=alex-portfolio

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# The site is a Nail program: nail-build.sh regenerates the stylesheet from the
# Nail sources, transpiles site.nail, and builds the result in server/.
echo "== building =="
./scripts/nail-build.sh
BUILT="server/target/release/portfolio_site"

cp "$BUILT" "$STAGE/$BIN"
strip "$STAGE/$BIN" 2>/dev/null || true
chmod +x "$STAGE/$BIN"
echo "   $(du -h "$STAGE/$BIN" | cut -f1) $(file -b "$STAGE/$BIN" | cut -d, -f1-2)"

if $PUSH_ENV; then
	if [[ ! -f .env ]]; then echo "no local .env to push" >&2; exit 1; fi
	echo "== uploading secrets =="
	# EnvironmentFile= wants bare KEY=value lines, so strip any `export ` prefix.
	# DEPLOY_* keys are for this script only - never ship the droplet's own
	# password to the droplet.
	sed 's/^export //' .env | grep -vE '^DEPLOY_' \
		| "${SSH[@]}" "$HOST" "cat > /srv/$APP/env && chown $APP:$APP /srv/$APP/env && chmod 600 /srv/$APP/env"
fi

echo "== uploading static assets =="
rsync -az --delete -e "$RSH" static/ "$HOST:/srv/$APP/static/"

echo "== uploading binary =="
# Write beside the live binary then mv: rename is atomic, so a request never
# hits a half-copied file, and the running process keeps its old inode.
"${SCP[@]}" -q "$STAGE/$BIN" "$HOST:/srv/$APP/$BIN.new"
"${SSH[@]}" "$HOST" "mv /srv/$APP/$BIN.new /srv/$APP/$BIN \
	&& chown -R $APP:$APP /srv/$APP \
	&& systemctl restart $APP"

echo "== health check =="
sleep 2
if "${SSH[@]}" "$HOST" "curl -fsS -o /dev/null -w '%{http_code}' http://127.0.0.1:$APP_PORT/"; then
	echo " - up"
else
	echo " - FAILED; recent logs:" >&2
	"${SSH[@]}" "$HOST" "journalctl -u $APP -n 30 --no-pager" >&2
	exit 1
fi
