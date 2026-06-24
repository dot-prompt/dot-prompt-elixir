# Agent Instructions — dot_prompt

This is the `:dot_prompt` Hex package — a compiled language for LLM prompts.

## Before Working on This Package

Load the development skill:

```
skill(name: "dot-prompt-elixir")
```

Or read the skill directly: `agents/SKILL.md`

## Key Rules

1. **This is a git submodule** — code changes flow upstream to `dot-prompt/dot-prompt-elixir`, not from here
2. **Documentation is safe** — adding docs, guides, and agent instructions doesn't affect functionality
3. **If fixing an upstream bug** — submit PR to the upstream repo, not here
4. **Keep it standalone** — no references to `Anantha.*`, `Acs.*`, or project internals
5. **To update** from upstream: `cd lib/dot_prompt && git pull origin main`

## Package Contents

| File / Dir | Purpose |
|------------|---------|
| `AGENTS.md` | This file — agent instructions (you are here) |
| `agents/SKILL.md` | Development skill for AI agents |
| `docs/development.md` | Internal architecture guide for contributors |
| `README.md` | Language reference + usage docs |
| `CHANGELOG.md` | Version history |
| `lib/` | Source code (25 modules) |
| `test/` | Tests |

## Quick Start

```bash
# Run tests
cd lib/dot_prompt && mix test

# Update from upstream
cd lib/dot_prompt && git pull origin main
cd ../.. && git add lib/dot_prompt
```
