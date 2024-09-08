defmodule KvUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        kv_storage: [
          version: "0.0.0",
          include_executables_for: [:unix],
          applications: [
            kv: :permanent
          ]
        ],
        kv_server: [
          version: "0.0.0",
          include_executables_for: [:unix],
          applications: [
            kv: :permanent,
            kv_s: :permanent
          ]
        ]
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:mix_test_interactive, "~> 3.2", only: [:dev, :test], runtime: false}
    ]
  end
end
