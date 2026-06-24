defmodule DotPrompt.Compiler.FragmentExpander.Static do
  @moduledoc """
  Expands static fragments by compiling them.
  """

  @spec expand(String.t(), map(), keyword()) ::
          {:ok, iodata(), MapSet.t(), map()} | {:error, String.t()}
  def expand(fragment_path, params, opts \\ []) do
    path = String.trim(fragment_path, "{") |> String.trim("}")

    # Static fragments should NOT interpolate variables; leave @varname
    # placeholders for the parent prompt to handle.
    opts = Keyword.put_new(opts, :skip_interpolation, true)

    try do
      case DotPrompt.compile_to_iodata(path, params, opts) do
        {:ok, content, _vary, used, item_files, _, _warnings, _contract, _major, _version, _decls} ->
          {:ok, content, used, item_files}

        {:error, reason} ->
          {:error, "fragment_compile_error: #{path} - #{inspect(reason)}"}
      end
    rescue
      _ -> {:error, "fragment_not_found: #{path}"}
    end
  end
end
