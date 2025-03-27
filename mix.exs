defmodule Dynamo.MixProject do
  use Mix.Project

  def project do
    [
      app: :dynamo,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:aws, "~> 1.0.0"},
      {:aws_credentials, "~> 0.3.2"},
      {:hackney, "~> 1.16"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
