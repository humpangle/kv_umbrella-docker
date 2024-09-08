import Config

if Mix.env() == :dev || Mix.env() == :test do
  command_args =
    case System.get_env("MIX_TEST_INTERACTIVE_COMMAND_CONFIG", "")
         |> String.trim() do
      "" ->
        ["-S", "mix"]

      cmd_string ->
        String.split(cmd_string, "\s", trim: true)
    end

  config :mix_test_interactive,
    # clear: true,
    exclude: [~r/___scratch/],
    command: {"elixir", command_args}
end
