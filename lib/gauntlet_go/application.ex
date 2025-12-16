defmodule GauntletGo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GauntletGoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:gauntlet_go, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GauntletGo.PubSub},
      {Registry, keys: :unique, name: GauntletGo.RoomRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: GauntletGo.RoomSupervisor},
      GauntletGoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GauntletGo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GauntletGoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
