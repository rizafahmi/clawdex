defmodule Clawdex.MixProject do
  use Mix.Project

  def project do
    [
      app: :clawdex,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader],
      description: "A personal AI assistant gateway built on the BEAM",
      source_url: "https://github.com/rizafahmi/clawdex",
      homepage_url: "https://github.com/rizafahmi/clawdex",
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ecto_sql],
      mod: {Clawdex.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons, "~> 0.5"},
      {:bandit, "~> 1.5"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.17"},
      {:bypass, "~> 2.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:earmark, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind clawdex", "esbuild clawdex"],
      "assets.deploy": [
        "tailwind clawdex --minify",
        "esbuild clawdex --minify",
        "phx.digest"
      ],
      check: ["format", "credo --strict", "dialyzer"]
    ]
  end
end
