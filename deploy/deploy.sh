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
#      HOST=root@1.2.3.4  ./deploy/deploy.sh  # override target
#      SSH_KEY=~/.ssh/x   ./deploy/deploy.sh  # override identity
#
#  Local requirements : rsync + ssh
#  Server requirements: nginx, certbot, root access
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

# Optional identity override: SSH_KEY=/path/to/key ./deploy/deploy.sh
SSH_CMD=(ssh -o ConnectTimeout=12 -o BatchMode=yes)
SCP_CMD=(scp -q -o ConnectTimeout=12 -o BatchMode=yes)
if [ -n "${SSH_KEY:-}" ]; then
  SSH_CMD+=(-i "${SSH_KEY}" -o IdentitiesOnly=yes)
  SCP_CMD+=(-i "${SSH_KEY}" -o IdentitiesOnly=yes)
fi
TAR_EXCLUDES=(--exclude='.git' --exclude='./deploy' --exclude='_audit*.html'
              --exclude='.DS_Store' --exclude='._*' --exclude='*.secret')

LOCAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

c_green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
c_blue()  { printf '\033[0;34m%s\033[0m\n' "$*"; }
c_warn()  { printf '\033[0;33m%s\033[0m\n' "$*"; }
c_err()   { printf '\033[0;31m%s\033[0m\n' "$*"; }

remote() { "${SSH_CMD[@]}" "${HOST}" "$@"; }

c_blue "==> Target: ${HOST}   domain: ${DOMAIN}   root: ${REMOTE_ROOT}"

# ── 0. sanity ────────────────────────────────────────────────────────
if ! remote 'echo ok' >/dev/null 2>&1; then
  c_err "Cannot authenticate to ${HOST} over SSH. Deploy aborted — nothing was changed."
  cat <<'EOS'

  Fix SSH access first, then re-run. Any one of these works:

  (a) install this machine's public key on the server (one time, asks for password):

        ssh-copy-id -i ~/.ssh/id_ed25519.pub root@137.184.210.97

  (b) add the key in the DigitalOcean control panel
      (Settings -> Security -> SSH Keys) and ensure the droplet has it in
      /root/.ssh/authorized_keys,

  (c) point the script at a working key or host:

        SSH_KEY=~/.ssh/other_key ./deploy/deploy.sh
        HOST=root@1.2.3.4        ./deploy/deploy.sh

  Verify with:  ssh root@137.184.210.97 'echo ok'

EOS
  exit 1
fi

# ── 1. directories + config snapshot ─────────────────────────────────
c_blue "==> Preparing directories"
remote "mkdir -p '${REMOTE_ROOT}' '${ACME_ROOT}/.well-known/acme-challenge'
        chmod 755 '${ACME_ROOT}' '${ACME_ROOT}/.well-known' '${ACME_ROOT}/.well-known/acme-challenge'"

c_blue "==> Snapshotting current nginx configs (rollback point)"
BACKUP_DIR="$(remote "mkdir -p /root/nginx-backup-\$(date +%Y%m%d-%H%M%S) && echo /root/nginx-backup-\$(date +%Y%m%d-%H%M%S)" || true)"
remote "cp -a /etc/nginx/sites-available/. '${BACKUP_DIR:-/tmp}/' 2>/dev/null || true"
c_green "    snapshot: ${BACKUP_DIR:-<none>}"

# ── 2. upload site ───────────────────────────────────────────────────
# A tar pipeline is used instead of rsync: macOS ships openrsync (protocol
# 29) which rejects several GNU rsync flags, and tar behaves identically
# everywhere. The remote extract is preceded by a guarded clear so removed
# files don't linger.
c_blue "==> Uploading site files"
tar -czf - -C "${LOCAL_ROOT}" "${TAR_EXCLUDES[@]}" . \
  | remote "set -e
           mkdir -p '${REMOTE_ROOT}'
           find '${REMOTE_ROOT}' -mindepth 1 -delete
           tar -xzf - -C '${REMOTE_ROOT}'"

remote "set -e
        find '${REMOTE_ROOT}' -type d -exec chmod 755 {} +
        find '${REMOTE_ROOT}' -type f -exec chmod 644 {} +
        if id www-data >/dev/null 2>&1; then chown -R www-data:www-data '${REMOTE_ROOT}'
        elif id nginx >/dev/null 2>&1; then chown -R nginx:nginx '${REMOTE_ROOT}'; fi
        echo \"    \$(find '${REMOTE_ROOT}' -type f | wc -l) files, \$(du -sh '${REMOTE_ROOT}' | cut -f1)\""

# ── 3. nginx: bootstrap vhost (HTTP only, so ACME can be answered) ───
c_blue "==> Installing bootstrap vhost (HTTP only)"
"${SCP_CMD[@]}" "${LOCAL_ROOT}/deploy/nginx/${DOMAIN}.http.conf" "${HOST}:${NGINX_AVAILABLE}"

remote "set -e
        ln -sfn '${NGINX_AVAILABLE}' '${NGINX_ENABLED}'
        nginx -t
        systemctl reload nginx 2>/dev/null || service nginx reload"
c_green "    bootstrap vhost live"

if [ "${MODE}" = "--files-only" ]; then
  c_warn "--files-only: skipping certificate provisioning."
  exit 0
fi

# ── 4. certificate (brand new, HTTP-01 via webroot) ──────────────────
c_blue "==> Requesting Let's Encrypt certificate"
remote "set -e
        if [ -d '/etc/letsencrypt/live/${DOMAIN}' ]; then
          echo '    existing certificate found — keeping it if still valid'
          certbot certonly --webroot -w '${ACME_ROOT}' -d '${DOMAIN}' \
            --email '${ACME_EMAIL}' --agree-tos --no-eff-email \
            --keep-until-expiring --expand --non-interactive
        else
          certbot certonly --webroot -w '${ACME_ROOT}' -d '${DOMAIN}' \
            --email '${ACME_EMAIL}' --agree-tos --no-eff-email \
            --non-interactive
        fi"
c_green "    certificate ready"

# ── 5. nginx: final vhost (HTTPS) ────────────────────────────────────
# The config is validated before reloading. If it does not validate the
# script restores the bootstrap file and reloads, so a broken config can
# never be left enabled.
c_blue "==> Installing final HTTPS vhost"
"${SCP_CMD[@]}" "${LOCAL_ROOT}/deploy/nginx/${DOMAIN}.conf" "${HOST}:${NGINX_AVAILABLE}"

if remote "nginx -t" >/dev/null 2>&1; then
  remote "systemctl reload nginx 2>/dev/null || service nginx reload"
  c_green "    HTTPS vhost live"
else
  c_err "nginx rejected the final config — restoring the HTTP-only vhost"
  remote "cat /tmp/nginxt.log 2>/dev/null || true"
  "${SCP_CMD[@]}" "${LOCAL_ROOT}/deploy/nginx/${DOMAIN}.http.conf" "${HOST}:${NGINX_AVAILABLE}"
  remote "nginx -t && (systemctl reload nginx 2>/dev/null || service nginx reload)"
  c_warn "rolled back; site still reachable over HTTP. Certificate is installed and valid."
  exit 1
fi

# ── 6. verify ────────────────────────────────────────────────────────
c_blue "==> Verifying"
remote "ls -1 /etc/letsencrypt/live/${DOMAIN}/"
echo
curl -s -o /dev/null -w "  http  -> %{http_code}  redirect=%{redirect_url}\n" "http://${DOMAIN}/" || true
curl -s -o /dev/null -w "  https -> %{http_code}  %{size_download} bytes  %{time_total}s\n" "https://${DOMAIN}/" || true
echo
echo "  serving certificate:"
echo | openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates 2>/dev/null | sed 's/^/    /' || true

c_green "==> Done. https://${DOMAIN}"
echo
c_warn "Renewal is automatic via certbot.timer. To verify it manually (can take ~30s):"
echo "    ssh ${HOST} 'certbot renew --dry-run --cert-name ${DOMAIN}'"
