---
name: dot-prompt-elixir
description: Work on the dot_prompt Elixir library. Use when developing dot_prompt prompts or modifying lib/dot_prompt/.
---

# dot-prompt-elixir Development Skill

## When to Use
- Modifying anything in `lib/dot_prompt/` (the `:dot_prompt` Hex package)
- Developing `.prompt` files for this project
- Debugging prompt compilation issues

## Package Structure
```
lib/dot_prompt/
├── lib/dot_prompt.ex           # Public API
├── lib/dot_prompt/
│   ├── ast.ex                  # AST node definitions
│   ├── compiler.ex             # Pipeline orchestrator
│   ├── compiler/               # 7 resolver/compositor modules
│   ├── parser/                 # Lexer, Parser, Validator (3 modules)
│   ├── cache/                  # Structural, Fragment, Vary caches
│   ├── injector.ex             # Runtime variable injection
│   ├── helpers.ex              # Shared utilities
│   ├── telemetry.ex            # Instrumentation
│   ├── result.ex               # Result struct
│   └── application.ex          # OTP Application
├── test/                       # Tests (346)
├── mix.exs                     # Hex package config
├── docs/development.md         # Internal development guide
├── AGENTS.md                   # Agent instructions
├── agents/SKILL.md             # This skill file
├── README.md                   # Full language reference + usage
```

## Compiler Pipeline (5 Stages)
1. **Validate** — type-check all params against declared types
2. **Structural Resolution** — resolve if/case/vary, discard dead branches (cached)
3. **Fragment Expansion** — compile static fragments, fetch dynamic (cached)
4. **Vary Composition** — seed-driven random branch selection (preloaded)
5. **Runtime Injection** — inject runtime string params

## Module Map

### Parser Layer
| Module | Role |
|--------|------|
| `DotPrompt.Parser.Lexer` | Tokenizes `.prompt` file content into tokens |
| `DotPrompt.Parser.Lexer.Token` | Token struct definition |
| `DotPrompt.Parser.Parser` | Parses tokens into AST |
| `DotPrompt.Parser.Validator` | Validates AST structure and types |

### Compiler Layer
| Module | Role |
|--------|------|
| `DotPrompt.Compiler` | Orchestrates the full 5-stage pipeline |
| `DotPrompt.Compiler.Context` | Carries compilation state through stages |
| `DotPrompt.Compiler.IfResolver` | Resolves if/elif/else, removes dead branches |
| `DotPrompt.Compiler.CaseResolver` | Resolves case/when, selects active branch |
| `DotPrompt.Compiler.ResponseCollector` | Collects response contract from all response blocks |
| `DotPrompt.Compiler.VaryCompositor` | Seed-driven random branch selection |
| `DotPrompt.Compiler.FragmentExpander.Static` | Compiles static fragments |
| `DotPrompt.Compiler.FragmentExpander.Dynamic` | Fetches dynamic fragments |
| `DotPrompt.Compiler.FragmentExpander.Collection` | Composites multiple fragments |

### Cache Layer
| Module | Cache Strategy | Invalidated When |
|--------|---------------|------------------|
| `DotPrompt.Cache.Structural` | Compile-time params | Params change |
| `DotPrompt.Cache.Fragment` | Path + params | File changes |
| `DotPrompt.Cache.Vary` | Preloaded at startup | Application restart |

## Key API Endpoints
- `DotPrompt.list_prompts/0` — list available prompts
- `DotPrompt.schema/1` — get prompt schema with params
- `DotPrompt.render/3` — compile + inject in one call
- `DotPrompt.compile/2` — compile prompt (stages 1-4)
- `DotPrompt.inject/2` — inject runtime params (stage 5)

## Golden Rules
- **Develop from within Anantha** — this is the primary dev environment. Edit, commit, push from here
- **Keep standalone** — zero references to `Anantha.*`, `Acs.*`, or project internals
- **Changelog** — every change must add entry in `CHANGELOG.md`
- **Push BEFORE publishing** — ensure remote repo is up to date before `mix hex.publish`

## Testing
```bash
cd lib/dot_prompt && mix test
```
346 tests covering: lexer, parser, validator, compiler stages, cache layers, injector, full pipeline.

## Common Pitfalls
- **Don't** reference `Anantha.*` or `Acs.*` in dot_prompt code — it's a standalone Hex package
- **Don't** forget CHANGELOG — it's the release history for consumers
- **Don't** add project-specific config to dot_prompt — use the main app's config
