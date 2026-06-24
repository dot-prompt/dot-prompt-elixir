defmodule DotPrompt.Application do
  @moduledoc false
  # Standard OTP Application callback. Starts the DotPrompt supervision tree
  # including caches (Structural, Fragment, Vary) and Telemetry.
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DotPrompt.Cache.Structural,
      DotPrompt.Cache.Fragment,
      DotPrompt.Cache.Vary,
      DotPrompt.Telemetry
    ]

    opts = [strategy: :one_for_one, name: DotPrompt.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
