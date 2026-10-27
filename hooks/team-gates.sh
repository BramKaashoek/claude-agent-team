#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
event=$(jq -r '.hook_event_name' <<<"$input")
roster="architect ux-specialist ux-tester reviewer reviewer-lite senior-backend junior-backend senior-frontend junior-frontend"

case "$event" in
PreToolUse)
	agent=$(jq -r '.agent_type // ""' <<<"$input")
	agent=${agent##*:}
	[[ " $roster " == *" ${agent%%-[0-9]*} "* ]] || exit 0
	command=$(jq -r '.tool_input.command // ""' <<<"$input")
	if grep -Eq '\bgit\b.*\b(commit|push)\b' <<<"$command"; then
		jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Team members never commit or push. Report to the team lead instead."}}'
	fi
	;;
TaskCreated | TaskCompleted)
	cwd=$(jq -r '.cwd' <<<"$input")
	compgen -G "$cwd/.agent-work/*/status.md" >/dev/null || exit 0
	subject=$(jq -r '.task_subject // ""' <<<"$input")
	description=$(jq -r '.task_description // ""' <<<"$input")
	[[ $subject =~ ^T[0-9]{2}[[:space:]] ]] || exit 0
	if [[ $event == TaskCreated ]] && ! grep -qi 'acceptance criteria' <<<"$description"; then
		echo "Ticket tasks need an 'Acceptance criteria' section in the description." >&2
		exit 2
	fi
	if [[ $event == TaskCompleted ]] && ! grep -q '^Verified:' <<<"$description"; then
		echo "Before completing, add a 'Verified: <what you ran and the result>' line to the task description." >&2
		exit 2
	fi
	;;
esac
