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
        ok "Brace counts match ($opens each)"
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

    if grep -qiE 'url\((["'"'"']?)(https?:|//)' css/terper.css; then
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

# --- Task 3: homepage ---
printf '\nHomepage\n'

if grep -q 'class="splash"' index.html; then
    ok 'Homepage uses the splash body class'
else
    bad 'Homepage is not a splash'
fi

if grep -q 'terper_pool_bw2.jpg' index.html; then
    ok 'Homepage shows the pool photograph'
else
    bad 'Homepage photograph missing'
fi

if grep -q '<h1 class="sr-only">' index.html; then
    ok 'Homepage carries a heading for screen readers'
else
    bad 'Homepage has no h1'
fi

navcount=$(grep -oE 'href="\./(art|live|releases|bio|contact)"' index.html | wc -l | tr -d ' ')
if [ "$navcount" -eq 5 ]; then
    ok 'Homepage nav has all five links'
else
    bad "Homepage nav has $navcount of 5 links"
fi

if grep -q 'jquery' index.html; then
    bad 'jQuery still referenced on the homepage'
else
    ok 'jQuery gone from the homepage'
fi

if grep -qE '<(footer|div id="footer")' index.html; then
    bad 'Homepage should have no footer'
else
    ok 'Homepage has no footer'
fi

# --- Task 4: category pages ---
printf '\nCategory pages\n'

have art.html      'art.html present'
have live.html     'live.html present'
have releases.html 'releases.html present'

check_tiles() {
    [ -s "$1" ] || return 0
    n=$(grep -o 'class="tile"' "$1" | wc -l | tr -d ' ')
    if [ "$n" -eq "$2" ]; then
        ok "$1 has $2 tiles"
    else
        bad "$1 has $n tiles, expected $2"
    fi
}

check_tiles art.html 8
check_tiles live.html 3
check_tiles releases.html 3

# Art and Live tiles must open pages on this site. The allow-list check
# cannot catch an off-site tile, because every plausible destination is
# already an allowed host. releases.html is deliberately excluded: its
# three tiles point at Bandcamp and SoundCloud by design.
offsite=$(grep -hoE '<a class="tile" href="[^"]*"' art.html live.html 2>/dev/null \
          | grep -vE 'href="\./' || true)
if [ -z "$offsite" ]; then
    ok 'Every Art and Live tile links inside the site'
else
    bad "Off-site tile: $(echo "$offsite" | tr '\n' ' ')"
fi

if [ -s live.html ] && grep -q 'terper_dates_late2026.jpg' live.html; then
    ok 'Live page leads with the dates poster'
else
    bad 'Live page is missing the dates poster'
fi

for page in art live; do
    if [ -s "$page.html" ] && grep -q "scroll:$page" "$page.html"; then
        ok "$page.html saves scroll position under scroll:$page"
    else
        bad "$page.html has no scroll restore"
    fi
done

if [ -s releases.html ]; then
    n=$(grep -o 'target="_blank"' releases.html | wc -l | tr -d ' ')
    # 3 tiles + 4 footer links
    if [ "$n" -eq 7 ]; then
        ok 'Releases tiles all open in a new tab'
    else
        bad "releases.html has $n target=_blank links, expected 7"
    fi
fi

# rel=noopener is the floor on every new-tab link, not just releases'.
unsafe=$(grep -ohE '<a [^>]*target="_blank"[^>]*>' ./*.html \
         | grep -v 'rel="noopener' || true)
if [ -z "$unsafe" ]; then
    ok 'Every target=_blank link carries rel=noopener'
else
    bad "target=_blank without noopener: $(echo "$unsafe" | head -3 | tr '\n' ' ')"
fi

# --- Task 5: bio and contact ---
printf '\nBio and Contact\n'

have bio.html     'bio.html present'
have contact.html 'contact.html present'

if grep -rq 'href="linktr.ee' . --include='*.html'; then
    bad 'Protocol-less linktr.ee href still present (resolves relative, 404s)'
else
    ok 'Linktree hrefs all carry a protocol'
fi

if [ -s bio.html ] && grep -q 'https://linktr.ee/ryandmt' bio.html; then
    ok 'RDMT Linktree fixed to https://linktr.ee/ryandmt'
else
    bad 'RDMT Linktree link missing or unfixed'
fi

if [ -s bio.html ] && grep -q 'terper-montage-redBlue-1.jpg' bio.html; then
    ok 'Bio carries the montage image'
else
    bad 'Bio montage image missing'
fi

if [ -s contact.html ] && grep -q 'terper (dot) club (@) gmail (dot) com' contact.html; then
    ok 'Contact carries the obfuscated address'
else
    bad 'Obfuscated address missing or altered'
fi

# --- Task 6: detail pages ---
printf '\nDetail pages\n'

ART_PAGES='mycelium-parlour-1 inorganic-interruptions-1 displacement-2 displacement-1 amygdala-1 tortuga-1 breathing-waves-2 breathing-waves-1'
LIVE_PAGES='terper-live-3 terper-live-2 terper-live-1'

# done_pages lists the pages converted so far; extend it in Tasks 7, 8 and 9.
DONE_PAGES='mycelium-parlour-1 amygdala-1 inorganic-interruptions-1 displacement-2 displacement-1 tortuga-1 breathing-waves-2 breathing-waves-1 terper-live-1 terper-live-2 terper-live-3'

for p in $DONE_PAGES; do
    f="$p.html"
    have "$f" "$f present"
    [ -s "$f" ] || continue

    cat=art
    for l in $LIVE_PAGES; do [ "$l" = "$p" ] && cat=live; done

    if grep -q "href=\"./$cat\" class=\"is-current\"" "$f"; then
        ok "$f lights $cat in the nav"
    else
        bad "$f does not light $cat in the nav"
    fi

    if grep -q 'onclick=' "$f"; then
        bad "$f still has the history.back() onclick hack"
    else
        ok "$f has no inline onclick"
    fi

    if grep -q 'class="project-nav"' "$f"; then
        ok "$f has a project-nav block"
    else
        bad "$f is missing project-nav"
    fi
done

# Francesc Cami shot the NEST Festival photographs and must be credited.
if [ -s mycelium-parlour-1.html ] && grep -q 'Francesc Cami' mycelium-parlour-1.html; then
    ok 'NEST Festival photo credit present'
else
    bad 'NEST Festival photo credit missing'
fi

# No detail page may link outside its own category in prev/next.
for p in $DONE_PAGES; do
    f="$p.html"
    [ -s "$f" ] || continue
    cat=art; peers="$ART_PAGES"
    for l in $LIVE_PAGES; do [ "$l" = "$p" ] && { cat=live; peers="$LIVE_PAGES"; }; done
    # Bound the block by the footer, not by the next closing </div>: the
    # first line matching </div> is the nav-label, one line above the link
    # we are looking for, so a </div>-terminated range finds no hrefs at all
    # and the check passes vacuously on every page.
    strays=$(awk '/class="project-nav"/{f=1} /<footer/{f=0} f' "$f" \
             | grep -oE 'href="\./[a-z0-9-]+"' | sed -E 's|href="\./||; s|"||' || true)
    # Every page in R2 has at least one neighbour, so finding none means the
    # extraction broke again rather than that the page is clean.
    if [ -z "$strays" ]; then
        bad "$f prev/next block yielded no links; extraction is broken"
        continue
    fi
    bad_link=''
    for s in $strays; do
        found=0
        for peer in $peers; do [ "$peer" = "$s" ] && found=1; done
        [ "$found" -eq 0 ] && bad_link="$bad_link $s"
    done
    if [ -z "$bad_link" ]; then
        ok "$f prev/next stays inside $cat"
    else
        bad "$f prev/next leaves $cat:$bad_link"
    fi
done

# Category membership is not order. Walk both chains and assert every
# adjacent pair is symmetric: A's Next is B and B's Previous is A.
# grep -oE (not sed) because BSD sed cannot take `t` with a `;` after it,
# and because an empty result is exactly what a chain endpoint should give.
nav_target() {   # $1 = file, $2 = Previous|Next
    tr '\n' ' ' < "$1" \
      | grep -oE "nav-label\">$2</div>[^<]*<a href=\"\./[a-zA-Z0-9._-]+\"" \
      | sed -E 's|.*href="\./||; s|"$||'
}

check_chain() {   # $1 = chain name, rest = pages in order
    name=$1; shift
    prev=''; broken=''
    for page in "$@"; do
        [ -s "$page.html" ] || { broken="$broken $page(missing)"; continue; }
        got_prev=$(nav_target "$page.html" Previous)
        [ "$got_prev" = "$prev" ] || broken="$broken $page.prev=$got_prev/want=$prev"
        prev=$page
    done
    last=$prev
    prev=''
    for page in "$@"; do
        if [ -n "$prev" ]; then
            got_next=$(nav_target "$prev.html" Next)
            [ "$got_next" = "$page" ] || broken="$broken $prev.next=$got_next/want=$page"
        fi
        prev=$page
    done
    end_next=$(nav_target "$last.html" Next)
    [ -z "$end_next" ] || broken="$broken $last.next=$end_next/want=empty"
    if [ -z "$broken" ]; then
        ok "$name chain is in order and symmetric"
    else
        bad "$name chain broken:$broken"
    fi
}

check_chain Art breathing-waves-1 breathing-waves-2 tortuga-1 amygdala-1 \
    displacement-1 displacement-2 inorganic-interruptions-1 mycelium-parlour-1
check_chain Live terper-live-1 terper-live-2 terper-live-3

# --- Task 7: video embeds ---
printf '\nVideo embeds\n'

EMBED_PAGES='terper-live-1 terper-live-2 terper-live-3 tortuga-1 inorganic-interruptions-1 amygdala-1'

# embed_done lists the embed pages converted so far; extend it in Task 8.
EMBED_DONE=$EMBED_PAGES

for p in $EMBED_DONE; do
    f="$p.html"
    [ -s "$f" ] || { bad "$f missing"; continue; }

    if grep -q 'youtube.com/embed/' "$f"; then
        ok "$f carries a YouTube embed"
    else
        bad "$f has no embed"
    fi

    # Flatten before matching: an <iframe> tag legitimately spans several
    # lines, so a line-scoped grep would demand src and loading sit on the
    # same one and reject the very markup this plan writes.
    if tr '\n' ' ' < "$f" | grep -qE \
       '<iframe[^>]*(youtube\.com/embed/[^>]*loading="lazy"|loading="lazy"[^>]*youtube\.com/embed/)'; then
        ok "$f embed is lazy-loaded"
    else
        bad "$f embed is not lazy-loaded"
    fi

    if grep '<iframe' "$f" | grep -qE '(width|height)="[0-9]'; then
        bad "$f iframe still has a hardcoded pixel size"
    else
        ok "$f iframe has no hardcoded size"
    fi

    if grep -qE 'youtube\.com/embed/[A-Za-z0-9_-]+ ' "$f"; then
        bad "$f embed src has a trailing space"
    else
        ok "$f embed src is clean"
    fi
done

# The local .webm must stay inline-playable on iOS. Flatten the file and
# match whole attributes: a line-scoped substring grep would break if the
# tag were ever reflowed, and would accept class="looping" as loop.
if [ -s terper-live-3.html ]; then
    vid=$(tr '\n' ' ' < terper-live-3.html | grep -oE '<video[^>]*>' | head -1)
    for attr in autoplay loop muted playsinline; do
        if printf '%s' "$vid" | grep -qE "(^|[[:space:]])$attr([[:space:]]|>|=)"; then
            ok "terper-live-3 video keeps $attr"
        else
            bad "terper-live-3 video lost $attr"
        fi
    done
fi

# --- Task 10: whole-site invariants ---
printf '\nWhole site\n'

pages=$(ls ./*.html)

# 6 top-level pages + 11 detail pages.
n=$(echo "$pages" | wc -l | tr -d ' ')
if [ "$n" -eq 17 ]; then
    ok '17 page files at the root'
else
    bad "expected 17 root pages, found $n"
fi

# This loop is the script's one summary check: four assertions over every
# page, reported as a single line. Its ok must therefore be earned; an
# unconditional one would print "audited" on the same run it prints FAIL.
# A local flag, not $fail: bad() sets fail=1 stickily, so a failure in any
# earlier section would make a $fail comparison pass here regardless.
styleclean=1

for f in $pages; do
    [ -s "$f" ] || { bad "$f is empty"; styleclean=0; continue; }

    if grep -q '<style' "$f"; then
        bad "$f still has an inline <style> block"
        styleclean=0
    fi

    if grep -qE '[[:space:]]style=' "$f"; then
        bad "$f still has a style= attribute"
        styleclean=0
    fi

    if ! grep -q 'href="./css/terper.css"' "$f"; then
        bad "$f does not link the stylesheet"
        styleclean=0
    fi

    if grep -qi 'jquery\|googleapis\|gstatic\|cdn\.' "$f"; then
        bad "$f loads something remote that is not a YouTube embed"
        styleclean=0
    fi
done

if [ "$styleclean" -eq 1 ]; then
    ok 'Inline styles, stylesheet link and remote resources audited'
fi

# Every remote URL on the site must be an allowed host. The list was first
# written before the Live pages' prose was audited; terper.club (the site's
# own domain, appearing as a visible URL in a credit line on terper-live-1
# and -2) and paolaidrontino.bandcamp.com (a collaborator credit on the same
# two pages) are inherited links that predate the redesign, and both belong.
strays=$(grep -ohE 'https?://[a-zA-Z0-9.-]+' ./*.html | sort -u \
    | grep -vE '^https://(www\.youtube\.com|youtube\.com|terper\.bandcamp\.com|paolaidrontino\.bandcamp\.com|soundcloud\.com|www\.instagram\.com|linktr\.ee|www\.papayapie\.com|ryandmt\.com|terper\.club)$' || true)
if [ -z "$strays" ]; then
    ok 'Every external host is on the allow list'
else
    bad "Unexpected external hosts: $(echo "$strays" | tr '\n' ' ')"
fi

# The allow-list extractor above only sees absolute https?:// URLs, so a
# protocol-relative reference would leave the origin unnoticed.
protorel=$(grep -ohE '(src|href)="//[a-zA-Z0-9.-]+' ./*.html | sort -u || true)
if [ -z "$protorel" ]; then
    ok 'No protocol-relative external reference'
else
    bad "Protocol-relative reference: $(echo "$protorel" | tr '\n' ' ')"
fi

# Exactly six YouTube embeds, no more and no fewer.
embeds=$(grep -o 'youtube.com/embed/' ./*.html | wc -l | tr -d ' ')
if [ "$embeds" -eq 6 ]; then
    ok 'Exactly 6 YouTube embeds'
else
    bad "Found $embeds YouTube embeds, expected 6"
fi

# Every internal link resolves. GitHub Pages serves art.html at /art, so a
# link with no extension is checked against <name>.html.
printf '\nLink integrity\n'
broken=''
for f in $pages; do
    for href in $(grep -ohE 'href="\.\/[^"#]*"' "$f" | sed -E 's/href="\.\///; s/"//'); do
        target="$href"
        case "$target" in
            '')            target='index.html' ;;
            */)            target="${target}index.html" ;;
            *.html|*.css|*.png|*.jpg|*.webm) : ;;
            *)             target="${target}.html" ;;
        esac
        [ -e "$target" ] || broken="$broken $f->$href"
    done
done
if [ -z "$broken" ]; then
    ok 'Every internal link resolves'
else
    bad "Broken internal links:$broken"
fi

# Every referenced media file exists.
missing=''
for src in $(grep -ohE '(src|href)="\.\/media\/[^"]+"' ./*.html 2>/dev/null \
             | sed -E 's/.*="\.\///; s/"//' | sort -u); do
    [ -e "$src" ] || missing="$missing $src"
done
if [ -z "$missing" ]; then
    ok 'Every referenced media file exists'
else
    bad "Missing media:$missing"
fi

# The stylesheet spells its references url(../media/…), which the HTML
# pattern above cannot match, so give CSS its own pass rather than a
# vacuous argument.
cssmissing=''
for src in $(grep -ohE 'url\(\.\./media/[^)]+\)' ./css/*.css 2>/dev/null \
             | sed -E 's|.*url\(\.\./||; s|\)$||' | sort -u); do
    [ -e "$src" ] || cssmissing="$cssmissing $src"
done
if [ -z "$cssmissing" ]; then
    ok 'Every media file referenced from CSS exists'
else
    bad "CSS references missing media:$cssmissing"
fi

# Originals and config survive.
have CNAME 'CNAME kept'

titles=$(grep -h '<title>' ./*.html | wc -l | tr -d ' ')
if [ "$titles" -eq 17 ]; then
    ok 'All 17 pages have a title'
else
    bad "Found $titles page titles, expected 17"
fi

# No two pages may share a <title>. Tasks 6-8 were written before R3 carried
# a <title> column and derived it from the <h1>, which is not unique: two
# pages are titled "Breathing Waves", two "Displacement", three "Terper
# (Live)". Step 1b retitles them; this check keeps them retitled.
dupes=$(grep -h '<title>' ./*.html | sed -E 's/.*<title>//; s|</title>.*||' \
        | sort | uniq -d || true)
if [ -z "$dupes" ]; then
    ok 'Every page title is unique'
else
    bad "Duplicate page titles: $(echo "$dupes" | tr '\n' '|')"
fi

# Internal links must be extensionless. Beyond the served-URL rule, a
# .html-suffixed href is invisible to the category-crossing extractor's
# regex above, so it would be skipped rather than caught.
suffixed=$(grep -ohE 'href="\./[a-zA-Z0-9._-]+\.html"' ./*.html | sort -u || true)
if [ -z "$suffixed" ]; then
    ok 'No internal link carries a .html suffix'
else
    bad "Internal links with a .html suffix: $(echo "$suffixed" | tr '\n' ' ')"
fi

# A1 standardised on the Catalan "Centre Cívic". Keep the old spelling from
# creeping back through a copy-paste from the pre-redesign source.
if grep -q 'Civico' ./*.html; then
    bad "Old venue spelling 'Civico' is back: $(grep -l 'Civico' ./*.html | tr '\n' ' ')"
else
    ok 'Venue is spelled Centre Cívic throughout'
fi

n=$(grep -oh 'aria-current="page"' ./*.html | wc -l | tr -d ' ')
if [ "$n" -eq 16 ]; then
    ok 'All 16 interior pages mark their current nav item'
else
    bad "Found $n aria-current=page attributes, expected 16"
fi

printf '\n'
[ "$fail" -eq 0 ] && printf 'All checks passed.\n' || printf 'Some checks FAILED.\n'
exit "$fail"
