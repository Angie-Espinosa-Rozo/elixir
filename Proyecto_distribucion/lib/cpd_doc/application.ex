defmodule CpdDoc.Application do
  @moduledoc false

  use Application

  @target Mix.target()

  @impl true
  def start(_type, _args) do
    children = children(@target)

    opts = [strategy: :one_for_one, name: CpdDoc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp children(:host), do: [CpdDoc.Discovery, CpdDoc.Replica]

  defp children(_target) do
    [
      {DynamicSupervisor, strategy: :one_for_one, name: CpdDoc.TargetSupervisor},
      CpdDoc.Boot
    ]
  end
end
