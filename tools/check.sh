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

# Every tile is one <a class="tile"> wrapping one .tile-cap. Compare those
# two counts instead of pinning a total. A half-deleted or malformed tile
# breaks the pairing and fails; adding a legitimate ninth one does not, so
# this stops reporting ordinary growth as a regression. Zero tiles on a page
# that has a grid is a broken extraction, and must not read as "no bad tiles".
check_tiles() {
    [ -s "$1" ] || return 0
    n=$(grep -o 'class="tile"' "$1" | wc -l | tr -d ' ')
    caps=$(grep -o 'class="tile-cap"' "$1" | wc -l | tr -d ' ')
    if [ "$n" -eq 0 ]; then
        bad "$1 has no tiles; the grid is empty or extraction is broken"
    elif [ "$n" -eq "$caps" ]; then
        ok "$1 has $n tiles, each with a caption"
    else
        bad "$1 has $n tiles but $caps captions"
    fi
}

check_tiles art.html
check_tiles live.html
check_tiles releases.html

# Art and Live tiles must open pages on this site. Attribute order is not
# guaranteed, so match the tag and then inspect its href. The extraction still
# has to prove it saw everything, but it proves it against a plain count of
# class="tile" in the same two files rather than against a pinned total: if
# the regex ever stops matching, the two disagree and this fails, while
# adding a tile keeps them in step. Zero extracted is still a failure.
# releases.html is excluded on purpose: its tiles are Bandcamp and
# SoundCloud by design.
tiles=$(tr '\n' ' ' < art.html | grep -oE '<a [^>]*class="tile"[^>]*>'; \
        tr '\n' ' ' < live.html | grep -oE '<a [^>]*class="tile"[^>]*>')
ntiles=$(printf '%s\n' "$tiles" | grep -c '<a' || true)
declared=$(cat art.html live.html | grep -o 'class="tile"' | wc -l | tr -d ' ')
offsite=$(printf '%s\n' "$tiles" | grep -vE "href=[\"']\./" || true)
if [ "$ntiles" -eq 0 ]; then
    bad 'Extracted no Art or Live tiles; extraction is broken'
elif [ "$ntiles" -ne "$declared" ]; then
    bad "Extracted $ntiles Art+Live tiles, $declared declared; extraction is broken"
elif [ -z "$offsite" ]; then
    ok "All $ntiles Art and Live tiles link inside the site"
else
    bad "Off-site tile: $(printf '%s' "$offsite" | head -1)"
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
    # This counted every target="_blank" on the page, tiles and footer links
    # together, against one number, so a footer edit and a lost tile attribute
    # were indistinguishable. Assert what the line actually claims: each tile
    # anchor carries it. Extracting none fails rather than reading as clean.
    rtiles=$(tr '\n' ' ' < releases.html | grep -oE '<a [^>]*class="tile"[^>]*>')
    nr=$(printf '%s\n' "$rtiles" | grep -c '<a' || true)
    plain=$(printf '%s\n' "$rtiles" | grep -v 'target="_blank"' || true)
    if [ "$nr" -eq 0 ]; then
        bad 'Extracted no Releases tiles; extraction is broken'
    elif [ -z "$plain" ]; then
        ok "All $nr Releases tiles open in a new tab"
    else
        bad "Releases tile without target=_blank: $(printf '%s' "$plain" | head -1)"
    fi
fi

# rel=noopener is the floor on every new-tab link, not just releases'.
# Flattened: <a> tags wrap across lines in this codebase (see :369, :393).
unsafe=$(for f in ./*.html; do
             tr '\n' ' ' < "$f" | grep -oE '<a [^>]*target=["'"'"']?_blank[^>]*>' \
               | grep -vE "rel=[\"'][^\"']*noopener" | sed "s|^|$f: |"
         done || true)
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

# Bio carries one portrait beside the prose. Assert that an image is there
# and that the file it names exists, but not which photograph it is: naming
# one meant every deliberate swap tripped this check as though it were a
# regression. An empty extraction is a failure, not a pass.
bioimg=$(tr '\n' ' ' < bio.html 2>/dev/null | grep -oE '<img[^>]*src="\./media/[^"]+"' \
         | sed -E 's/.*src="\.\///; s/".*//' | head -1)
if [ -z "$bioimg" ]; then
    bad 'Bio carries no image, or the extraction is broken'
elif [ ! -s "$bioimg" ]; then
    bad "Bio image names a file that does not exist: $bioimg"
else
    ok "Bio carries its image ($bioimg)"
fi

if [ -s contact.html ] && grep -q 'terper (dot) club (@) gmail (dot) com' contact.html; then
    ok 'Contact carries the obfuscated address'
else
    bad 'Obfuscated address missing or altered'
fi

# --- Task 6: detail pages ---
printf '\nDetail pages\n'

ART_PAGES='displacement-3 mycelium-parlour-1 inorganic-interruptions-1 displacement-2 displacement-1 amygdala-1 tortuga-1 breathing-waves-2 breathing-waves-1'
LIVE_PAGES='terper-live-3 terper-live-2 terper-live-1'

# done_pages lists the pages converted so far; extend it in Tasks 7, 8 and 9.
DONE_PAGES='displacement-3 mycelium-parlour-1 amygdala-1 inorganic-interruptions-1 displacement-2 displacement-1 tortuga-1 breathing-waves-2 breathing-waves-1 terper-live-1 terper-live-2 terper-live-3'

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
    # Capture whatever href is there, not just an already-internal one: a
    # chain endpoint must show up empty because there is no <a> at all, not
    # because an off-site href failed to match "href=\"\./". An href that
    # does not start with ./ is tagged OFFSITE so it can never be mistaken
    # for a legitimate bare page name or a legitimate empty endpoint.
    href=$(tr '\n' ' ' < "$1" \
      | grep -oE "nav-label\">$2</div>[^<]*<a href=[\"'][^\"']*[\"']" \
      | sed -E 's|.*href=.||; s|.$||')
    case "$href" in
        '')  printf '' ;;
        ./*) printf '%s' "${href#./}" ;;
        *)   printf 'OFFSITE:%s' "$href" ;;
    esac
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
    displacement-1 displacement-2 inorganic-interruptions-1 mycelium-parlour-1 \
    displacement-3
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

    # Flatten first: every iframe in this codebase spans three lines (see
    # the lazy-load check above), so width/height on a continuation line
    # would be invisible to a line-scoped grep.
    if tr '\n' ' ' < "$f" | grep -oE '<iframe[^>]*>' | grep -qE '(width|height)="[0-9]'; then
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

# A pinned total made every new page look like a regression, and it never
# detected one: a page that actually went missing breaks the link-integrity
# and chain checks below, which name the broken link instead of a number.
# What is worth asserting here is that the glob found something at all,
# since every whole-site check downstream iterates over it.
n=$(echo "$pages" | wc -l | tr -d ' ')
if [ "$n" -gt 0 ]; then
    ok "$n page files at the root"
else
    bad 'No page files at the root; the whole-site audit has nothing to walk'
fi

# Every photograph carries a description. Screen readers announce nothing for
# alt="", so an empty one is not a neutral default here: nothing on this site
# is decorative, every image is the work. Counting <img> against non-empty alt
# catches both the missing attribute and the empty one, which a presence test
# would wave through. No images at all means the extraction broke, so it fails
# rather than reporting a clean sweep of nothing.
nimg=$(grep -oh '<img ' ./*.html | wc -l | tr -d ' ')
nalt=$(grep -ohE 'alt="[^"]+"' ./*.html | wc -l | tr -d ' ')
if [ "$nimg" -eq 0 ]; then
    bad 'No images found; the alt-text audit examined nothing'
elif [ "$nimg" -eq "$nalt" ]; then
    ok "All $nimg images carry a non-empty alt"
else
    bad "$nimg images but $nalt non-empty alt attributes"
fi

# This loop is the script's one summary check: four assertions over every
# page, reported as a single line. Its ok must therefore be earned; an
# unconditional one would print "audited" on the same run it prints FAIL.
# A local flag, not $fail: fail only ever moves from 0 to 1, so a $fail
# check here could never wrongly grant this ok; an earlier failure can
# only suppress it, never fake it. The local flag exists for a different
# reason: decoupling. Under $fail, a failure in some earlier, unrelated
# section would silently delete this section's ok line too, even though
# the four assertions above all held.
styleclean=1

for f in $pages; do
    [ -s "$f" ] || { bad "$f is empty"; styleclean=0; continue; }

    if grep -q '<style' "$f"; then
        bad "$f still has an inline <style> block"
        styleclean=0
    fi

    if grep -qE '(^|[[:space:]])style=' "$f"; then
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
# protocol-relative reference would leave the origin unnoticed. Quoting is
# optional and may be single, double, or absent.
protorel=$(grep -ohE '(src|href)=["'"'"']?//[a-zA-Z0-9.-]+' ./*.html | sort -u || true)
if [ -z "$protorel" ]; then
    ok 'No protocol-relative external reference'
else
    bad "Protocol-relative reference: $(echo "$protorel" | tr '\n' ' ')"
fi

# The HTML check above cannot see the stylesheet: an unguarded remote or
# protocol-relative @import there would load a remote origin unnoticed.
cssimport=$(grep -ohiE '@import[^;]*(https?:|//)' ./css/*.css || true)
if [ -z "$cssimport" ]; then
    ok 'Stylesheet imports nothing remote'
else
    bad "Remote @import in CSS: $(printf '%s' "$cssimport" | head -1)"
fi

# Exactly six YouTube embeds, no more and no fewer.
embeds=$(grep -o 'youtube.com/embed/' ./*.html | wc -l | tr -d ' ')
if [ "$embeds" -eq 6 ]; then
    ok 'Exactly 6 YouTube embeds'
else
    bad "Found $embeds YouTube embeds, expected 6"
fi

# Every internal link resolves. GitHub Pages serves art.html at /art, so a
# link with no extension is checked against <name>.html. The pattern accepts
# either quote style: matching only double quotes would walk past a
# single-quoted link and still print ok. Extracting nothing fails, because a
# broken extractor otherwise reports a clean sweep of an empty set.
printf '\nLink integrity\n'
broken=''
nlinks=0
for f in $pages; do
    for href in $(grep -ohE 'href=["'"'"']\.\/[^"'"'"'#]*' "$f" | sed -E 's/href=["'"'"']\.\///'); do
        nlinks=$((nlinks + 1))
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
if [ "$nlinks" -eq 0 ]; then
    bad 'No internal links extracted; link integrity examined nothing'
elif [ -z "$broken" ]; then
    ok "All $nlinks internal links resolve"
else
    bad "Broken internal links:$broken"
fi

# Every referenced media file exists. Same two faults as the check above had:
# the pattern read double quotes only, so a single-quoted src was never
# tested, and an empty extraction printed ok. The CSS pass below has been
# hardened this way since it was written; this one had not.
srcs=$(grep -ohE '(src|href)=["'"'"']\./media/[^"'"'"']+' ./*.html 2>/dev/null \
       | sed -E 's/.*=["'"'"']\.\///' | sort -u || true)
nsrcs=$(printf '%s' "$srcs" | grep -c . || true)
missing=''
for src in $srcs; do
    [ -e "$src" ] || missing="$missing $src"
done
if [ "$nsrcs" -eq 0 ]; then
    bad 'No media references found in the HTML; extraction is broken'
elif [ -z "$missing" ]; then
    ok "Every referenced media file exists ($nsrcs checked)"
else
    bad "Missing media:$missing"
fi

# The stylesheet spells its references url(../media/…), which the HTML
# pattern above cannot match, so give CSS its own pass rather than a
# vacuous argument. url() may be quoted or spaced, and an empty extraction
# must not read as success; that is the vacuous shape this script has
# shipped before. Paths come out media/foo.png, relative to the repo root
# (../media/ is relative to css/), so the existence test below must not
# re-prepend media/.
cssrefs=$(grep -ohE 'url\([[:space:]]*["'"'"']?\.\./media/[^)"'"'"']+' ./css/*.css 2>/dev/null \
          | sed -E 's|.*\.\./||' | sort -u || true)
nrefs=$(printf '%s' "$cssrefs" | grep -c . || true)
cssmissing=''
for src in $cssrefs; do
    [ -e "$src" ] || cssmissing="$cssmissing $src"
done
if [ "$nrefs" -eq 0 ]; then
    bad 'No media references found in CSS; extraction is broken'
elif [ -z "$cssmissing" ]; then
    ok "Every media file referenced from CSS exists ($nrefs checked)"
else
    bad "CSS references missing media:$cssmissing"
fi

# Originals and config survive.
have CNAME 'CNAME kept'

# -o counts tags, not lines: grep -c would count a page with two <title>-
# bearing lines once, and undercount a title-less page that another page's
# spare match happens to paper over.
# Compared against the number of pages on disk, not a literal: "every page
# has a title" is the actual invariant, and it holds at any site size.
titles=$(grep -oh '<title>' ./*.html | wc -l | tr -d ' ')
npages=$(ls ./*.html | wc -l | tr -d ' ')
if [ "$npages" -eq 0 ]; then
    bad 'No pages found; the title audit examined nothing'
elif [ "$titles" -eq "$npages" ]; then
    ok "All $npages pages have a title"
else
    bad "Found $titles <title> tags across $npages pages"
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
# creeping back through a copy-paste from the pre-redesign source. The match
# is case-insensitive, since "civico" and "Civico" are both regressions, and
# it asserts the correct spelling is actually present rather than trusting
# the absence of the wrong one: an ok must survive deleting the venue name.
if grep -qi 'civico' ./*.html; then
    bad "Old venue spelling is back: $(grep -li 'civico' ./*.html | tr '\n' ' ')"
elif [ "$(grep -oh 'Centre Cívic' ./*.html | wc -l | tr -d ' ')" -gt 0 ]; then
    ok "Venue is spelled Centre Cívic in all $(grep -oh 'Centre Cívic' ./*.html | wc -l | tr -d ' ') places"
else
    bad 'No "Centre Cívic" anywhere; the venue name is gone, not just respelled'
fi

# A bare count proves nothing: aria-current on the wrong nav item still
# passes a total. It must sit on the same <a> as class="is-current".
# Report the number this loop actually walked rather than a literal. The
# literal said 16 while 17 pages were on disk, and nothing caught it,
# because it lived in the ok text and not in the condition. Zero pages
# walked is a broken glob, so it fails instead of reporting a clean sweep.
miswired=''
interior=0
for f in ./*.html; do
    [ "$f" = "./index.html" ] && continue
    interior=$((interior + 1))
    tr '\n' ' ' < "$f" \
      | grep -oE '<a [^>]*class="is-current"[^>]*>' \
      | grep -q 'aria-current="page"' \
      || miswired="$miswired $f"
done
if [ "$interior" -eq 0 ]; then
    bad 'No interior pages walked; the aria-current audit examined nothing'
elif [ -z "$miswired" ]; then
    ok "All $interior interior pages mark their current nav item"
else
    bad "aria-current missing from the is-current link:$miswired"
fi

printf '\n'
[ "$fail" -eq 0 ] && printf 'All checks passed.\n' || printf 'Some checks FAILED.\n'
exit "$fail"
