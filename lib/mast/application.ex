defmodule Mast.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MastWeb.Telemetry,
      Mast.Repo,
      {DNSCluster, query: Application.get_env(:mast, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mast.PubSub},
      {Oban, Application.fetch_env!(:mast, Oban)},
      MastWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mast.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MastWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
