# dot-prompt

A compiled language for LLM prompts. Define structure, branching, and contracts in `.prompt` files — ship clean prompts to your LLM.

---

## The Problem

Every team building with LLMs ends up in the same place. Prompts scattered across the codebase as f-strings, markdown files, or YAML configs. Branching logic tangled into application code. No versioning. No contracts. No tooling. Token waste invisible. The LLM receives everything — including all the logic you meant to resolve before the call.

```python
# What most teams end up with
prompt = f"""
You are a {role}.
{"Answer the question directly." if is_question else "Continue the lesson."}
{"Give a short answer." if depth == "shallow" else "Give a detailed answer."}
Here is the context: {context}
The user said: {user_message}
"""
```

This works until it doesn't. Then it's very hard to fix.

---

## The Solution

`.prompt` files are compiled before they reach the LLM. Branching resolves at compile time. The LLM receives a clean, flat string with zero logic residue.

```
init do
  @version: 1.0
  @major: 1

  def:
    mode: explanation
    description: Teacher mode — explanation phase.

  params:
    @pattern_step: int[1..5] = 1 -> current step in the teaching sequence
    @variation: enum[analogy, recognition, story]
      -> teaching track — required, selected once per session
    @answer_depth: enum[shallow, medium, deep] = medium -> depth of answers
    @if_input_mode_question: bool = false
      -> true when user has asked an off-pattern question
    @user_input: str -> the user's current message
    @user_level: enum[beginner, intermediate, advanced] = intermediate

  fragments:
    {skill_context}: static from: skills
      match: @skill_names

end init

if @if_input_mode_question is true do
STOP TEACHING. Answer the user's question directly.

The user asked: @user_input

case @answer_depth do
shallow: Shallow Answer
1-2 sentences answering exactly what they asked.

medium: Medium Answer
Explanation + 1 relevant example.

deep: Deep Answer
Full explanation with multiple examples.
end @answer_depth

response do
  {
    "response_type": "question_answer",
    "content": "your response here",
    "ui_hints": { "show_answer_input": false }
  }
end response

else

case @variation do
analogy: #Analogy Track
case @pattern_step do
1: Opening Anchor
Introduce the concept with a single real-world analogy.
2: Deepening the Frame
Build on the analogy. Layer in the formal definition.
3: Concrete Examples
Give 2 examples. First obvious, second subtle.
end @pattern_step

recognition: #Recognition Track
case @pattern_step do
1: Opening Anchor
Open with a question that makes the user realise they already use this concept.
2: Deepening the Frame
Return to their recognition. Use their words to introduce the formal framing.
3: Concrete Examples
Ask the user to generate their own example first.
end @pattern_step
end @variation

@user_input

response do
  {
    "response_type": "teaching",
    "content": "your response here",
    "ui_hints": { "show_answer_input": true }
  }
end response

end @if_input_mode_question
```

**What the LLM receives** for `variation: recognition`, `pattern_step: 2`, `answer_depth: medium`, `if_input_mode_question: false`:

```
Deepening the Frame
Return to their recognition. Use their words to introduce the formal framing.

[user message]

Respond with this JSON:
{
  "response_type": "teaching",
  "content": "your response here",
  "ui_hints": { "show_answer_input": true }
}
```

No branching. No logic. No dead weight. Just the instruction the LLM needs.

---

## Features

**Compiled language** — branching resolves before the LLM call. `if`, `case`, and `vary` blocks compile away entirely. The LLM never sees them.

**Input and output contracts** — params declare the input contract. `response` blocks declare the output contract. Both are versioned together. Breaking changes are detected automatically.

**Fragment composition** — `.prompt` files compose. Static fragments are cached. Dynamic fragments are fetched fresh. Collections load multiple fragments from a folder and composite them.

**Variation tracks** — `vary` blocks select branches randomly or by seed. One seed drives all vary blocks in a prompt deterministically.

**Semantic versioning** — `@major` pins the contract version. Callers pin to a major version and receive non-breaking updates automatically. Old major versions are served from `archive/` for callers that have not upgraded.

**Breaking change detection** — the container detects breaking contract changes on every save. Prompts the developer to version before committing. Hard warning at git commit if unversioned breaking changes exist.

**Snapshot safety** — the container snapshots every `.prompt` file before the first edit after a commit. LLM agents can edit freely — the pre-edit baseline is always preserved for archiving.

**MCP server** — LLM coding tools discover prompt schemas, params, and contracts via MCP without reading raw files.

**Works with any language** — Elixir gets a native library. Everyone else calls the container HTTP API.

---

## How It Works

```
.prompt file + params
        │
        ▼
  [Stage 1] Validate params against declared types
        │
        ▼
  [Stage 2] Resolve if/case — discard untaken branches
            ← structural cache by compile-time params
        │
        ▼
  [Stage 3] Expand fragments — compile static, fetch dynamic
            ← fragment cache by path + params
        │
        ▼
  [Stage 4] Resolve vary slots — seed or random selection
            ← vary branch cache preloaded at startup
        │
        ▼
  [Stage 5] Inject runtime variables
        │
        ▼
  DotPrompt.Result { prompt: "...", response_contract: %{...} }
```

Three independent cache layers. The structural skeleton is cached by compile-time params. Vary branches are preloaded at startup. Fragment content is cached by path and version. Runtime variables are injected fresh every call.

---

## Elixir Library Usage

Add to your `mix.exs`:

```elixir
defp deps do
  [
    {:anantha_dot_prompt, "~> 1.1"}
  ]
end
```

Configure the prompts directory:

```elixir
config :anantha_dot_prompt,
  prompts_dir: Path.expand("../prompts", __DIR__)
```

Usage:

```elixir
# List available prompts
DotPrompt.list_prompts()

# Get prompt schema
{:ok, schema} = DotPrompt.schema("router")
schema.params      # map of declared params

# Render a prompt with params
{:ok, result} = DotPrompt.render("memory/extract/claims", %{actor_name: "Ramesh"}, %{})
result.prompt      # compiled string sent to LLM

# Compile and inject separately
{:ok, compiled} = DotPrompt.compile("my_prompt", params)
final = DotPrompt.inject(compiled.prompt, %{user_input: "hello"})
```

---

## Language Reference

### The One Rule

`@` means variable. Always. Only. Everywhere.
Structural keywords never use `@`.

### Init Block

```
init do
  @major: 1
  @version: 1.0

  def:
    mode: explanation
    description: Human readable description.

  params:
    @name: type = default -> documentation

  fragments:
    {name}: static from: folder_or_file
    {{name}}: dynamic -> fetched fresh each request

  docs do
    Free text documentation. Surfaces via MCP.
  end docs

end init
```

### Types

| Type          | Lifecycle    | Notes                  |
| ------------- | ------------ | ---------------------- |
| `str`         | Runtime      | Cannot drive branching |
| `int`         | Runtime      | Cannot drive branching |
| `int[a..b]`   | Compile-time | Bounded integer        |
| `bool`        | Compile-time |                        |
| `enum[a, b, c]` | Compile-time | Single value           |
| `list[a, b, c]` | Compile-time | Multiple values        |

### Control Flow

```
if @var is x do        # equality
if @var not x do       # inequality
if @var above x do     # greater than
if @var below x do     # less than
if @var min x do       # greater than or equal
if @var max x do       # less than or equal
if @var between x and y do  # inclusive range
elif @var is x do      # chained condition
else                   # fallback
end @var

case @var do           # deterministic branch selection
value: Title
content here
end @var

vary @var do           # random or seeded — enum required
branch_name: content here
end @var
```

### Fragments

```
fragments:
  {single}: static from: skills
    match: @skill           # enum — returns one
  {multi}: static from: skills
    match: @skill_names     # list — returns composited
  {pattern}: static from: skills
    matchRe: @skill_pattern # enum of regex patterns
  {all}: static from: skills
    match: all              # every file in folder
    limit: 10
    order: ascending
  {{live}}: dynamic         # fetched fresh each request
```

### Response Contract

```
response do
  {
    "field": "value",
    "nested": { "bool_field": true }
  }
end response
```

Compiler derives contract schema from JSON structure.
Multiple response blocks compared across branches — warning if compatible, error if incompatible.

### Sigils

| Sigil    | Meaning                          |
| -------- | -------------------------------- |
| `@name`  | Variable                         |
| `{name}` | Static fragment                  |
| `{{name}}` | Dynamic fragment                 |
| `#`      | Comment — never reaches LLM      |
| `->`     | Documentation — surfaces via MCP |
| `=`      | Default value                    |

---

## Versioning

```
init do
  @major: 1      # contract version — callers pin to this
  @version: 1.3  # major.minor — managed by container
end init
```

**Breaking changes** — removing or renaming params, changing types, removing response fields — require `@major` to increment. The old version is archived. Callers pinned to the old major continue to be served.

**Non-breaking changes** — adding params with defaults, changing docs, internal prompt edits — auto-bump `@minor` on commit. Callers never notice.

---

## License

Apache 2.0
