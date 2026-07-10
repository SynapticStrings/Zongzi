defmodule Zongzi.MixProject do
  use Mix.Project

  def project do
    [
      app: :zongzi,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: [precommit: ["compile --warnings-as-errors", "format", "test"]]
    ]
  end

  def application, do: []

  def cli, do: [preferred_envs: [precommit: :test]]
end
