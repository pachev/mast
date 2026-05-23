defmodule MastWeb.Plugs.RewriteForwardedHeaders do
  @moduledoc """
  Rewrites the request scheme and port from `X-Forwarded-Proto` and
  `X-Forwarded-Port` when the endpoint is configured to trust its proxy.

  Gated by `:trust_proxy_headers` on `MastWeb.Endpoint`. Set by
  `MAST_TRUST_PROXY_HEADERS=true` in runtime config.

  Only enable when Mast sits behind a trusted reverse proxy that strips
  client-supplied X-Forwarded-* headers before setting its own. Trusting
  these headers from arbitrary direct clients lets an attacker spoof the
  apparent request scheme and bypass any code that branches on it
  (cookie `Secure` flag, `conn.scheme` checks).
  """
  @behaviour Plug

  @rewrites [:x_forwarded_proto, :x_forwarded_port]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if MastWeb.Endpoint.config(:trust_proxy_headers, false) do
      Plug.RewriteOn.call(conn, Plug.RewriteOn.init(@rewrites))
    else
      conn
    end
  end
end
