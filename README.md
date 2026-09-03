# KlardoIdent — quick start

Run **KlardoIdent** and its **admin console** on one host with Docker Compose,
in about a minute.

## What KlardoIdent is

KlardoIdent is an **OAuth 2.0 / OpenID Connect authorization server**: the thing
your applications send people to in order to sign in, and the thing that issues
the tokens they then trust.

Point your apps at it instead of building login into each of them, and you get
one place that holds the users, one place that decides who may sign in, and one
set of standard endpoints — `/authorize`, `/token`, `/userinfo`,
`/.well-known/openid-configuration` — that every OIDC library already speaks. No
SDK of ours to adopt: if a framework supports "log in with an OpenID Connect
provider", it supports this.

What it does:

- **Sign-in for your own applications.** Authorization Code with PKCE for web and
  mobile apps and SPAs, client credentials for service-to-service calls,
  refresh tokens, and signed ID tokens and JWKS for verifying them.
- **Registration, login and account pages**, served by the server and themable
  per realm, so an application does not have to build them.
- **Many realms in one install.** A realm is a fully isolated world of its own —
  its own users, its own clients, its own tokens, its own branding. One per
  customer, per environment or per product line; nothing crosses between them.
  Every route is namespaced `/realms/{realm}/…`, and the `master` realm is the
  one that administers the others.
- **An admin API, an admin console and a CLI** over the same surface, so
  everything clickable is also scriptable.

What it is built like: a single static Go binary with MongoDB as its only
dependency — no application server, no plugin runtime, no JVM. It starts in
under a second, holds the login and token paths to a small, deliberate amount of
work per request, and is meant to be operated by people who would rather not
think about their identity provider very often.

**Beta.** KlardoIdent is in beta and versioned `0.x`. It is complete and
conformant enough to run — that is what this quick start is for — but a minor
version bump may still contain breaking changes, called out in the release notes.
Pin an exact version, read the notes before upgrading, and talk to us before
putting it in front of production traffic.

## What this repository is

Nothing but the deployment files — a Compose stack, an env template and a start
script. The software itself is the published image, and these files are
regenerated on every release, so the versions below are always the current ones.

| Component | Image | Version |
|---|---|---|
| Authorization server | `klardo/ident` | `0.4.6` |
| Admin console | `klardo/ident-admin-ui` | `0.5.6` |

Both images are `linux/amd64` and `linux/arm64`, and both are signed (cosign
keyless — see *Verifying the images*).

You never have to look a version number up. `IDENT_VERSION` and
`ADMINUI_VERSION` in `.env` start out pinned to the two above; leave either
**empty** and the stack falls back to that release's **moving minor tag**
(`0.4` / `0.5`), which picks up new patches on every
`docker compose pull` and never crosses into a minor that is allowed to break.
`git pull` in this repository is how the pins move to a newer minor.

## Requirements

- Docker with the Compose plugin (`docker compose version`).
- 2 GB of free memory and ports `8080` and `5174` — both overridable in `.env`.
- Nothing else. MongoDB is part of the stack, started as the single-node replica
  set KlardoIdent needs (it uses transactions, which MongoDB only offers on a
  replica set).

## Start it

```bash
git clone https://github.com/klardo-gmbh/klardo-ident.git
cd klardo-ident
./start.sh
```

`start.sh` writes a `.env` on first run — with a random `JWT_SECRET`, random
client secrets and a random admin password — and then starts the stack. It
prints the credentials it generated; they are in `.env` too, and nowhere else.

Already have a `.env`? It is never overwritten. Edit it and re-run `./start.sh`,
or use `docker compose up -d` directly.

## What you get

| URL | What it is |
|---|---|
| <http://localhost:5174> | the admin console — sign in with the printed credentials |
| <http://localhost:8080> | the server: OAuth 2.0 / OIDC endpoints |
| <http://localhost:8080/health> | health check |
| <http://localhost:8080/realms/master/.well-known/openid-configuration> | discovery document |

Every route is namespaced under its realm — `/realms/{realm}/authorize`,
`/token`, `/userinfo`, `/.well-known/jwks.json` — and `master` is the admin
realm, created on first start from `ADMIN_EMAIL` and `ADMIN_PASSWORD`.

Read the startup banner (`docker compose logs kident`): it prints the resolved
configuration, the admin URL, and the plan and limits the install is running on.
It is the fastest confirmation that the server sees the settings you think it
does.

## Stop it

```bash
docker compose down          # stop, keep the database
docker compose down -v       # stop and delete the database volume
```

## The free plan

An install with no licence runs on the built-in **free plan**, perpetually:
**1 realm, 2 clients, 10 users**. Nothing expires and nothing has to be
requested — it is what this stack starts on.

Larger limits and features such as custom branding come with a licence. Set
`LICENSE_KEY` (or mount a licence file and point `LICENSE_FILE` at it) in
`.env`; the server picks it up at startup and prints the plan on the banner.

An install that can reach the internet reports **aggregate counts only** — plan,
version, host shape, resource totals. No end-user data, and no realm, client or
user identifiers. If you need a deployment that makes no outbound connection at
all, ask us for an air-gapped licence, which carries the exemption; blocking the
endpoint at your firewall gets you retries and log noise instead.

## Upgrading

Versions are pinned in `.env`. Raise them, then:

```bash
docker compose pull
docker compose up -d
```

Or clear `IDENT_VERSION` / `ADMINUI_VERSION` in `.env` and the same two commands
take the newest **patch** of the minor these files were published with. Crossing
to a newer minor is deliberate, because under `0.x` a minor may break: `git pull`
here, read the notes, then pull and restart.

Database migrations run automatically at startup, and skipping versions is
supported — an upgrade from an older release runs every migration in between, in
order, in one start. Take a database backup first regardless.

This is a `0.x` beta line (see *What KlardoIdent is*): a minor bump may contain
breaking changes, and they are named in the release notes. Pin an exact version
rather than a moving tag, and read <https://klardo-ident.com/releases.html>
before upgrading.

## Going to production

This stack is set up for evaluation on `localhost`. Before it faces anyone else:

- **Terminate TLS in front of it** and set `SERVER_URL` to the public HTTPS URL.
  It becomes the `iss` of every token — the single hardest value to change once
  clients exist — and a wrong one fails validation at every relying party.
- **Set `ENVIRONMENT=production`.** Cookies then require HTTPS, which is why the
  evaluation default is not this.
- **Set `ADMIN_UI_ORIGIN`** to the console's public origin, and re-run the admin
  console behind TLS as well. Origins are registered per realm; for realms that
  already exist use `kidentctl` rather than this variable, which is read only
  when a realm is created.
- **Keep `JWT_SECRET` stable.** Rotating it invalidates every issued token.
- **Change the generated admin password** after the first sign-in, and keep
  `ADMIN_CLIENT_SECRET` and `ACCOUNT_CLIENT_SECRET` secret.
- **Run MongoDB with authentication, backups and durable storage.** The MongoDB
  in this stack is a convenience for evaluation, not a database you would trust a
  production identity service to.
- **Pin by digest** rather than by tag for reproducible rollouts.

## Verifying the images

```bash
docker buildx imagetools inspect docker.io/klardo/ident:0.4.6 \
  --format '{{.Manifest.Digest}}'

cosign verify docker.io/klardo/ident:0.4.6 \
  --certificate-identity-regexp '^https://github.com/klardo-gmbh/identcontrol/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The signing identity is the release workflow in the (private) build repository —
the certificate is what you verify against, no repository access needed. The same
two commands work for `docker.io/klardo/ident-admin-ui:0.5.6`.

Both images live on Docker Hub, which needs no account and no registry login to
pull from. Anonymous pulls are rate-limited per source IP, so an install that
pulls from behind a shared egress, or rolls out across many nodes at once, is
better off with a Docker Hub login (`docker login`) or a pull-through mirror than
with the anonymous quota.

## Support

- Security issues: **security@klardo-ident.com** — please do not open a public
  issue.
- Everything else: **support@klardo-ident.com** — include the version you are
  running.
- <https://klardo-ident.com>

Issues in this repository are the right place for problems with **these
deployment files**. The server itself is not developed here.

## Licence

KlardoIdent is proprietary software of Klardo GmbH; use is governed by your
agreement with Klardo GmbH. The deployment files in this repository are provided
for evaluating and running it — see [`LICENSE`](LICENSE).
