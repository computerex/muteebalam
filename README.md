# muteebalam.com

Personal portfolio website for **Syed Muteeb Alam** — Information Security Analyst / SOC Analyst
at Jubilee Life Insurance Company Ltd., Karachi, Pakistan.

Hand-written static site. No framework, no build step, no runtime dependencies.
Deployed on nginx with a Let's Encrypt certificate — see [`deploy/`](deploy/).

---

## What this is

A single-page portfolio covering:

| Section | Contents |
| --- | --- |
| **Hero** | Name, role, location, top credentials, portrait |
| **About** | Professional summary, focus areas, skill groups |
| **Experience** | SOC Analyst · WordPress Developer · Frontend Developer |
| **Certifications** | 9 credentials, 8 with the real certificate scans in a lightbox gallery |
| **Education** | SSUET (BS Computer Science), Bahria Karsaz, Beaconhouse, UIT University |
| **Contact** | Email + copy-to-clipboard, LinkedIn, location |

## Structure

```
.
├── index.html                      # the whole site
├── 404.html
├── favicon.svg
├── site.webmanifest
├── robots.txt
├── sitemap.xml
├── css/
│   ├── fonts.css                   # @font-face for self-hosted webfonts
│   └── style.css                   # all styling
├── fonts/                          # Inter + JetBrains Mono (latin, woff2)
├── js/
│   └── main.js                     # nav, scroll reveal, lightbox, copy email
├── images/
│   ├── headshot.jpg                # 1200 × 1600 portrait
│   ├── headshot-600.jpg            # 600 × 800 (used as the src)
│   ├── headshot-square.jpg         # 900 × 900 avatar crop
│   ├── apple-touch-icon.jpg        # 180 × 180
│   ├── og-image.jpg                # 1200 × 630 social card
│   └── certs/                      # 8 certificate scans + /thumbs (720px)
└── deploy/
    ├── deploy.sh                   # upload + nginx + certbot, one command
    └── nginx/
        ├── muteebalam.com.http.conf  # bootstrap (HTTP only, for ACME)
        └── muteebalam.com.conf       # final (HTTPS)
```

## Design notes

- **No external requests.** Fonts, CSS, JS and images are all served from the
  same origin, so the page works with third-party CDNs blocked and leaks
  nothing to other providers.
- **Typography** — Inter (400–800) for text, JetBrains Mono for labels and
  metadata. Latin subset only, `font-display: swap`.
- **Palette** — near-black navy base (`#070b12`), mint→blue accent gradient
  (`#2ee6c5` → `#4f8cff`) used sparingly for state and hierarchy.
- **Accessibility** — skip link, visible focus rings, semantic landmarks,
  `aria-expanded` on the nav toggle, focus trap + `Esc`/arrow keys in the
  lightbox, `prefers-reduced-motion` respected, and content is never hidden
  when JavaScript is unavailable.
- **Responsive** — verified with zero horizontal overflow from 360 px to
  1440 px. Breakpoints at 1000 px (hero/about collapse), 820 px (mobile nav),
  640 px (single-column cards).

## Images

All photography was processed from the source files:

- The headshot source carried EXIF orientation `6`, so it was rewritten with
  the rotation baked in, then cropped around a detected face box so the
  portrait keeps headroom and the square avatar keeps the face in the upper
  third.
- Certificate scans were resized to 1400 px (full) and 720 px (thumbs) at
  JPEG quality 80.

## Local preview

```bash
python3 -m http.server 8080
# then open http://localhost:8080
```

Any static file server works.

## Deployment

Prerequisites: `ssh` locally; `nginx`, `certbot` and root access on the server.
(The upload uses a `tar` pipeline rather than `rsync`, because macOS ships
`openrsync` which rejects several GNU rsync flags.)

```bash
ACME_EMAIL=you@example.com ./deploy/deploy.sh
```

The ACME contact address is deliberately not committed — pass it in the
environment so no personal email is published in this repository.

The script:

1. Confirms SSH access and aborts before changing anything if it fails.
2. Snapshots `/etc/nginx/sites-available` to `/root/nginx-backup-<timestamp>`.
3. Creates `/var/www/muteebalam.com` and `/var/www/letsencrypt`.
4. Uploads the site via `tar` over SSH (AppleDouble `._*` files excluded).
5. Installs the **HTTP-only** vhost and reloads nginx so ACME can be answered.
6. Runs `certbot certonly --webroot` to issue a brand-new certificate for
   `muteebalam.com`.
7. Swaps in the **HTTPS** vhost, validates with `nginx -t`, then reloads —
   rolling back to the HTTP-only vhost if validation fails.
8. Verifies the redirect, the HTTPS response and the served certificate.

### Live environment (as deployed)

| | |
| --- | --- |
| Host | `137.184.210.97` (`orbiter-mods.com`, DigitalOcean) |
| OS | Ubuntu 20.04.4 LTS |
| nginx | 1.18.0 — requires `listen 443 ssl http2`, **not** the newer `http2 on;` |
| certbot | 0.40.0, `certbot.timer` enabled |
| Docroot | `/var/www/muteebalam.com` (39 files, ~3.6 MB) |
| Certificate | `/etc/letsencrypt/live/muteebalam.com/` — Let's Encrypt, 90 days, HTTP-01 webroot |
| Co-existing sites | 17 other vhosts on the same server, all untouched |

### Non-disruptive by design

- The vhost is a **new file**: `/etc/nginx/sites-available/muteebalam.com.conf`,
  enabled by symlink. No other `sites-enabled` entry is read or modified —
  verified with a recursive `diff` against the pre-deploy snapshot.
- `nginx -t` runs before every reload, and the reload is a *reload*
  (`systemctl reload nginx`), not a restart, so existing connections to other
  sites are unaffected.
- If `nginx -t` fails, the script restores the previous vhost and reloads, so a
  bad config can never be left enabled.
- The certificate is issued with `certonly`, so certbot does not edit any nginx
  configuration on its own.

### Renewal

Certbot installs its own systemd timer (`certbot.timer`), which renews via the
same webroot. Because the private key and chain paths are `/etc/letsencrypt/live/…`,
nginx picks up the renewed certificate on the next reload. Confirm with:

```bash
systemctl list-timers | grep certbot
certbot renew --dry-run
```

## Updating content

Everything lives in `index.html`:

| To change | Look for |
| --- | --- |
| Email address | `mailto:syedmuteebalam@gmail.com` and `data-email="…"` on the copy button |
| LinkedIn URL | `https://www.linkedin.com/in/syed-muteeb-alam-a18157260/` |
| Job titles / dates | the `Experience` section `<ol class="timeline">` |
| A certificate | the `.cert-grid` block — each `<button class="cert-card">` has `data-full`, `data-title` and `data-issuer` |
| Skills | the `.skills` aside |

Remember to update the `<title>`, the meta description, the Open Graph tags and
the JSON-LD `Person` block in `<head>` if the role changes.

## Notes / follow-ups

- **CHFI has no scan.** The Computer Hacking Forensic Investigator certificate
  was announced as a PDF on LinkedIn; no image was available, so it appears as
  a designed "featured credential" card rather than a gallery item. Drop a scan
  at `images/certs/chfi.jpg` (+ `thumbs/chfi.jpg`) and add a matching
  `.cert-card` to include it in the lightbox.
- **`www.muteebalam.com`** has no DNS record yet. The HTTP vhost already lists
  it in `server_name`, so once an `A` record is added the redirect works;
  re-run the certificate step with `-d www.muteebalam.com` to add it to the
  certificate.

---

© Syed Muteeb Alam · muteebalam.com
