import Config

# Test environment configuration

config :har,
  security_tier: :development,
  web_enabled: false,
  telemetry_enabled: false,
  ipfs_enabled: false

# Phoenix endpoint configuration for testing.
# Uses a random port so tests can run in parallel with dev server.
config :har, HARWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_endpoint_tests",
  server: false

config :logger, :console,
  level: :warning
