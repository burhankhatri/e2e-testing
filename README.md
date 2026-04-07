# Claude Code Agentic Development Skills

A set of 7 global skills for [Claude Code](https://claude.ai/claude-code) that enforce disciplined, test-driven agentic development. Install once, use in any project.

## Skills

| Skill | Command | What it does |
|-------|---------|--------------|
| **TDD** | `/tdd` | Enforces strict red-green-refactor. No production code without a failing test first. |
| **Systematic Debugging** | `/debug` | 4-phase root cause investigation before any fix attempt. |
| **Verification** | `/verify-done` | Requires fresh evidence before any completion claim. |
| **Brainstorming & Planning** | `/brainstorm-and-plan` | Design-first workflow with specs and implementation plans. |
| **E2E Playwright** | `/e2e-playwright` | Battle-tested Playwright patterns, locators, fixtures, and debugging. |
| **Test Automation Loop** | `/test-loop` | Autonomous test-fix iteration — write tests, let the agent loop until green. |
| **Code Review** | `/code-review` | Two-stage review: spec compliance, then code quality. |

## Install

```bash
git clone https://github.com/burhankhatri/e2e-testing.git
cd e2e-testing
bash install.sh
```

This installs all skills globally to `~/.claude/skills/` and sets up the orchestrator `CLAUDE.md` at `~/.claude/CLAUDE.md`.

> If you already have a `~/.claude/CLAUDE.md`, the installer will warn you and skip overwriting it. You can merge manually or replace it.

## Usage

Once installed, skills are available in any project:

- **New feature** — `/brainstorm-and-plan` then `/tdd`
- **Bug fix** — `/debug` then `/tdd`
- **Refactor** — `/tdd` (tests for existing behavior first, then refactor)
- **E2E tests** — `/e2e-playwright`
- **Autonomous iteration** — `/test-loop`
- **Review** — `/code-review`
- **Before claiming done** — `/verify-done`

### Project Setup

For best results with `/test-loop`, create a `testing.md` in your project root describing how to run your test suites, required env vars, and setup steps. See the [test-loop skill](skills/test-automation-loop/SKILL.md) for a template.

## How It Works

The orchestrator `CLAUDE.md` routes tasks to the right skill chain automatically:

```
User request → CLAUDE.md routing → Skill chain → Verified output
```

**Decision tree:**
- "Build X" → `/brainstorm-and-plan` → `/tdd` → `/verify-done`
- "Fix this" → `/debug` → `/tdd` → `/verify-done`
- "Make it work" → `/test-loop`
- "Review this" → `/code-review`

## Philosophy

- **Tests over prompts** — if the agent is going in circles, it needs a test, not more instructions
- **Evidence over claims** — no "should work", no "looks correct", run the command and show the output
- **Root cause over quick fix** — trace the bug to its source, don't patch symptoms
- **Design before code** — even "simple" projects get a design review

## License

MIT
