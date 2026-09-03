#!/usr/bin/env bash
#
# Start the KlardoIdent quick-start stack.
#
# First run: writes .env from .env.example with generated secrets, starts the
# stack, waits for the server to answer, and prints where to go and how to sign
# in. Later runs: starts what is already configured. .env is never overwritten —
# it holds the only copy of this install's secrets.
#
#   ./start.sh              start (generating .env if there is none)
#   docker compose down     stop, keeping the database
#   docker compose down -v  stop and delete the database volume
set -euo pipefail

cd "$(dirname "$0")"

# These files are GENERATED: the version numbers are substituted when the quick
# start is published. Running the unrendered template — a checkout of the build
# repository rather than a clone of the quick start — otherwise fails several
# steps later, as an "invalid reference format" from the Docker daemon that says
# nothing about the cause. Answer the question here instead.
if grep -q '@[A-Z][A-Z0-9_]*@' docker-compose.yml 2>/dev/null; then
	echo "ERROR: these files still carry version placeholders, so they are the" >&2
	echo "       unrendered template rather than a published quick start." >&2
	echo "" >&2
	echo "       Clone the quick start:" >&2
	echo "         git clone https://github.com/klardo-gmbh/klardo-ident.git" >&2
	echo "" >&2
	echo "       Or render this tree with the version it should pin:" >&2
	echo "         make quickstart-render QUICKSTART_OUT=/tmp/quickstart" >&2
	echo "         cd /tmp/quickstart && ./start.sh" >&2
	if [ -f .env ]; then
		echo "" >&2
		echo "       A .env generated from the template is here too, and carries the" >&2
		echo "       same placeholders. Delete it: rm .env" >&2
	fi
	exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
	echo "ERROR: 'docker compose' is not available." >&2
	echo "       Install Docker with the Compose plugin: https://docs.docker.com/get-docker/" >&2
	exit 1
fi

# A secret nobody has to think about. openssl is the common case; the kernel's
# random device covers a machine without it, so a missing openssl is not a
# reason to fall back to something guessable.
generate_secret() {
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -base64 32 | tr -d '\n/+=' | cut -c1-32
	else
		LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
	fi
}

generated=no
if [ ! -f .env ]; then
	echo "Writing .env with generated secrets..."
	# Substituted line by line rather than with a single sed: every GENERATE_ME
	# must become a DIFFERENT value, and one sed expression would write one.
	: > .env.tmp
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			*GENERATE_ME*) line="${line%%GENERATE_ME*}$(generate_secret)" ;;
		esac
		printf '%s\n' "$line" >> .env.tmp
	done < .env.example
	mv .env.tmp .env
	chmod 600 .env
	generated=yes
fi

# shellcheck disable=SC1091
set -a; . ./.env; set +a

# An empty entry is not an error: compose falls back to the moving minor tag, so
# say which version is actually about to be pulled rather than printing a blank.
echo "Pulling images (ident ${IDENT_VERSION:-0.4}, admin UI ${ADMINUI_VERSION:-0.5})..."
docker compose pull --quiet

echo "Starting..."
docker compose up -d

# The server runs migrations and seeds the master realm before it listens, so
# "the container is up" is not "the server is ready". Poll the health endpoint.
port="${IDENT_PORT:-8080}"
echo -n "Waiting for the server on :${port} "
ready=no
for _ in $(seq 1 60); do
	if curl -fsS "http://localhost:${port}/health" >/dev/null 2>&1; then
		ready=yes
		break
	fi
	echo -n "."
	sleep 2
done
echo ""

if [ "$ready" != "yes" ]; then
	echo "The server did not become healthy within two minutes. What it logged:" >&2
	docker compose logs --tail 40 kident >&2
	exit 1
fi

cat <<INFO

  KlardoIdent is up.

  Admin console   http://localhost:${ADMIN_UI_PORT:-5174}
  Server          ${SERVER_URL:-http://localhost:${port}}
  Discovery       ${SERVER_URL:-http://localhost:${port}}/realms/master/.well-known/openid-configuration

  Sign in as      ${ADMIN_EMAIL}
INFO

if [ "$generated" = "yes" ]; then
	cat <<INFO
  Password        ${ADMIN_PASSWORD}

  These credentials were generated just now and exist only in .env.
INFO
else
	cat <<'INFO'
  Password        the one in .env (ADMIN_PASSWORD)
INFO
fi

cat <<'INFO'

  Logs            docker compose logs -f kident
  Stop            docker compose down

INFO
