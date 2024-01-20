import Config

# We don't want to set up libcluster in test
create_cluster = System.get_env("DO_NOT_AUTO_JOIN_NODES", "") == ""

config :kv,
  routing_table: [{?a..?z, node()}],
  create_cluster: create_cluster

if Mix.env() == :dev || Mix.env() == :test do
  config :mix_test_interactive,
    clear: true,
    exclude: [~r/___scratch/]
end

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
