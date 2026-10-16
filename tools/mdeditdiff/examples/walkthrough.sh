#!/bin/bash
# mdEditDiff walkthrough: a planner agent, a person and an implementer agent share plan.md.
# mdEditDiff is free, open-source software (MIT license):
#   https://github.com/roy-vinay/applied-ai-agents/tree/main/tools/mdeditdiff
# This script uses a temporary folder with its own history, so it never touches your files or real history.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/../dist/src/cli.js" ]; then MDD=(node "$HERE/../dist/src/cli.js"); else MDD=(mdeditdiff); fi
mdeditdiff() { "${MDD[@]}" "$@"; }

WORK="$(mktemp -d)"
export MDEDITDIFF_HOME="$WORK/.history"
cd "$WORK"
cp "$HERE/plan.md" plan.md

say()  { printf '\n\033[1;36m# %s\033[0m\n' "$*"; }
show() { printf '\033[2m$ %s\033[0m\n' "$*"; }
edit() { perl -0pi -e "$1" plan.md; }

printf '\033[1mmdEditDiff: an editor for people, a diff for agents.\033[0m\n'
printf 'Free, open-source (MIT): github.com/roy-vinay/applied-ai-agents/tree/main/tools/mdeditdiff\n'

say "1. A planner agent writes plan.md and checks it in."
show 'mdeditdiff checkpoint plan.md --author planner --note "First plan"'
mdeditdiff checkpoint plan.md --author planner --note "First plan"

say "2. An implementer agent reads it for the first time (it gets the full text once)."
show 'mdeditdiff changes plan.md --reader implementer'
mdeditdiff changes plan.md --reader implementer | head -3
echo "   ..."

say "3. A person edits the plan in their editor and tells no one."
echo "   - answers the archived-rows question and removes it"
echo "   - tightens step 2"
edit 's/- Should exports include archived rows\?\n//; s/2\. Build the CSV on the server\./2. Build the CSV on the server, streaming rows so large reports never time out./; s/(## Rollout)/Decision: archived rows are excluded.\n\n$1/'

say "4. The planner checks what changed before revising, then proposes a row limit and checks in."
show 'mdeditdiff changes plan.md --reader planner'
mdeditdiff changes plan.md --reader planner | head -2
edit 's/- What is the row limit\?/- What is the row limit? Proposed: 100,000 rows./'
show 'mdeditdiff checkpoint plan.md --author planner --note "Proposed a row limit"'
mdeditdiff checkpoint plan.md --author planner --note "Proposed a row limit"

say "5. The implementer comes back. Instead of re-reading the plan, it asks what changed:"
show 'mdeditdiff changes plan.md --reader implementer'
mdeditdiff changes plan.md --reader implementer

say "6. The full history, with who reported each version and where each reader last looked:"
show 'mdeditdiff history plan.md'
mdeditdiff history plan.md

say "That's mdEditDiff. Install it: npm install -g ./tools/mdeditdiff (from a clone of the repo)."
echo "   Source, Mac app and docs: github.com/roy-vinay/applied-ai-agents/tree/main/tools/mdeditdiff"
echo "   (This walkthrough used a temporary history; your real history was not touched.)"
