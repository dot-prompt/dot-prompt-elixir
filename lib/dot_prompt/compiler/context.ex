defmodule DotPrompt.Compiler.Context do
  @moduledoc """
  Context struct for the dot-prompt compiler to reduce function arity.
  """

  defstruct [
    :params,
    :fragment_defs,
    :vary_map,
    :used_vars,
    :indent_level,
    :files_meta,
    :section_count,
    :declarations,
    :current_dir,
    :opts
  ]

  @type t :: %__MODULE__{
          params: map(),
          fragment_defs: map(),
          vary_map: map(),
          used_vars: MapSet.t(),
          indent_level: integer(),
          files_meta: map(),
          section_count: integer(),
          declarations: map(),
          current_dir: String.t(),
          opts: keyword()
        }

  def new(params, fragment_defs, declarations, opts \\ []) do
    %__MODULE__{
      params: params,
      fragment_defs: fragment_defs,
      vary_map: %{},
      used_vars: MapSet.new(),
      indent_level: opts[:indent] || 0,
      files_meta: %{},
      section_count: 0,
      declarations: declarations,
      current_dir: opts[:current_dir] || "",
      opts: opts
    }
  end

  def increment_indent(ctx) do
    %{ctx | indent_level: ctx.indent_level + 1}
  end

  def increment_section(ctx) do
    %{ctx | section_count: ctx.section_count + 1}
  end

  def add_used_var(ctx, var) do
    %{ctx | used_vars: MapSet.put(ctx.used_vars, var)}
  end

  def merge_files(ctx, new_files) do
    %{ctx | files_meta: Map.merge(ctx.files_meta, new_files)}
  end

  def put_vary(ctx, name, branches) do
    %{ctx | vary_map: Map.put(ctx.vary_map, name, branches)}
  end
end
