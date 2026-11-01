#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Render the Cloudron store slides (media/listing-N-name.png, 2400x800) from
# media/src/slide.html, and the README/social banner (media/banner.png,
# 1280x640) from media/src/banner.html, using the upstream screenshots in
# media/upstream/.
# Usage: CHROME=/path/to/chrome-headless-shell scripts/render-store-media.sh
set -euo pipefail

render_page() {
    local chrome="$1"
    local url="$2"
    local out="$3"
    local size="$4"
    local scale="$5"
    local tmp
    # Render into a fresh directory, so a stale or read-only destination can
    # never pass for this run's output; replace the destination only on success.
    tmp="$(mktemp -d)" || return 1
    if ! "$chrome" --headless --disable-gpu --hide-scrollbars --allow-file-access-from-files \
        --window-size="$size" --force-device-scale-factor="$scale" --virtual-time-budget=3000 \
        --screenshot="${tmp}/out.png" "$url" >/dev/null 2>&1 || ! test -s "${tmp}/out.png"; then
        rm -rf "$tmp"
        printf 'Failed to render %s\n' "$out" >&2
        return 1
    fi
    if ! mv -f "${tmp}/out.png" "$out"; then
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    printf 'Rendered %s\n' "$out"
    return 0
}

render_slide() {
    local chrome="$1"
    local root="$2"
    local number="$3"
    local name="$4"
    render_page "$chrome" "file://${root}/media/src/slide.html#${number}" \
        "${root}/media/listing-${number}-${name}.png" 1200,400 2 || return 1
    return 0
}

main() {
    local root chrome
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    chrome="${CHROME:-}"
    if [[ -z "$chrome" ]]; then
        chrome="$(command -v chrome-headless-shell || command -v chromium || true)"
    fi
    [[ -n "$chrome" && -x "$chrome" ]] || { printf 'Set CHROME to a headless Chromium binary\n' >&2; return 1; }
    render_slide "$chrome" "$root" 1 mailboxes || return 1
    render_slide "$chrome" "$root" 2 campaigns || return 1
    render_slide "$chrome" "$root" 3 inbox || return 1
    render_slide "$chrome" "$root" 4 deliverability || return 1
    render_slide "$chrome" "$root" 5 crm || return 1
    render_page "$chrome" "file://${root}/media/src/banner.html" \
        "${root}/media/banner.png" 1280,640 1 || return 1
    return 0
}

main "$@"
