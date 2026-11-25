defmodule CpdDoc.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [CpdDoc.Discovery, CpdDoc.Replica] ++ target_children()

    opts = [strategy: :one_for_one, name: CpdDoc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if Mix.target() == :host do
    defp target_children, do: []
  else
    defp target_children, do: [CpdDoc.Network]
  end
end
