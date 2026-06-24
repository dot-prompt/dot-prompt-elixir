defmodule DotPrompt.Telemetry do
  @moduledoc """
  Emits telemetry events.
  """
  use Agent

  def execute(event, measurements, metadata) do
    # Store event for UI
    store_event(event, measurements, metadata)
    :telemetry.execute([:dot_prompt | event], measurements, metadata)
  end

  def list_events do
    Agent.get(__MODULE__, & &1)
  end

  defp store_event(event, measurements, metadata) do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn state ->
        Enum.take(
          [
            %{
              event: event,
              measurements: measurements,
              metadata: metadata,
              time: DateTime.utc_now()
            }
            | state
          ],
          20
        )
      end)
    end
  end

  def start_link(_) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def start_render(prompt_name, params) do
    execute([:render, :start], %{system_time: System.system_time()}, %{
      prompt: prompt_name,
      params: params
    })
  end

  def stop_render(prompt_name, params, duration_ms, measurements) do
    metadata =
      %{prompt: prompt_name, params: params}
      |> maybe_put(:vary_selections, measurements[:vary_selections])
      |> maybe_put(:cache_hit, measurements[:cache_hit])
      |> maybe_put(:compiled_tokens, measurements[:compiled_tokens])

    measurements =
      measurements
      |> Map.drop([:vary_selections, :cache_hit])
      |> Map.put(:duration, duration_ms)

    execute([:render, :stop], measurements, metadata)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
