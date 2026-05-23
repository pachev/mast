defmodule MastWeb.Router do
  use MastWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MastWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MastWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/servers/new", DashboardLive, :new
    live "/servers/:id", ServerLive, :show
    live "/servers/:server_id/releases/:name", ReleaseLive, :show
    live "/servers/:server_id/releases/:name/apps/:app_name", ApplicationLive, :show
    live "/alerts", AlertsLive, :index
    live "/audit", AuditLive, :index
    live "/settings", SettingsLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MastWeb do
  #   pipe_through :api
  # end

  # Dev-only routes: LiveDashboard, component showcase. Compiled out
  # in :prod via Mix.env/0 — the showcase is unreachable in production
  # without a redeploy.
  if Mix.env() != :prod do
    import Phoenix.LiveDashboard.Router

    scope "/dev", MastWeb do
      pipe_through :browser

      live "/ui", DevUiLive, :index
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MastWeb.Telemetry
    end
  end
end
