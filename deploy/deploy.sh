#!/usr/bin/env bash
# =====================================================================
#  muteebalam.com — one-shot deploy
#
#  Uploads the static site to the VPS, creates a NEW nginx virtual host
#  (no other site is touched) and provisions a fresh Let's Encrypt
#  certificate with certbot over HTTP-01 / webroot.
#
#  Usage:
#      ./deploy/deploy.sh                     # full deploy
#      ./deploy/deploy.sh --files-only        # upload, skip certbot
#      HOST=root@1.2.3.4 ./deploy/deploy.sh   # override target
#
#  Requirements on the local machine : rsync + ssh
#  Requirements on the server        : nginx, certbot, sudo as root
# =====================================================================
set -euo pipefail

HOST="${HOST:-root@137.184.210.97}"
DOMAIN="muteebalam.com"
REMOTE_ROOT="/var/www/${DOMAIN}"
ACME_ROOT="/var/www/letsencrypt"
NGINX_AVAILABLE="/etc/nginx/sites-available/${DOMAIN}.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}.conf"
ACME_EMAIL="${ACME_EMAIL:-mohd.ali.el@gmail.com}"
MODE="${1:-full}"

LOCAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

c_green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
c_blue()  { printf '\033[0;34m%s\033[0m\n' "$*"; }
c_warn()  { printf '\033[0;33m%s\033[0m\n' "$*"; }

c_blue "==> Target: ${HOST}   domain: ${DOMAIN}   root: ${REMOTE_ROOT}"

# ── 0. sanity ────────────────────────────────────────────────────────
ssh -o ConnectTimeout=12 -o BatchMode=yes "${HOST}" 'echo ok' >/dev/null 2>&1 \
  || { c_warn "Cannot reach ${HOST} over SSH. Deploy aborted."; exit 1; }

# ── 1. directories ───────────────────────────────────────────────────
c_blue "==> Preparing directories"
ssh "${HOST}" "mkdir -p '${REMOTE_ROOT}' '${ACME_ROOT}/.well-known/acme-challenge'"

# ── 2. upload site ───────────────────────────────────────────────────
c_blue "==> Uploading site files"
rsync -az --delete --info=stats2 \
  --exclude '.git/' \
  --exclude 'deploy/' \
  --exclude '_audit.html' \
  --exclude '.DS_Store' \
  --exclude '*.secret' \
  "${LOCAL_ROOT}/" "${HOST}:${REMOTE_ROOT}/"

ssh "${HOST}" "chown -R www-data:www-data '${REMOTE_ROOT}' 2>/dev/null || chown -R nginx:nginx '${REMOTE_ROOT}'; find '${REMOTE_ROOT}' -type d -exec chmod 755 {} +; find '${REMOTE_ROOT}' -type f -exec chmod 644 {} +"

# ── 3. nginx: bootstrap vhost (HTTP only, for ACME) ──────────────────
c_blue "==> Installing bootstrap vhost (HTTP only)"
scp -q "${LOCAL_ROOT}/deploy/nginx/${DOMAIN}.http.conf" "${HOST}:${NGINX_AVAILABLE}"

ssh "${HOST}" "set -e
  ln -sfn '${NGINX_AVAILABLE}' '${NGINX_ENABLED}'
  nginx -t
  systemctl reload nginx 2>/dev/null || service nginx reload
"
c_green "    bootstrap vhost live"

if [ "${MODE}" = "--files-only" ]; then
  c_warn "--files-only: skipping certificate provisioning."
  exit 0
fi

# ── 4. certificate ───────────────────────────────────────────────────
c_blue "==> Requesting Let's Encrypt certificate"
ssh "${HOST}" "set -e
  if [ -d '/etc/letsencrypt/live/${DOMAIN}' ]; then
    echo '    existing certificate found — renewing/expanding'
    certbot certonly --webroot -w '${ACME_ROOT}' -d '${DOMAIN}' \
      --email '${ACME_EMAIL}' --agree-tos --no-eff-email \
      --keep-until-expiring --expand --non-interactive
  else
    certbot certonly --webroot -w '${ACME_ROOT}' -d '${DOMAIN}' \
      --email '${ACME_EMAIL}' --agree-tos --no-eff-email \
      --non-interactive
  fi
"
c_green "    certificate issued"

# ── 5. nginx: final vhost (HTTPS) ────────────────────────────────────
c_blue "==> Installing final HTTPS vhost"
scp -q "${LOCAL_ROOT}/deploy/nginx/${DOMAIN}.conf" "${HOST}:${NGINX_AVAILABLE}"

ssh "${HOST}" "set -e
  nginx -t
  systemctl reload nginx 2>/dev/null || service nginx reload
"
c_green "    HTTPS vhost live"

# ── 6. verify ────────────────────────────────────────────────────────
c_blue "==> Verifying"
ssh "${HOST}" "ls -1 /etc/letsencrypt/live/${DOMAIN}/"
echo
curl -s -o /dev/null -w "  http  -> %{http_code} (redirect: %{redirect_url})\n"  "http://${DOMAIN}/"  || true
curl -s -o /dev/null -w "  https -> %{http_code}  %{size_download} bytes  %{time_total}s\n" "https://${DOMAIN}/" || true

c_green "==> Done. https://${DOMAIN}"
