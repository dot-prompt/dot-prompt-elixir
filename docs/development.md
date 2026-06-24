# DotPrompt — Development Guide

## Architecture Overview

DotPrompt is a 25-module Elixir library with a 5-stage compiler pipeline and 3 independent cache layers. Everything is centered around a single data flow: `.prompt` file + params → compiled prompt string + response contract.

## Compiler Pipeline

```
.prompt file + params
        │
        ▼
  [Stage 1] Validate — validate params against declared types
        │
        ▼
  [Stage 2] Structural Resolution — resolve if/case/vary, discard dead branches
        │    ← structural cache by compile-time params
        ▼
  [Stage 3] Fragment Expansion — compile static fragments, fetch dynamic ones
        │    ← fragment cache by path + params
        ▼
  [Stage 4] Vary Composition — seed-driven random branch selection
        │    ← vary cache preloaded at startup
        ▼
  [Stage 5] Runtime Injection — inject runtime string params
        │
        ▼
  DotPrompt.Result { prompt, response_contract }
```

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

### Core
| Module | Role |
|--------|------|
| `DotPrompt` | Main public API |
| `DotPrompt.AST` | AST node definitions |
| `DotPrompt.Injector` | Runtime variable injection |
| `DotPrompt.Helpers` | Shared utility functions |
| `DotPrompt.Result` | Result struct |
| `DotPrompt.Telemetry` | Instrumentation events |
| `DotPrompt.Application` | OTP Application |
| `DotPrompt.DotPromptVersionTracker` | Version management |
| `DotPrompt.DotPromptGithubPoller` | GitHub poller for version tracking |

## Cache Architecture

Three caches with different lifetimes:

1. **Structural Cache**: Keyed by compile-time params (enum, int range, bool values). Invalidated when params change. Most effective for prompt skeletons that rarely change.

2. **Fragment Cache**: Keyed by fragment path + params. Invalidated when underlying fragment files change. Static fragments cached forever; dynamic fragments uncached.

3. **Vary Cache**: Preloaded at application startup. All vary branches loaded once. Deterministic — same seed always selects same branch.

## Adding Features

- **New param type**: Add type to `Parser.Validator`, update docs
- **New control flow**: Add resolver module under `Compiler/`, register in `Compiler`
- **New fragment source**: Add module under `Compiler/FragmentExpander/`, register in `Compiler`
- **New cache layer**: Implement in `Cache/`, follow existing behaviour pattern

## Code Philosophy

1. **Compiled output is clean** — no branching, no dead code, no LLM-visible logic
2. **Deterministic** — same input + same seed = same output every time
3. **Type-safe params** — all params validated at compile time where possible
4. **Cache aggressively** — structural compilation is expensive, cache everything safely
