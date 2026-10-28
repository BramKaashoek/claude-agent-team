#!/usr/bin/env bash
set -uo pipefail

# macOS ships neither `timeout` nor `sha256sum` by default
with_timeout() {
	if command -v timeout >/dev/null 2>&1; then timeout "$@"
	elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
	else shift; "$@"
	fi
}

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

case "$file" in
	*.md | *.mdx | *.markdown | *.txt | *.rst) exit 0 ;;
esac

added="$(printf '%s' "$input" | jq -r '
	.tool_input.content
	// .tool_input.new_string
	// ([.tool_input.edits[]?.new_string] | join("\n"))
	// empty
')"
[ -z "$added" ] && exit 0

old="$(printf '%s' "$input" | jq -r '
	.tool_input.old_string
	// ([.tool_input.edits[]?.old_string] | join("\n"))
	// ""
')"

comment_re='^[[:space:]]*(//|#[^!]|/\*|\*[^/]|<!--)|[^:[:space:]][[:space:]]+(//|#|/\*|<!--)([[:space:]]|$)'
skip_re='eslint|@ts-|biome-ignore|c8 |istanbul|prettier-ignore|noqa|type: ?ignore|TODO|FIXME|HACK|SPDX|copyright'

trim() { sed -E 's/^[0-9]+://; s/^[[:space:]]+//; s/[[:space:]]+$//'; }

old_comments="$(printf '%s\n' "$old" | grep -E "$comment_re" 2>/dev/null | trim || true)"

raw_hits="$(printf '%s\n' "$added" \
	| grep -nE "$comment_re" \
	| grep -vE '\{[[:space:]]*$' \
	| grep -viE "$skip_re" \
	| grep -vE 'https?://' \
	|| true)"
[ -z "$raw_hits" ] && exit 0

hits=""
while IFS= read -r line; do
	[ -z "$line" ] && continue
	text="$(printf '%s' "$line" | trim)"
	if [ -n "$old_comments" ] && printf '%s\n' "$old_comments" | grep -qxF -- "$text"; then
		continue
	fi
	hits+="${line}"$'\n'
done <<< "$raw_hits"

hits="$(printf '%s' "$hits" | sed '/^$/d')"
[ -z "$hits" ] && exit 0

count="$(printf '%s\n' "$hits" | grep -c '' || true)"

self_verdict_msg="COMMENT GATE — BLOCKING. This edit added ${count} comment line(s) to ${file}. STOP; do not continue with other work until you resolve them.

The added comment lines are:
${hits}

Comments are guilty-until-proven-innocent. Judge YOUR OWN comment adversarially — the fact that you can construct a justification is NOT the bar and does NOT let it survive. In your NEXT reply, render an explicit verdict for EACH added comment, in this exact form:

  DELETE: \"<quoted comment>\"
  or
  KEEP: \"<quoted comment>\" — surprising fact: <ONE concrete clause naming the specific constraint / race / workaround / violated assumption / gotcha that the code and surrounding names genuinely cannot convey>

Rules for a KEEP verdict:
- The surprising fact must be something a competent reader would NOT already infer from the code and names. A 'why' that isn't surprising is a WHAT — DELETE it.
- If your surprising-fact clause merely restates what the code does, or is a generic/self-evident reason, DELETE.
- A WHAT restates what THIS code does. A statement about an EXTERNAL actor the code cannot show (browser, OS, third-party API, hardware, network, spec quirk) is a WHY — 'X does Y' grammar alone is not a WHAT when X is outside this code. KEEP those.
- Borderline loses. When in doubt, DELETE.
- No ticket/PBI refs, step narration, or type/shape labels.
Directives (eslint/@ts-/biome-ignore/TODO/FIXME/HACK), URLs and license headers are exempt and already excluded.

Then actually apply every DELETE before doing anything else."

# Fail-safe, not fail-open: an unavailable judge falls back to the self-verdict
# gate rather than letting the edit through unreviewed.
if ! command -v claude >/dev/null 2>&1; then
	printf '%s\n' "$self_verdict_msg" >&2
	exit 2
fi

judge_prompt="You are a strict code-comment reviewer. A comment survives ONLY if it states a non-obvious WHY a competent reader could NOT infer from the code and names: a race, workaround, violated assumption, external constraint, or perf cliff. FORBIDDEN: comments that restate the code (WHAT), decode obvious constants/enums, narrate steps, label test state, or mirror a signature. Assume a competent engineer. Borderline loses.

A WHAT restates something the reader can verify by reading THIS code. A statement about the behavior of an EXTERNAL actor the code cannot show — the browser, OS, a third-party API/service, hardware, the network, a spec quirk — is a WHY, not a WHAT, even when phrased as 'X does/doesn't do Y'. Check the subject: if it is this code, likely WHAT; if it is something outside this code, likely a legitimate external-constraint WHY. Do not DELETE a comment solely because it is a declarative 'X does Y' sentence — that grammar alone is not a WHAT.

Judge ONLY these added comment line(s):
${hits}

Full edit for context:
${added}

Reply with EXACTLY one line first:
VERDICT: OK
or
VERDICT: DELETE
On DELETE, add one line per forbidden comment: the quoted comment then a <=8-word reason."

judge="$(printf '%s' "$judge_prompt" | with_timeout 90 claude -p --model claude-haiku-4-5-20251001 2>/dev/null || true)"

if printf '%s\n' "$judge" | grep -qiE '^[[:space:]]*VERDICT:[[:space:]]*OK'; then
	exit 0
fi

if printf '%s\n' "$judge" | grep -qiE '^[[:space:]]*VERDICT:[[:space:]]*DELETE'; then
	printf 'COMMENT GATE — BLOCKING. An automated reviewer judged %s added comment line(s) in %s as WHAT/obvious comments that must go.\n\n%s\n\nDelete each listed comment (or, if you genuinely disagree, rewrite it to state a non-obvious constraint). Do this before other work.\n' \
		"$count" "$file" "$judge" >&2
	exit 2
fi

printf '%s\n' "$self_verdict_msg" >&2
exit 2
