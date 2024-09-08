import Config

if Mix.env() == :dev || Mix.env() == :test do
  config :mix_test_interactive,
    clear: true,
    exclude: [~r/___scratch/]
end
