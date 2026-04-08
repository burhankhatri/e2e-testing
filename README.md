# Claude Code Agentic Development Skills

A set of 8 global skills for [Claude Code](https://claude.ai/claude-code) that enforce disciplined, test-driven agentic development. Install once, use in any project.

## What This Solves

Without skills, AI coding agents write tutorial-quality code. They use brittle CSS selectors, skip tests, claim "done" without evidence, and guess at bug fixes. These skills fix that.

| Problem | What the skills do |
|---|---|
| Agent writes fragile `page.locator('.btn')` selectors | Forces `getByRole()` locators that survive redesigns |
| Agent skips E2E tests ("unit tests already cover this") | `/start` makes Playwright E2E mandatory — literally cannot skip it |
| Agent claims "done" after writing code | `/verify-done` requires fresh test output as proof |
| Agent guesses at fixes and goes in circles | `/debug` forces 4-phase root cause analysis before any fix |
| No visual regression testing | `toHaveScreenshot()` with baselines, masking, CI font rendering |
| Tests break in CI but pass locally | CI pipeline patterns with sharding, artifacts, Docker for consistency |
| Agent writes "page loads" smoke tests and calls it coverage | Quality gates reject smoke-only coverage — demands real user workflow tests |
| No screenshots or traces for debugging | Screenshots every test, video on failure, traces on retry — all automatic |

### What's included

- **8 orchestrated skills** that route tasks through the right pipeline
- **17 deep-dive reference guides** (6,400+ lines) covering locators, auth, fixtures, mocking, visual regression, screenshots, CI/CD, debugging, flaky tests, Next.js, POM, test data, clock mocking, iframes, API testing, and test organization
- **Production-tested Playwright patterns** adapted from the [TestDino Playwright Skill](https://github.com/testdino-hq/playwright-skill)
- **Autonomous loop testing** — write tests, let the agent iterate until green, walk away

## Skills

| Skill | Command | What it does |
|-------|---------|--------------|
| **Start** | `/start` | Master orchestrator — routes tasks through the full pipeline with guaranteed test infrastructure and E2E coverage. |
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

```
/start <task description>
```

That's it. `/start` handles everything — it routes your task through the correct skill chain, creates `testing.md` if it doesn't exist, guarantees Playwright E2E tests, and won't claim done without verification.

### What `/start` does

1. **Creates `testing.md`** — auto-detects your project's test setup and writes a testing guide (if one doesn't exist)
2. **Routes the task** — feature, bugfix, refactor, or e2e-only each get the right skill chain
3. **Runs TDD** — every implementation step follows red-green-refactor
4. **Writes E2E tests** — Playwright tests for every user-facing flow (mandatory, not optional)
5. **Verifies** — runs the full test suite and shows evidence before claiming done

### Individual skills

You can also invoke skills directly:

- **New feature** — `/brainstorm-and-plan` then `/tdd`
- **Bug fix** — `/debug` then `/tdd`
- **Refactor** — `/tdd` (tests for existing behavior first, then refactor)
- **E2E tests** — `/e2e-playwright`
- **Autonomous iteration** — `/test-loop`
- **Review** — `/code-review`
- **Before claiming done** — `/verify-done`

## How It Works

The `/start` skill orchestrates the full pipeline:

```
/start <task> → testing.md → Route → TDD → E2E → Verify
```

**Routing examples:**
- `/start add user auth` → brainstorm → tdd → e2e → verify
- `/start fix login loop` → debug → tdd → e2e → verify
- `/start extract auth middleware` → tdd (existing behavior) → refactor → e2e → verify
- `/start add checkout e2e tests` → e2e → verify

## Philosophy

- **Tests over prompts** — if the agent is going in circles, it needs a test, not more instructions
- **Evidence over claims** — no "should work", no "looks correct", run the command and show the output
- **Root cause over quick fix** — trace the bug to its source, don't patch symptoms
- **Design before code** — even "simple" projects get a design review

## License

MIT
