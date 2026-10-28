#!/usr/bin/env bash
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null

[ -n "${TEST_GATE_JUDGE:-}" ] && exit 0

with_timeout() {
	if command -v timeout >/dev/null 2>&1; then timeout "$@"
	elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
	else shift; "$@"
	fi
}

sha() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
	else shasum -a 256 | cut -d' ' -f1
	fi
}

input="$(cat)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-test-gate"
mkdir -p "$cache/verdicts"
model="${TEST_GATE_MODEL:-claude-sonnet-5-5}"

is_test_file() {
	case "$1" in
		*.test.ts | *.test.tsx | *.test.js | *.test.jsx | *.test.mts | *.test.cts) ;;
		*.spec.ts | *.spec.tsx | *.spec.js | *.spec.jsx | *.spec.mts | *.spec.cts) ;;
		*_test.py | *_test.go | *.test.py) ;;
		*) return 1 ;;
	esac
	return 0
}

test_re='(^|[^.[:alnum:]_])(it|test|its)(\.(each|only|skip|todo|concurrent|failing|fails|skipIf|runIf))*[[:space:]]*[(`]'
trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

added_tests() {
	local added="$1" old="$2" old_tests line
	old_tests="$(printf '%s\n' "$old" | grep -E "$test_re" | trim || true)"
	printf '%s\n' "$added" | grep -E "$test_re" | trim | while IFS= read -r line; do
		[ -z "$line" ] && continue
		[ -n "$old_tests" ] && printf '%s\n' "$old_tests" | grep -qxF -- "$line" && continue
		printf -- '- %s\n' "$line"
	done
}

repo_guidance() {
	local root="$1" dir="$2" section="" extra=""
	while :; do
		if [ -f "$dir/AGENTS.md" ]; then
			section="$(awk '
				/^#+[[:space:]]/ {
					level = length($1)
					if (on && level <= start) exit
					if (!on && tolower($0) ~ /test/) { on = 1; start = level }
				}
				on { print }
			' "$dir/AGENTS.md")"
			if [ -n "$section" ]; then
				local rel="${dir#"$root"}/AGENTS.md"
				section="From ${rel#/}:"$'\n\n'"$section"
				break
			fi
		fi
		[ "$dir" = "$root" ] || [ "$dir" = / ] && break
		dir="$(dirname "$dir")"
	done
	[ -f "$root/.agents/test-gate.md" ] && extra="Repo preferences (.agents/test-gate.md):"$'\n\n'"$(cat "$root/.agents/test-gate.md")"
	[ -n "$section$extra" ] && printf '\n%s\n\n%s\n' "$section" "$extra"
}

import_alias() {
	local spec="$1" pkg="$2"
	[ -f "$pkg/package.json" ] || return
	jq -r --arg spec "$spec" '
		(.imports // {}) | to_entries[]
		| .value |= (if type == "string" then . else (.default // .import // .node // ([.. | strings][0])) end)
		| select(.value != null)
		| if (.key | endswith("*")) then
			(.key | rtrimstr("*")) as $pre
			| select($spec | startswith($pre))
			| .value | sub("\\*"; $spec | ltrimstr($pre))
		  else select(.key == $spec) | .value end
	' "$pkg/package.json" 2>/dev/null | head -n1 | sed "s|^\./||; s|^|$pkg/|"
}

subject_sources() {
	local file="$1" dir pkg spec base cand body out="" seen="|" cap="${TEST_GATE_SUBJECT_BYTES:-30000}"
	dir="$(dirname "$file")"
	pkg="$(package_dir "$file")"
	while IFS= read -r spec; do
		case "$spec" in
			.*) base="$dir/$spec" ;;
			'#'*) base="$(import_alias "$spec" "$pkg")"; [ -n "$base" ] || continue ;;
			*) continue ;;
		esac
		base="${base%.js}"; base="${base%.mjs}"; base="${base%.ts}"
		for cand in "$base" "$base".ts "$base".tsx "$base".js "$base".mts "$base".mjs "$base"/index.ts "$base"/index.tsx "$base"/index.js; do
			[ -f "$cand" ] || continue
			is_test_file "$cand" && break
			case "$cand" in *.json) break ;; esac
			case "$seen" in *"|$cand|"*) break ;; esac
			seen="${seen}${cand}|"
			body="$(cat "$cand")"
			[ $(( ${#out} + ${#body} )) -gt "$cap" ] && break
			out+="### ${cand#"$root"/}"$'\n\n```\n'"$body"$'\n```\n\n'
			break
		done
	done < <(grep -oE "(from|require\(|import\(|^import)[[:space:]]*['\"][.#][^'\"]+['\"]" "$file" | sed -E "s/^[^'\"]*['\"]//; s/['\"]$//")
	printf '%s' "$out"
}

package_dir() {
	local dir
	dir="$(dirname "$1")"
	while [ "$dir" != "$root" ] && [ "$dir" != / ]; do
		for marker in package.json pyproject.toml go.mod; do
			[ -f "$dir/$marker" ] && { printf '%s' "$dir"; return; }
		done
		dir="$(dirname "$dir")"
	done
	printf '%s' "$root"
}

change_diff() {
	local pkg="$1" rel new
	rel="${pkg#"$root"}"; rel="${rel#/}"; rel="${rel:-.}"
	{
		git -C "$root" diff "$base" -- "$rel" ':!*.test.*' ':!*.spec.*' ':!*_test.*' 2>/dev/null
		git -C "$root" ls-files --others --exclude-standard -- "$rel" 2>/dev/null | grep -vE '\.(test|spec)\.|_test\.' | while IFS= read -r new; do
			git -C "$root" diff --no-index -- /dev/null "$new" 2>/dev/null
		done
	} | head -c "${TEST_GATE_DIFF_BYTES:-40000}"
}

build_prompt() {
	local file="$1" titles="$2" rel tpl
	rel="${file#"$root"/}"
	tpl="$(cat "$here/test-gate-prompt.md")"
	tpl="${tpl//'{{TEST_FILE}}'/$rel}"
	tpl="${tpl//'{{REPO_GUIDANCE}}'/$(repo_guidance "$root" "$(dirname "$file")")}"
	tpl="${tpl//'{{ADDED_TESTS}}'/$titles}"
	tpl="${tpl//'{{SUBJECT_SOURCES}}'/$(subject_sources "$file")}"
	tpl="${tpl//'{{CHANGE_DIFF}}'/$(change_diff "$(package_dir "$file")")}"
	tpl="${tpl//'{{TEST_SOURCE}}'/$(head -c "${TEST_GATE_TEST_BYTES:-60000}" "$file")}"
	printf '%s' "$tpl"
}

judge() {
	local out
	out="$(cd "$root" && printf '%s' "$1" | TEST_GATE_JUDGE=1 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 with_timeout "${TEST_GATE_TIMEOUT:-60}" \
		claude -p --model "$model" --safe-mode --strict-mcp-config --mcp-config '{"mcpServers":{}}' --setting-sources "" --disable-slash-commands \
		--system-prompt "You review newly added automated tests for value. Be direct and brief. Your last message must end with the requested JSON block." \
		--tools Read,Grep,Glob --allowedTools Read,Grep,Glob --disallowedTools 'Read(~/.claude/**)' \
		--permission-mode dontAsk --max-turns "${TEST_GATE_MAX_TURNS:-6}" \
		--output-format json --no-session-persistence 2>/dev/null)" || return 1
	printf '%s' "$out" | jq -e '.is_error != true and (.result | type == "string")' >/dev/null 2>&1 || return 1
	printf '%s' "$out" | jq -c --arg file "$2" --arg model "$model" \
		'{time: (now | todate), file: $file, model: $model, turns: .num_turns, cost: .total_cost_usd, usage: (.usage | {input_tokens, cache_creation_input_tokens, cache_read_input_tokens, output_tokens})}' \
		>> "$cache/usage.jsonl" 2>/dev/null
	printf '%s' "$out" | jq -r '.result' | awk '
		/^```json[[:space:]]*$/ { buf = ""; on = 1; next }
		on && /^```[[:space:]]*$/ { last = buf; on = 0; next }
		on { buf = buf $0 "\n" }
		END { printf "%s", last }
	' | jq -ce 'select(.verdicts | type == "array" and length > 0)' 2>/dev/null
}

report=""
gate() {
	local file="$1" titles="$2" from_bash="$3" key hash verdicts_file verdicts lines
	[ -z "$titles" ] && return 0
	key="$(printf '%s' "$file" | sha)"
	hash="$(sha < "$file")"
	verdicts_file="$cache/verdicts/$key-$hash.json"

	if [ -s "$verdicts_file" ]; then
		[ "$from_bash" = 1 ] && return 0
		verdicts="$(cat "$verdicts_file")"
	else
		verdicts="$(judge "$(build_prompt "$file" "$titles")" "$file")"
		if [ -z "$verdicts" ]; then
			printf 'test-gate: judge failed for %s; skipped.\n' "${file#"$root"/}" >&2
			return 0
		fi
		printf '%s' "$verdicts" > "$verdicts_file"
	fi

	lines="$(printf '%s' "$verdicts" | jq -r '.verdicts[] | select(.verdict == "DELETE" or .verdict == "REWRITE")
		| "- \"\(.title)\" → \(.verdict)\(if .foldInto then " (fold into \"\(.foldInto)\")" else "" end): \(.reason)"')"
	[ -z "$lines" ] && return 0
	printf '%s\t%s\t%s\n' "$(date -Iseconds 2>/dev/null || date)" "$file" "$(printf '%s' "$lines" | tr '\n' ' ')" >> "$cache/blocks.log"
	report+="${file#"$root"/}:"$'\n'"${lines}"$'\n\n'
	return 2
}

command -v jq >/dev/null 2>&1 || exit 0
command -v claude >/dev/null 2>&1 || { echo 'test-gate: claude CLI not found; skipped.' >&2; exit 0; }

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
status=0

if [ "$tool" != "Bash" ]; then
	file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
	is_test_file "$file" && [ -f "$file" ] || exit 0
	root="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || dirname "$file")"
	base="$(git -C "$root" merge-base HEAD origin/main 2>/dev/null || echo HEAD)"
	added="$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // ([.tool_input.edits[]?.new_string] | join("\n")) // empty')"
	old="$(printf '%s' "$input" | jq -r '.tool_input.old_string // ([.tool_input.edits[]?.old_string] | join("\n")) // ""')"
	gate "$file" "$(added_tests "$added" "$old")" 0 || status=2
else
	[ -n "$cwd" ] || exit 0
	root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
	base="$(git -C "$root" merge-base HEAD origin/main 2>/dev/null || echo HEAD)"
	while IFS= read -r rel; do
		file="$root/$rel"
		is_test_file "$file" && [ -f "$file" ] || continue
		if git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
			diff="$(git -C "$root" diff -U0 "$base" -- "$rel")"
			added="$(printf '%s\n' "$diff" | grep -E '^\+' | grep -vE '^\+\+\+ ' | sed 's/^+//' || true)"
			old="$(printf '%s\n' "$diff" | grep -E '^-' | grep -vE '^--- ' | sed 's/^-//' || true)"
		else
			added="$(cat "$file")"
			old=""
		fi
		gate "$file" "$(added_tests "$added" "$old")" 1 || status=2
	done < <({ git -C "$root" diff --name-only "$base"; git -C "$root" ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
fi

[ "$status" = 0 ] && exit 0
printf 'TEST GATE: a reviewer judged tests you added as low value or mis-shaped.\n\n%s' "$report" >&2
printf 'Apply every DELETE and REWRITE now (and remove setup/mocks/helpers only those tests used). Overrides are logged to %s/blocks.log; only override with a concrete distinct behaviour and state it in your final report.\n' "$cache" >&2
exit 2
