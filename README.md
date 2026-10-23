# claude-agent-team

A software team for [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams). Your main session acts as the **Project Manager** (the team lead). It spawns specialists from a roster, tracks their work in the shared task list, and is your single point of contact with the team.

| Role | Agent | Model | What it does |
|---|---|---|---|
| Business Analyst | `business-analyst` | Opus | Grills Confluence pages and Azure DevOps PBIs into a spec, keeps the glossary and ADRs, and breaks the spec into backend/frontend tickets |
| Technical Architect | `technical-architect` | Opus | End-to-end design and API contracts, plus an implementation plan for every ticket (where to change what). Read-only |
| UX Specialist | `ux-specialist` | Sonnet | Looks up designs in Figma and turns them into design specs for tickets, and reference sets for the UX Tester |
| UX Tester | `ux-tester` | Sonnet | Tests implemented tickets in the running app with `playwright-cli`, against the acceptance criteria and the Figma designs |
| QA Specialist | `qa-specialist` | Sonnet | Writes the automated tests |
| Reviewer | `reviewer` | Opus | Adversarial review of risky changes |
| Reviewer (lite) | `reviewer-lite` | Sonnet | Quick review of mechanical changes |
| Senior Backend / Frontend | `senior-backend`, `senior-frontend` | Opus | Implementation |

Junior developer definitions are parked in `agents-parked/` and aren't installed.

## Requirements

- Claude Code 2.1.309 or later, with agent teams enabled (see below). Teams only work in an interactive session, not with `-p` or the SDK.
- `jq`, used by the hook and by `install.sh`.
- For the BA: the Atlassian MCP (Confluence) and `az` with the `azure-devops` extension.
- For the UX roles: the Figma MCP. For the UX Tester: [`playwright-cli`](https://www.npmjs.com/package/@playwright/cli).
- Your repo's `.agent-work/` gitignored, since the team keeps its specs, tickets, state and test evidence there.

## Install

Choose **one** of the two options. Installing both gives you every agent twice.

### Option A: plugin

```
/plugin marketplace add BramKaashoek/claude-agent-team
/plugin install agent-team@bramkaashoek
```

Plugins can't set environment variables, so enable agent teams yourself in `~/.claude/settings.json`:

```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

With the plugin, the agents are namespaced (`agent-team:business-analyst`) and the skill is `/agent-team:project-manager`.

### Option B: install script

```bash
git clone https://github.com/BramKaashoek/claude-agent-team.git
cd claude-agent-team && ./install.sh
```

The script symlinks the agents, the skill and the hook into `~/.claude`, so `git pull` updates them. It backs up any files it would replace. It also patches `~/.claude/settings.json` to enable agent teams and register the hook, and keeps the previous version as `settings.json.bak`.

Restart Claude Code after either option.

## Usage

1. Start `claude` in your repo and run `/project-manager` (or `/agent-team:project-manager` if you installed the plugin).
2. Give it the work, e.g. "Implement PBI 1234" or "Fix the checkout rounding bug".
3. The PM proposes a **tier** and you confirm it. Every tier starts with the BA and architect turning the input into agent-ready tickets, even when the input is already a work item. The tier decides who else gets spawned:

   | Tier | Roles |
   |---|---|
   | fix | BA, architect, developer, reviewer-lite |
   | change | BA, architect, developers, QA, reviewer (lite if mechanical), UX Tester (if frontend work) |
   | feature | BA, architect, UX Specialist (if user-facing), developers, QA, reviewer, UX Tester |
   | build | everyone, starting with the BA and architect |

4. The PM creates a worktree off `origin/main` for the work and moves the session into it. All work and every `.agent-work/` file live there.
5. Answer the PM's questions. The BA grills the requirements in rounds: you get numbered questions, each with a recommended answer, and replying "yes" accepts the recommendation. The PM batches questions from the whole team and records your decisions.
6. Approve the ticket breakdown. After that, developers pick up tickets from the shared task list as their blockers clear, and every ticket goes through review and testing.
7. Commit and ship yourself. Teammates can't `git commit` or `git push`.

### Working with the team

- **Agent panel** (below the prompt): ↑/↓ selects a teammate, Enter opens it so you can message it directly, `x` stops it, and Ctrl+T shows the task list.
- **Split panes:** set `"teammateMode": "auto"` in settings and run inside tmux.
- **Teammate permission prompts** appear in your session. Pre-allow the commands you trust to keep them down.
- **After `/resume`**, teammates are gone. Ask the PM to rebuild the team, and it respawns them from the status file.

## Files the team writes

All of these live in your repo and are gitignored, except the glossary and ADRs.

| Path | What |
|---|---|
| `.agent-work/<feature>.md` | The spec and tickets (`T01`, `T02`, …) |
| `.agent-work/<feature>.status.md` | Tier, live teammates, ticket status. Used to rebuild the team after `/resume` |
| `.agent-work/<feature>.decisions.md` | Append-only log of your decisions |
| `.agent-work/<feature>-evidence/` | Test evidence: the UX Tester's and QA Specialist's files, plus one `index.html` page that the PM builds from their reports |
| `GLOSSARY.md`, `docs/adr/` | The domain model, maintained by the BA (committed) |

## Guardrails

`hooks/team-gates.sh` enforces three rules:

- Team agents can't run `git commit` or `git push`. The lead (your session) isn't affected.
- A ticket task (subject `T01 …`) can't be created without acceptance criteria in its description.
- A ticket task can't be completed until its description has a `Verified: <what was run and the result>` line.

The task rules only apply in repos that have a `.agent-work/*.status.md` file.

## Customizing

- **Roles:** edit the files in `agents/`. Each one's body is its full instructions. Teammates ignore the `skills:` frontmatter field, so put instructions in the body.
- **Models:** change `model:` in an agent's frontmatter.
- **Re-enable juniors:** move their files from `agents-parked/` to `agents/`, and add them back to the roster and tier table in `skills/project-manager/SKILL.md`.
