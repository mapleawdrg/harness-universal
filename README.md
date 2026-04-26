# harness-universal

9-Agent **Generator-Evaluator** harness for [Claude Code](https://claude.com/claude-code).
Project-agnostic — drop into any repo, configure once, use everywhere.

## Quick start

```bash
# 1. Copy into your project
cp -r ~/harness-universal/.claude /path/to/your-project/.claude
mkdir -p /path/to/your-project/.harness

# 2. Edit .claude/harness.config.json (project name, actor role, test commands)
# 3. See .claude/README_HARNESS.md for full adoption guide
```

## Structure

```
.claude/
├── agents/              # 9 system prompts (product/architect/plan/dev/qa/explain)
├── hooks/               # PreToolUse / PostToolUse / SubagentStop / Stop
├── harness.config.json  # Project-specific values (must edit)
├── agents-manifest.json # Agent → output file mapping
├── settings.json        # Hook registration
└── README_HARNESS.md    # Full adoption guide + Anthropic blog references
```

## Agent loop

```
product-designer ↔ product-reviewer  (max 3)
        ↓ PASS
architect ↔ architect-reviewer       (max 3)
        ↓ PASS
planner ↔ plan-reviewer              (max 3)
        ↓ PASS
dev ↔ qa                             (max 3)
        ↓ PASS
(complete)

cross-cutting: explain (layer triage when dev is blocked)
```

Generator agents write artifacts; evaluator agents only judge (never edit). Loop bounded at 3 iterations per pair.

## Anthropic alignment

Built on principles from:
- [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)
- [Scaling Managed Agents](https://www.anthropic.com/engineering/managed-agents)

See `.claude/README_HARNESS.md` for the full alignment table.

## Status

v0 — Universal extraction. Known v1 limits documented in `.claude/README_HARNESS.md` §"현재 v1 한계".
