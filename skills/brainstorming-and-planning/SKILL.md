---
name: brainstorm-and-plan
description: "Use before ANY creative work — creating features, building components, adding functionality, modifying behavior, or starting a new project. Also use when someone says 'build', 'create', 'add', 'implement', 'let's make', or describes something they want built. Do NOT write code until a design is approved and a plan is written."
---

# Brainstorming and Planning

## Part 1: Brainstorming — Design Before Code

<HARD-GATE>
Do NOT write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

### Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single utility, a config change — all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short, but you MUST present it and get approval.

### Process:

1. **Explore project context** — check files, docs, recent commits
2. **Ask clarifying questions** — one at a time, prefer multiple choice when possible
3. **Propose 2-3 approaches** — with trade-offs and your recommendation. Lead with recommended option and explain why.
4. **Present design** — in sections scaled to complexity, get user approval after each section. Cover: architecture, components, data flow, error handling, testing.
5. **Write design doc** — save to `docs/specs/YYYY-MM-DD-<topic>-design.md` and commit
6. **Spec self-review:**
   - Placeholder scan: Any "TBD", "TODO", incomplete sections? Fix them.
   - Internal consistency: Do sections contradict each other?
   - Scope check: Focused enough for a single plan, or needs decomposition?
   - Ambiguity check: Could any requirement be interpreted two ways? Pick one.
7. **User reviews written spec** — wait for approval before proceeding
8. **Transition to Part 2** — write implementation plan

### Design Principles:

- **One question at a time** — don't overwhelm
- **YAGNI ruthlessly** — remove unnecessary features
- **Design for isolation** — smaller units, one purpose each, well-defined interfaces, testable independently
- **In existing codebases** — explore first, follow existing patterns
- **If too large** — decompose into sub-projects. Each gets its own spec → plan → implementation cycle.

---

## Part 2: Writing Plans — Bite-Sized Executable Tasks

Write plans assuming the engineer executing has zero codebase context and questionable taste. Document everything: files to touch, code, testing, how to verify. DRY. YAGNI. TDD. Frequent commits.

### Plan Document Header:

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence]
**Architecture:** [2-3 sentences]
**Tech Stack:** [Key technologies]

---
```

### Each Task — Bite-Sized (2-5 minutes):

```markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.ts`
- Modify: `exact/path/to/existing.ts`
- Test: `tests/exact/path/to/test.ts`

- [ ] **Step 1: Write the failing test**
  [actual test code]

- [ ] **Step 2: Run test to verify it fails**
  Run: `npm test path/to/test.ts`
  Expected: FAIL with "[specific message]"

- [ ] **Step 3: Write minimal implementation**
  [actual implementation code]

- [ ] **Step 4: Run test to verify it passes**
  Run: `npm test path/to/test.ts`
  Expected: PASS

- [ ] **Step 5: Commit**
  `git add ... && git commit -m "feat: add specific feature"`
```

### No Placeholders — EVER:

These are plan failures — never write them:
- "TBD", "TODO", "implement later"
- "Add appropriate error handling"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — engineer may read out of order)
- Steps describing what to do without showing how (code blocks required)
- References to types/functions not defined in any task

### Self-Review After Writing:

1. **Spec coverage:** Skim each requirement. Can you point to a task? List gaps.
2. **Placeholder scan:** Search for red flags. Fix them.
3. **Type consistency:** Do names match across tasks? (`clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.)

Save plans to: `docs/plans/YYYY-MM-DD-<feature-name>.md`

### Execution:

After saving the plan, execute tasks sequentially:
- Follow each step exactly
- Run verifications as specified
- Use `/tdd` skill for each implementation step
- Use `/verify-done` before marking anything complete

### Git Worktrees:

For feature work, create an isolated worktree:
```bash
# Check for existing .worktrees/ directory, create if needed
# Verify .worktrees/ is in .gitignore (add + commit if not)
git worktree add .worktrees/<branch-name> -b <branch-name>
cd .worktrees/<branch-name>
npm install  # or appropriate setup
npm test     # verify clean baseline
```

When done: verify tests → merge/PR/keep/discard → clean up worktree.
