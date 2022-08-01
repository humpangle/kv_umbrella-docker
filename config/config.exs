import Config

config :kv,
  routing_table: [{?a..?z, node()}]

if Mix.env() == :dev || Mix.env() == :test do
  config :mix_test_interactive,
    clear: true,
    exclude: [~r/___scratch/]
end

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
