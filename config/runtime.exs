import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/mast start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :mast, MastWeb.Endpoint, server: true
end

config :mast, MastWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :mast, Mast.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  vault_key =
    System.get_env("MAST_VAULT_KEY") ||
      raise """
      environment variable MAST_VAULT_KEY is missing.
      Generate one with:  openssl rand -base64 32

      This key encrypts SSH private keys at rest. Losing it makes every
      stored key permanently unreadable. Source it from your secrets
      manager (1Password CLI, AWS Secrets Manager, Doppler, etc).
      """

  vault_key_bytes =
    case Base.decode64(vault_key) do
      {:ok, bytes} ->
        bytes

      :error ->
        raise "MAST_VAULT_KEY is not valid base64. Generate with: openssl rand -base64 32"
    end

  if byte_size(vault_key_bytes) != 32 do
    raise """
    MAST_VAULT_KEY must decode to exactly 32 bytes for AES-256-GCM.
    Got #{byte_size(vault_key_bytes)} bytes.

    Generate a correct key with:  openssl rand -base64 32
    """
  end

  config :mast, Mast.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: vault_key_bytes
      }
    ]

  port = String.to_integer(System.get_env("PORT", "4000"))

  # The public URL is the address operators actually share — the one users
  # type into a browser. Bandit always listens on plain HTTP on PORT; TLS
  # belongs at the reverse proxy in front (if any). Two separate concerns:
  #
  #   MAST_PUBLIC_URL          — what generated URLs look like
  #     unset → http://<PHX_HOST or "localhost">:<PORT>
  #     set   → parsed for scheme, host, port
  #
  #   MAST_TRUST_PROXY_HEADERS — whether to trust X-Forwarded-* from a proxy
  #     unset/false → conn.scheme reflects the actual request (plain HTTP)
  #     true        → conn.scheme picks up X-Forwarded-Proto; Secure cookies
  #                   work correctly when behind a TLS-terminating proxy.
  #                   ONLY enable this when a trusted proxy strips client-
  #                   supplied X-Forwarded-* headers before setting its own.
  {url_scheme, url_host, url_port} =
    case System.get_env("MAST_PUBLIC_URL") do
      nil ->
        fallback_host = System.get_env("PHX_HOST") || "localhost"
        {"http", fallback_host, port}

      raw ->
        uri = URI.parse(raw)

        unless uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
          raise """
          MAST_PUBLIC_URL must be a full URL with scheme and host, e.g.:
            https://mast.example.com
            http://192.168.0.71:4000
          Got: #{inspect(raw)}
          """
        end

        # URI.parse fills in default ports (80/443) for the scheme even when
        # the URL string omits one. Detect "explicit" via the raw string so
        # `http://10.0.0.1` (no port) falls back to PORT, not 80.
        explicit_port? = Regex.match?(~r/:\d+(\/|$)/, raw)

        derived_port =
          cond do
            explicit_port? -> uri.port
            uri.scheme == "https" -> 443
            true -> port
          end

        {uri.scheme, uri.host, derived_port}
    end

  trust_proxy_headers? = System.get_env("MAST_TRUST_PROXY_HEADERS") in ~w(1 true TRUE yes YES)

  config :mast, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :mast, MastWeb.Endpoint,
    url: [host: url_host, port: url_port, scheme: url_scheme],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      port: port,
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base,
    trust_proxy_headers: trust_proxy_headers?

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :mast, MastWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :mast, MastWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
