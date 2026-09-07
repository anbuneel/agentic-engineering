# Contributing

Thanks for your interest in contributing to Agentic Engineering! This project is a collection of markdown instruction files — skills and agents — that AI coding assistants can follow. Contributions don't require writing traditional code.

## What You Can Contribute

- **New skills** — workflow instructions that users invoke with `/command-name`
- **New agents** — sub-agent instructions that run in the background via the Agent tool
- **Improvements to existing skills/agents** — better instructions, edge case handling, cross-platform fixes
- **Documentation** — README improvements, examples, typo fixes

## Before You Start

1. Check [open issues](https://github.com/anbuneel/agentic-engineering/issues) to see if someone is already working on your idea
2. For new skills or agents, open an issue first to discuss the design before writing it
3. For bug fixes and small improvements, go ahead and open a PR directly

## Writing a Skill

Skills live in `skills/<name>/SKILL.md` and are user-invoked workflows. The layout follows the [Agent Skills specification](https://agentskills.io/specification): the directory name must equal the `name` in the frontmatter, `description` is required, and supporting material goes in `references/`, `scripts/`, or `assets/` beside `SKILL.md`. Follow these conventions:

- **Keep `SKILL.md` under 500 lines** — move command contracts and reference tables into `references/`
- **Start with a clear title and one-line description** of what the skill does
- **Add a "When to Invoke" section** — when should a user reach for this?
- **Add a "Prerequisites" section** — what tools/auth does it need?
- **Structure steps sequentially** with clear phase/step headings
- **Add a "Rules" section at the end** — hard constraints the agent must follow
- **Include preflight checks** — verify tools exist and state is valid before doing anything destructive
- **Handle failures explicitly** — tell the agent what to do when something goes wrong, don't leave it to guess
- **Use Read/Write tools for file operations** — not shell commands like `cp`, `mv`, or redirects
- **Put temp files in `.review/`** inside the project root — cross-platform, gitignored
- **Generate session IDs natively** — no Bash calls for setup
- **Never hardcode AI model names** — inherit from user config

Look at `skills/multi-agent-code-review/SKILL.md` as the reference example for a complex skill, or `extras/skills/security-posture/SKILL.md` for a simpler one.

Only `skills/` ships in the `ae` plugin. `extras/skills/` holds skills that are maintained here but installed by copying; put a new skill there unless it belongs in every install.

## Writing an Agent

Agents live in `agents/` and run as sub-agents via the Agent tool. Follow these conventions:

- **Add YAML frontmatter** with name, description, tools, and model fields
- **Keep agents focused** — one clear responsibility per agent
- **List allowed tools explicitly** — agents should declare what they need
- **Include safety guidelines** — what the agent should NOT do or remove

Look at `agents/codebase-snapshot.md` as the reference example.

## Pull Request Process

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Test your skill/agent by running it on a real project. `claude --plugin-dir <path-to-repo>` loads the working tree without installing
4. Run `claude plugin validate <path-to-repo>` — it checks the manifests, every `SKILL.md`, and agent frontmatter
5. If you changed anything under `tools/`, run the matching Pester suite (`Invoke-Pester tools/codex-setup-sync/tests`)
6. Open a PR with:
   - A clear title describing what you added or changed
   - A description explaining **why** this is useful
   - Confirmation that you tested it

## Style Guidelines

- Write instructions in imperative mood ("Run this command", not "You should run this command")
- Be explicit about error handling — "If X fails, do Y" not just "Run X"
- Use fenced code blocks for all commands
- Keep rules sections as bullet lists, not paragraphs
- No emoji in skill/agent files

## Code of Conduct

Be respectful and constructive. This is a small project — keep discussions focused on making the tools better.

## Questions?

Open an issue or start a discussion on the [GitHub repo](https://github.com/anbuneel/agentic-engineering).
