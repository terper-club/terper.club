#!/bin/sh
# tools/check.sh: structural checks for terper.club.
#
# This is a testing aid, not a build step. The site is a set of plain HTML
# files and works without it. Run it after editing pages by hand:
#
#     sh tools/check.sh
#
# Exits 0 if every check passes, 1 otherwise.

set -u
cd "$(dirname "$0")/.." || exit 1
fail=0

ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }

# have <path> <label>: assert a file exists and is non-empty
have() {
    if [ -s "$1" ]; then ok "$2"; else bad "$2 (missing or empty: $1)"; fi
}

# --- Task 1: assets ---
printf '\nAssets\n'

have fonts/oxanium-var.woff2 'Oxanium variable font present'
have fonts/jost-var.woff2    'Jost variable font present'
have fonts/OFL-Oxanium.txt   'Oxanium licence shipped'
have fonts/OFL-Jost.txt      'Jost licence shipped'
have media/logo-alpha.png    'Transparent wordmark present'

for f in fonts/oxanium-var.woff2 fonts/jost-var.woff2; do
    if [ -s "$f" ] && [ "$(dd if="$f" bs=1 count=4 2>/dev/null)" = "wOF2" ]; then
        ok "$f is real woff2"
    else
        bad "$f is not woff2 (wrong magic bytes)"
    fi
done

# %A reports Blend when an alpha channel is present and Undefined when it is
# not. Do NOT test %[channels] for the letter 'a'; an opaque grayscale PNG
# reports "gray", which contains an 'a' and would pass a substring match.
if [ -s media/logo-alpha.png ] && \
   [ "$(magick identify -format '%A' media/logo-alpha.png 2>/dev/null)" = "Blend" ]; then
    ok 'Wordmark has an alpha channel'
else
    bad 'Wordmark has no alpha channel'
fi

# Originals must survive.
have media/logo_bw.png 'Original logo_bw.png kept'
have media/logo.png    'Original logo.png kept'

# --- Task 2: stylesheet ---
printf '\nStylesheet\n'

have css/terper.css 'css/terper.css present'

if [ -s css/terper.css ]; then
    opens=$(tr -cd '{' < css/terper.css | wc -c | tr -d ' ')
    closes=$(tr -cd '}' < css/terper.css | wc -c | tr -d ' ')
    if [ "$opens" = "$closes" ]; then
        ok "Braces balanced ($opens pairs)"
    else
        bad "Braces unbalanced: $opens open, $closes close"
    fi

    for token in '--shell:' '--ink:' '--dim:' '--accent:' '--hair:'; do
        if grep -q -- "$token" css/terper.css; then
            ok "Token $token defined"
        else
            bad "Token $token missing"
        fi
    done

    for val in '#0A0C0C' '#C3CBC8' '#8B948F' '#5FBFAE'; do
        if grep -qi -- "$val" css/terper.css; then
            ok "Palette value $val present"
        else
            bad "Palette value $val missing"
        fi
    done

    if grep -qE 'url\((["'"'"']?)https?:' css/terper.css; then
        bad 'Stylesheet loads a remote url()'
    else
        ok 'Stylesheet loads nothing remote'
    fi

    if grep -q 'logo-alpha.png' css/terper.css; then
        ok 'Wordmark wired to a CSS mask'
    else
        bad 'Wordmark not referenced'
    fi
fi

printf '\n'
[ "$fail" -eq 0 ] && printf 'All checks passed.\n' || printf 'Some checks FAILED.\n'
exit "$fail"
