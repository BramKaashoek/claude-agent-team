#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
claude=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
backup="$claude/backup-agent-team-$(date +%Y%m%d%H%M%S)"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

link() {
	local src=$1 dst=$2
	mkdir -p "$(dirname "$dst")"
	if [[ -e $dst && ! -L $dst ]]; then
		mkdir -p "$backup"
		mv "$dst" "$backup/"
		echo "backed up $dst -> $backup/"
	fi
	ln -sfn "$src" "$dst"
	echo "linked $dst"
}

for f in "$repo"/agents/*.md; do link "$f" "$claude/agents/$(basename "$f")"; done
link "$repo/skills/project-manager" "$claude/skills/project-manager"
link "$repo/hooks/team-gates.sh" "$claude/hooks/team-gates.sh"

settings="$claude/settings.json"
[[ -f $settings ]] || echo '{}' >"$settings"
cp "$settings" "$settings.bak"
hook="$claude/hooks/team-gates.sh"
jq --arg hook "$hook" '
	def has_hook($event): any(.hooks[$event][]?.hooks[]?; .command == $hook);
	def add_hook($event; $entry): if has_hook($event) then . else .hooks[$event] += [$entry] end;
	.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
	| add_hook("PreToolUse"; {matcher: "Bash", hooks: [{type: "command", command: $hook}]})
	| add_hook("TaskCreated"; {hooks: [{type: "command", command: $hook}]})
	| add_hook("TaskCompleted"; {hooks: [{type: "command", command: $hook}]})
' "$settings.bak" >"$settings"
echo "updated $settings (previous version in $settings.bak)"
echo "Restart Claude Code to pick up the changes."
