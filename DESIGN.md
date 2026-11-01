---
version: alpha
name: Warmbly Cloudron package
description: Store slides and README banner framing Warmbly's own product screenshots; the upstream web UI is unchanged apart from one sign-in button
colors:
  primary: "#38bdf8"
  eyebrow: "#7dd3fc"
  background-from: "#0b1626"
  background-to: "#0e2340"
  frame-border: "#23395a"
  on-background: "#f8fafc"
  muted: "#a5b4c8"
typography:
  body-md:
    fontFamily: system-ui
    fontSize: 16.5px
    fontWeight: 400
    lineHeight: 1.5
rounded:
  md: 12px
spacing:
  unit: 8px
---

# Warmbly package artwork

## Overview

Deep-navy store slides with a sky-blue accent, taken from Warmbly's own sky
gradient icon, so the white product screenshots stand out. The package does not
re-theme the Warmbly web UI. Its one visible addition is the Cloudron sign-in
button and note on the login screen (`web-extra/cloudron-sso.js`), styled with
the dashboard's own utility classes so it looks native.

## Icon

`logo.png` is 256×256: Warmbly's paper-plane app icon on its sky gradient,
upstream `ios/Warmbly/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png`
at the pinned commit, scaled down with `sips -Z 256`. Do not redraw it or
present the package artwork as official Warmbly material.

## Store slides

`media/listing-1-mailboxes.png` to `media/listing-5-crm.png` are the Cloudron
`mediaLinks`, in that order. Each is 2400×800: a 1200×400 layout (Cloudron's
recommended 3:1) rendered at 2× for high-density screens.

The left third holds copy on the navy gradient: a sky-blue uppercase eyebrow
with the icon ("Warmbly on Cloudron"), a short blue rule, a 34px bold headline
and a 16.5px body line, in the system UI font. The right two thirds frame a
crop of a product screenshot with a 12px top-left radius, a `#23395a` border
and a soft shadow, bleeding off the right and bottom edges.

| Slide | Screenshot | Headline |
|---|---|---|
| 1 | `og-image.jpg` | Warm up every sending mailbox |
| 2 | `campaign-steps.webp` | Multi-step outreach sequences |
| 3 | `dashboard-inbox.png` | Every reply in one inbox |
| 4 | `deliverability.webp` | Deliverability you can see |
| 5 | `deals.webp` | A CRM built in |

The layout, crops and copy live in `media/src/slide.html`.

## README banner

`media/banner.png` is 1280×640 (GitHub's social preview size): the icon,
"Warmbly for Cloudron", one line of copy and three feature bullets beside a
framed crop of `og-image.jpg`. Source: `media/src/banner.html`.

## Rendering

```sh
CHROME=/path/to/chrome-headless-shell scripts/render-store-media.sh
```

Headless Chromium renders the slides at 1200×400 CSS pixels and 2× scale, and
the banner at 1280×640 and 1×. Review every image after rendering.

## Provenance

The images in `media/upstream/` are byte-identical to these files at upstream
commit `63f10ef2d6865469640799309deba39150f140b1` (Warmbly v0.6.70), used under
Apache-2.0:

| File | Upstream path |
|---|---|
| `og-image.jpg` | `site/public/og-image.jpg` |
| `campaign-steps.webp` | `docs/public/guides/campaign-steps.webp` |
| `dashboard-inbox.png` | `docs/assets/dashboard-inbox.png` |
| `deliverability.webp` | `docs/public/guides/deliverability.webp` |
| `deals.webp` | `docs/public/guides/deals.webp` |
| `warmbly-logo-white.png` | `site/public/brand/warmbly-logo-white.png` (kept for reference; not rendered) |

They show upstream's demo data; no real contacts, credentials or private host
names appear. Each claim in the slide copy was checked against upstream's
documentation (mailbox providers, warmup and health scores, sequence steps and
stop on reply, inbox snooze and scheduled sends, inbox placement, deals and
meetings).

The slides and banner were composed on 2026-11-01 by AI DevOps with headless
Chromium. No generative-image service was used. The copy was checked against
upstream's documentation on its default branch on that date (v0.6.70 to
v0.6.71); recheck it when moving the pin. The composition and copy are
this package's (MIT); the interface shown is the Warmbly project's work.

To refresh after a visible upstream UI change, fetch the same files at the new
pinned commit, re-render, review the result, commit the images, then pin
`mediaLinks` to that commit (see [docs/PUBLISHING.md](docs/PUBLISHING.md)).
