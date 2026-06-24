# Agent Instructions — dot_prompt

This is the `:dot_prompt` Hex package — a compiled language for LLM prompts.
Developed from within the Anantha monorepo, pushed upstream to `dot-prompt/dot-prompt-elixir`.

## Before Working on This Package

Load the development skill:

```
skill(name: "dot-prompt-elixir")
```

Or read the skill directly: `agents/SKILL.md`

## Key Rules

1. **Git submodule — develop here, push upstream** — edit code in `lib/dot_prompt/`, commit, push to `dot-prompt/dot-prompt-elixir`
2. **Keep it standalone** — no references to `Anantha.*`, `Acs.*`, or project internals
3. **Changelog** — every change must add entry in `CHANGELOG.md`
4. **Push BEFORE publishing** to Hex — remote repo must be up to date

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

# Commit and push changes
cd lib/dot_prompt
git add . && git commit -m "feat: ..."
git push

# Update main repo pointer
cd ../..
git add lib/dot_prompt && git commit -m "chore: bump dot_prompt submodule"
```
