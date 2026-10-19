#!/bin/bash
#
# Deploy djklick.com (static site, no build step) from a Mac.
#
#     cd ~/Development/djklick && ./deploy.sh
#     cd ~/Development/djklick && ./deploy.sh --dry-run
#
# What it does:
#   1. refuses to run unless the git working tree is clean
#   2. pushes the current branch to origin (never force)
#   3. rsyncs ONLY the site files to the Opalstack site directory
#      (no --delete: nothing on the server is ever removed)
#   4. checks https://djklick.com returns 200
#
# --dry-run shows what rsync would upload and changes nothing: no push,
# no upload, no live check.
#
# Run by JT only. Agents must never run this script, not even --dry-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SSH_HOST="opal-zorrotmm"
REMOTE_DIR="/home/zorrotmm/apps/djclick"   # app name is spelled with a "c"
SITE="https://djklick.com"

# The only files that ship. Anything else in the repo stays local.
SITE_FILES=(
    index.html
    favicon.ico
    favicon-32x32.png
    apple-touch-icon.png
    og-image.png
)

# Belt and braces: rsync is handed an explicit file list above, so these never
# match today, but they keep a future "./" sync from shipping repo-only files.
EXCLUDES=(
    --exclude '.git'
    --exclude '.gitignore'
    --exclude 'oldsite/'
    --exclude '.DS_Store'
    --exclude 'deploy.sh'
    --exclude '*.md'
)

# Same helper as the other projects: quiet on success, full output on failure.
run_quiet() {
    local label="$1"; shift
    printf "%s" "$label"
    local tmpout; tmpout=$(mktemp)
    if "$@" > "$tmpout" 2>&1; then
        echo " done"
        rm -f "$tmpout"
    else
        local rc=$?
        echo " FAILED"
        cat "$tmpout"
        rm -f "$tmpout"
        return $rc
    fi
}

fail() { echo "deploy: $*" >&2; exit 1; }

# ------------------------------------------------------------- args ----
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help)    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            fail "unknown option: $arg (only --dry-run is supported)" ;;
    esac
done

# ------------------------------------------------------------- checks ----
[ -n "$REMOTE_DIR" ] || fail "REMOTE_DIR is not set at the top of deploy.sh."

git rev-parse --git-dir > /dev/null 2>&1 || fail "not a git repository."

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || fail "detached HEAD. Check out a branch first."

# Untracked files count too: a clean tree means what ships is exactly what is
# committed. Ignored files (oldsite/, .DS_Store) do not count.
DIRTY="$(git status --porcelain)"
if [ -n "$DIRTY" ]; then
    echo "deploy: working tree is not clean:" >&2
    echo "$DIRTY" | sed 's/^/  /' >&2
    fail "commit or stash first, then run this again."
fi

for f in "${SITE_FILES[@]}"; do
    git ls-files --error-unmatch "$f" > /dev/null 2>&1 \
        || fail "$f is not tracked in git, refusing to ship it."
done

SHORT="$(git rev-parse --short HEAD)"
SUBJECT="$(git log -1 --format=%s)"

if [ "$DRY_RUN" = "1" ]; then
    echo "deploy: DRY RUN of $SHORT, $SUBJECT"
else
    echo "deploy: shipping $SHORT, $SUBJECT"
fi
echo

# ------------------------------------------------------------- push ----
if [ "$DRY_RUN" = "1" ]; then
    echo "==> [1/3] Push: skipped (dry run). Would push $BRANCH to origin."
else
    echo "==> [1/3] Push $BRANCH to origin"
    # Plain push, never --force. A rejected push (origin moved on) stops here.
    run_quiet "  pushing... " git push origin "$BRANCH" \
        || fail "push failed. Pull and sort it out, then run this again."
fi

# ------------------------------------------------------------- upload ----
# No --delete, ever. Files on the server that are not in SITE_FILES are left
# exactly as they are.
RSYNC_FLAGS=(-avz)
[ "$DRY_RUN" = "1" ] && RSYNC_FLAGS+=(-n)

if [ "$DRY_RUN" = "1" ]; then
    echo "==> [2/3] Upload (dry run): files rsync WOULD send to $SSH_HOST:$REMOTE_DIR/"
    echo "    Nothing on the server is ever deleted (no --delete)."
else
    echo "==> [2/3] Upload to $SSH_HOST:$REMOTE_DIR/"
fi

rsync "${RSYNC_FLAGS[@]}" "${EXCLUDES[@]}" \
    "${SITE_FILES[@]}" "$SSH_HOST:$REMOTE_DIR/" \
    || fail "rsync failed."

# ------------------------------------------------------------- verify ----
if [ "$DRY_RUN" = "1" ]; then
    echo "==> [3/3] Live check: skipped (dry run)."
    echo
    echo "deploy: dry run complete. Nothing was pushed, uploaded, or changed."
    exit 0
fi

echo "==> [3/3] Live check: $SITE"
CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$SITE" || true)"
[ "$CODE" = "200" ] || fail "$SITE returned HTTP ${CODE:-none}, expected 200."
echo "  HTTP 200"

# ------------------------------------------------------------- summary ----
echo
echo "deploy: summary"
echo "  commit:   $SHORT  $SUBJECT"
echo "  branch:   $BRANCH (pushed to origin)"
echo "  uploaded: ${SITE_FILES[*]}"
echo "  to:       $SSH_HOST:$REMOTE_DIR/"
echo "  live:     $SITE (HTTP 200)"
