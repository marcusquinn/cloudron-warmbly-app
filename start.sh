#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn
#
# Builds Warmbly's configuration from Cloudron addons, persistent secrets and
# the operator file /app/data/env, renders the dashboard and admin runtime
# config, then runs every service under supervisord. Addon values are re-read
# on each start.
set -euo pipefail
umask 077

readonly DATA=/app/data
readonly RUNDIR=/run/warmbly
readonly SECRETS="${DATA}/.secrets.env"
readonly OPERATOR_ENV="${DATA}/env"

log() {
	printf '==> %s\n' "$*"
	return 0
}

die() {
	printf 'warmbly start: %s\n' "$*" >&2
	exit 1
}

mkdir -p "${DATA}/blobs" "${DATA}/nats" "${DATA}/worker" "${DATA}/geo" \
	"${RUNDIR}/web" "${RUNDIR}/admin" /run/realtime /run/supervisor \
	/run/nginx/client-body /run/nginx/proxy /run/nginx/fastcgi /run/nginx/scgi /run/nginx/uwsgi

# ── secrets: generated once, kept with the data (backed up by Cloudron) ──────
# CREDENTIALS_ENCRYPTION_KEY and KMS_LOCAL_MASTER_KEY seal every mailbox
# credential and per-organization key; losing them makes those unrecoverable.
# Same generators and sizes as upstream's install.sh.
if [[ ! -f "${SECRETS}" ]]; then
	log "Generating instance secrets"
	{
		printf 'AUTH_SECRET=%s\n' "$(openssl rand -hex 32)"
		printf 'CREDENTIALS_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)"
		printf 'KMS_LOCAL_MASTER_KEY=%s\n' "$(openssl rand -base64 32 | tr -d '\n')"
		printf 'INTERNAL_API_TOKEN=%s\n' "$(openssl rand -hex 32)"
		printf 'NODE_BROKER_TOKEN=%s\n' "$(openssl rand -hex 32)"
		printf 'SECRET_KEY_BASE=%s\n' "$(openssl rand -hex 48)"
		printf 'WORKER_ID=%s\n' "$(cat /proc/sys/kernel/random/uuid)"
	} >"${SECRETS}.tmp"
	mv "${SECRETS}.tmp" "${SECRETS}"
fi

read_secret() {
	local name="$1"
	local pattern="$2"
	local value
	value="$(sed -n "s/^${name}=//p" "${SECRETS}" | head -n1)"
	[[ "${value}" =~ ${pattern} ]] || die "secret ${name} missing or malformed in ${SECRETS}"
	printf '%s' "${value}"
	return 0
}

AUTH_SECRET="$(read_secret AUTH_SECRET '^[0-9a-f]{64}$')"
CREDENTIALS_ENCRYPTION_KEY="$(read_secret CREDENTIALS_ENCRYPTION_KEY '^[0-9a-f]{64}$')"
KMS_LOCAL_MASTER_KEY="$(read_secret KMS_LOCAL_MASTER_KEY '^[A-Za-z0-9+/]{43}=$')"
INTERNAL_API_TOKEN="$(read_secret INTERNAL_API_TOKEN '^[0-9a-f]{64}$')"
NODE_BROKER_TOKEN="$(read_secret NODE_BROKER_TOKEN '^[0-9a-f]{64}$')"
SECRET_KEY_BASE="$(read_secret SECRET_KEY_BASE '^[0-9a-f]{96}$')"
WORKER_ID="$(read_secret WORKER_ID '^[0-9a-f-]{36}$')"
export AUTH_SECRET CREDENTIALS_ENCRYPTION_KEY KMS_LOCAL_MASTER_KEY INTERNAL_API_TOKEN \
	NODE_BROKER_TOKEN SECRET_KEY_BASE WORKER_ID

# ── operator settings: defaults first, then /app/data/env ───────────────────
if [[ ! -f "${OPERATOR_ENV}" ]]; then
	cp /app/code/env.template "${OPERATOR_ENV}"
fi

# Defaults the operator may override in /app/data/env.
export DISABLE_REGISTRATION=invite_only
export AUTH_LOGIN_CODE=off
export REQUIRE_EMAIL_VERIFICATION=false
export UPDATE_CHECK_ENABLED=false

# Settings the package owns: addon wiring, URLs, listeners, providers, secrets.
readonly PROTECTED_KEYS=" APP_ENV DEPLOYMENT_MODE AWS_CONFIG_ENABLED EVENTBUS_PROVIDER NATS_URL CODEC_PROVIDER REDIS REDIS_URL PRIMARY_DB DATABASE_URL DATABASE_SSL KMS_PROVIDER KMS_LOCAL_MASTER_KEY KMS_LOCAL_MASTER_KEY_FILE CREDENTIALS_ENCRYPTION_KEY BLOB_PROVIDER BLOB_FS_ROOT BLOB_PUBLIC_BASE_URL TASKS_PROVIDER PUBSUB_ENABLED BILLING_PROVIDER AUTH_SECRET JWT_SECRET SECRET_KEY_BASE INTERNAL_API_TOKEN NODE_BROKER_TOKEN ENCRYPTED_KEYS_PROVIDER ENCRYPTED_KEYS_BACKEND_URL ENCRYPTED_KEYS_WORKER_TOKEN WORKER_ID WORKER_STATE_DIR APP_URL API_PUBLIC_URL API_HOST CORS_ALLOW_ORIGINS TRUSTED_PROXIES WEBSOCKET_URL TRACKING_DOMAIN FORMS_DOMAIN TRACKING_HOST TRACKING_PORT TRACKING_TRUSTED_PROXIES BACKEND_INTERNAL_URL FORMS_PORT FORMS_STATIC_DIR PHX_HOST PORT CHECK_ORIGIN_HOSTS UPDATER_URL OIDC_ISSUER_URL OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_REDIRECT_URL RELEASE_COOKIE RELEASE_TMP RELEASE_DISTRIBUTION "

# KEY=value lines, values literal (never evaluated); optional matching quotes removed.
while IFS= read -r line || [[ -n "${line}" ]]; do
	line="${line%$'\r'}"
	[[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
	if [[ ! "${line}" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
		printf 'warmbly start: ignoring malformed line in %s\n' "${OPERATOR_ENV}" >&2
		continue
	fi
	key="${BASH_REMATCH[1]}"
	value="${BASH_REMATCH[2]}"
	if [[ "${PROTECTED_KEYS}" == *" ${key} "* ]]; then
		printf 'warmbly start: %s is managed by the package; ignoring it in %s\n' "${key}" "${OPERATOR_ENV}" >&2
		continue
	fi
	if [[ "${value}" =~ ^\"(.*)\"$ || "${value}" =~ ^\'(.*)\'$ ]]; then
		value="${BASH_REMATCH[1]}"
	fi
	export "${key}=${value}"
done <"${OPERATOR_ENV}"

# ── domains ─────────────────────────────────────────────────────────────────
: "${CLOUDRON_APP_ORIGIN:?}" "${CLOUDRON_APP_DOMAIN:?}" "${CLOUDRON_POSTGRESQL_URL:?}" "${CLOUDRON_REDIS_URL:?}"
: "${API_DOMAIN:?API_DOMAIN (secondary domain) is not set}"
: "${ADMIN_DOMAIN:?ADMIN_DOMAIN (secondary domain) is not set}"
: "${TRACK_DOMAIN:?TRACK_DOMAIN (secondary domain) is not set}"
: "${FORM_DOMAIN:?FORM_DOMAIN (secondary domain) is not set}"
readonly hostname_re='^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$'
for host in "${CLOUDRON_APP_DOMAIN}" "${API_DOMAIN}" "${ADMIN_DOMAIN}" "${TRACK_DOMAIN}" "${FORM_DOMAIN}"; do
	[[ "${host}" =~ ${hostname_re} ]] || die "${host} is not a domain name the package accepts"
done

readonly APP_ORIGIN="https://${CLOUDRON_APP_DOMAIN}"
readonly API_ORIGIN="https://${API_DOMAIN}"
readonly ADMIN_ORIGIN="https://${ADMIN_DOMAIN}"

# ── package-owned settings (upstream's self-host compose, adapted) ──────────
export APP_ENV=prod
export DEPLOYMENT_MODE=self_hosted
export AWS_CONFIG_ENABLED=false
export EVENTBUS_PROVIDER=nats
export NATS_URL=nats://127.0.0.1:4222
export CODEC_PROVIDER=json
export KMS_PROVIDER=local
export BLOB_PROVIDER=filesystem
export BLOB_FS_ROOT="${DATA}/blobs"
export TASKS_PROVIDER=local
export PUBSUB_ENABLED=false
export BILLING_PROVIDER=none
export CAPTCHA_PROVIDER="${CAPTCHA_PROVIDER:-none}"
export UPDATER_URL=none
unset KMS_LOCAL_MASTER_KEY_FILE

case "${CLOUDRON_POSTGRESQL_URL}" in
*\?*) export PRIMARY_DB="${CLOUDRON_POSTGRESQL_URL}&sslmode=disable" ;;
*) export PRIMARY_DB="${CLOUDRON_POSTGRESQL_URL}?sslmode=disable" ;;
esac
export REDIS="${CLOUDRON_REDIS_URL}"

export APP_URL="${APP_ORIGIN}"
export API_PUBLIC_URL="${API_ORIGIN}"
export BLOB_PUBLIC_BASE_URL="${API_ORIGIN}/public"
export CORS_ALLOW_ORIGINS="${APP_ORIGIN},${ADMIN_ORIGIN}"
export API_HOST=127.0.0.1:8080
export GIN_MODE=release
# Every service sits behind the internal nginx, which forwards the client
# address Cloudron's proxy recorded. Only loopback may set it.
export TRUSTED_PROXIES=127.0.0.1/32
export TRACKING_TRUSTED_PROXIES=127.0.0.1/32
# The API proxies browser sockets to the gateway on its own origin
# (/v1/realtime/socket/websocket), so the gateway needs no public host.
export WEBSOCKET_URL=ws://127.0.0.1:4000/socket/websocket
export TRACKING_DOMAIN="${TRACK_DOMAIN}"
export FORMS_DOMAIN="${FORM_DOMAIN}"
export GEODB_PATH="${GEODB_PATH:-${DATA}/geo/GeoLite2-City.mmdb}"
export BACKEND_INTERNAL_URL=http://127.0.0.1:8080
export TRACKING_HOST=127.0.0.1
export TRACKING_PORT=3000
export FORMS_PORT=8090
export FORMS_STATIC_DIR=/app/code/forms-static
export WORKER_STATE_DIR="${DATA}/worker"

# Realtime gateway (Phoenix). JWT_SECRET must equal AUTH_SECRET.
export PHX_HOST="${API_DOMAIN}"
export DATABASE_URL="${CLOUDRON_POSTGRESQL_URL}"
export DATABASE_SSL=false
export REDIS_URL="${CLOUDRON_REDIS_URL}"
export JWT_SECRET="${AUTH_SECRET}"
export CHECK_ORIGIN_HOSTS="${APP_ORIGIN},${ADMIN_ORIGIN}"
export PHX_SERVER=true
export RELEASE_TMP=/run/realtime
export RELEASE_DISTRIBUTION=none
RELEASE_COOKIE="$(printf '%s' "warmbly-realtime-cookie:${SECRET_KEY_BASE}" | sha256sum | cut -c1-64)"
export RELEASE_COOKIE
WARMBLY_RELEASE="$(cat /app/code/upstream-version)"
export WARMBLY_RELEASE

# Cloudron single sign-on (oidc addon). The callback is served on the app
# domain too (internal nginx), because Cloudron registers redirect URIs there.
if [[ -n "${CLOUDRON_OIDC_ISSUER:-}" && -n "${CLOUDRON_OIDC_CLIENT_ID:-}" ]]; then
	export OIDC_ISSUER_URL="${CLOUDRON_OIDC_ISSUER}"
	export OIDC_CLIENT_ID="${CLOUDRON_OIDC_CLIENT_ID}"
	export OIDC_CLIENT_SECRET="${CLOUDRON_OIDC_CLIENT_SECRET:-}"
	export OIDC_REDIRECT_URL="${APP_ORIGIN}/v1/auth/oidc/callback"
	export OIDC_PROVIDER_NAME="${OIDC_PROVIDER_NAME:-${CLOUDRON_OIDC_PROVIDER_NAME:-Cloudron}}"
	# Cloudron's access control already decides who may sign in, so a
	# Cloudron user's first SSO sign-in creates the account without an
	# invitation. SSO_AUTO_PROVISION=false in /app/data/env restores invites.
	export SSO_AUTO_PROVISION="${SSO_AUTO_PROVISION:-true}"
	# Package patch: on an instance with no accounts, the first Cloudron
	# sign-in becomes the owner and platform admin, so no setup link is
	# needed. Only one owner is ever granted this way.
	# WARMBLY_OIDC_FIRST_USER_OWNER=false in /app/data/env restores the
	# upstream setup-link claim.
	export WARMBLY_OIDC_FIRST_USER_OWNER="${WARMBLY_OIDC_FIRST_USER_OWNER:-true}"
else
	unset OIDC_ISSUER_URL OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_REDIRECT_URL WARMBLY_OIDC_FIRST_USER_OWNER
fi

# Platform email (login codes, resets, invitations, digests) goes through the
# Cloudron relay unless the operator chose MAIL_TRANSPORT/SMTP_HOST in
# /app/data/env. requiresValidCertificate makes CLOUDRON_MAIL_SMTP_SERVER the
# mail FQDN; the host forwards only the STARTTLS relay port to it, so send with
# STARTTLS and certificate verification, never the plain port.
if [[ -z "${SMTP_HOST:-}" && -z "${MAIL_TRANSPORT:-}" && -n "${CLOUDRON_MAIL_SMTP_SERVER:-}" ]]; then
	if [[ -n "${CLOUDRON_MAIL_STARTTLS_PORT:-}" ]]; then
		export MAIL_TRANSPORT=smtp
		export SMTP_HOST="${CLOUDRON_MAIL_SMTP_SERVER}"
		export SMTP_PORT="${CLOUDRON_MAIL_STARTTLS_PORT}"
		export SMTP_USERNAME="${CLOUDRON_MAIL_SMTP_USERNAME}"
		export SMTP_PASSWORD="${CLOUDRON_MAIL_SMTP_PASSWORD}"
		export SMTP_SECURITY=starttls
		export SMTP_AUTH=auto
		export EMAIL_ADDRESS="${EMAIL_ADDRESS:-${CLOUDRON_MAIL_FROM}}"
	else
		log "WARNING: Cloudron provided no STARTTLS relay port; platform email is logged, not sent. Set SMTP_* in ${OPERATOR_ENV} to send it."
	fi
fi
export MAIL_TRANSPORT="${MAIL_TRANSPORT:-log}"
# The backend refuses to start without a sender identity, even when mail is
# only logged.
export EMAIL_ADDRESS="${EMAIL_ADDRESS:-${CLOUDRON_MAIL_FROM:-noreply@${CLOUDRON_APP_DOMAIN}}}"
export EMAIL_NAME="${EMAIL_NAME:-${CLOUDRON_MAIL_FROM_DISPLAY_NAME:-Warmbly}}"

# ── dashboard and admin runtime config (upstream renderers) ─────────────────
cp /app/code/web/csp-template.txt "${RUNDIR}/web/"
[[ -f /app/code/web/csp-origins.txt ]] && cp /app/code/web/csp-origins.txt "${RUNDIR}/web/"
# The dashboard offers Gmail sign-in whenever the backend allows it
# (BOX_GOOGLE_OAUTH_CONNECT is read by the backend only).
WARMBLY_CONFIG_OUT="${RUNDIR}/web/config.js" \
	WARMBLY_API_URL="${API_ORIGIN}" \
	WARMBLY_APP_URL="${APP_ORIGIN}" \
	WEBSOCKET_URL="wss://${API_DOMAIN}/v1/realtime/socket/websocket" \
	sh /app/code/upstream/web-config.sh
# The renderer only patches the nginx header file at its default path; apply
# the same substitution to our copy.
CSP_POLICY="$(cat "${RUNDIR}/web/csp-policy.txt")" awk \
	'/^add_header Content-Security-Policy/ { print "add_header Content-Security-Policy \"" ENVIRON["CSP_POLICY"] "\" always;"; next } { print }' \
	/app/code/upstream/web-security-headers.conf >"${RUNDIR}/web-security-headers.conf"
WARMBLY_CONFIG_OUT="${RUNDIR}/admin/config.js" \
	WARMBLY_API_URL="${API_ORIGIN}" \
	WARMBLY_DASHBOARD_URL="${APP_ORIGIN}" \
	WARMBLY_ENV_LABEL="${ENV_LABEL:-production}" \
	sh /app/code/upstream/admin-config.sh

sed -e "s/@APP_DOMAIN@/${CLOUDRON_APP_DOMAIN}/g" /app/code/nginx.conf.template >"${RUNDIR}/nginx.conf"

# The CLI wrapper (bin/warmblyctl) reads the same environment.
export -p >"${RUNDIR}/env.tmp"
chmod 0600 "${RUNDIR}/env.tmp"
mv "${RUNDIR}/env.tmp" "${RUNDIR}/env"

sso=off
[[ -n "${OIDC_ISSUER_URL:-}" ]] && sso=on
log "Warmbly ${WARMBLY_RELEASE} at ${APP_ORIGIN} (api ${API_ORIGIN}, admin ${ADMIN_ORIGIN}, tracking ${TRACK_DOMAIN}, forms ${FORM_DOMAIN}; platform mail: ${MAIL_TRANSPORT}, sso: ${sso})"

chown -R cloudron:cloudron "${DATA}" /run/realtime /run/nginx
chmod -R a+rX "${RUNDIR}/web" "${RUNDIR}/admin"
chmod 0644 "${RUNDIR}/nginx.conf" "${RUNDIR}/web-security-headers.conf"
chmod 0711 "${RUNDIR}"
chown root:root "${RUNDIR}/env"
chmod 0600 "${SECRETS}" "${OPERATOR_ENV}"

exec /usr/bin/supervisord --configuration /app/code/supervisord.conf --nodaemon
