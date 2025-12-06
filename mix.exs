defmodule Dynamo.MixProject do
  use Mix.Project

  def project do
    [
      app: :dynamo,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      
      # Docs
      name: "Dynamo",
      source_url: "https://github.com/bmalum/dynamo",
      docs: docs()
    ]
  end
  
  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "Agents.md",
        "guides/SIMPLE_EXAMPLE.md",
        "guides/USER_POST_EXAMPLE.md",
        "guides/GSI_USAGE_GUIDE.md",
        "guides/BELONGS_TO_GUIDE.md",
        "guides/PARTIAL_SORT_KEY_EXAMPLE.md",
        "guides/STREAMING_QUICKSTART.md",
        "guides/STREAMING_GUIDE.md",
        "guides/STREAMING_PROPOSAL.md"
      ],
      groups_for_extras: [
        "Getting Started": [
          "README.md",
          "guides/SIMPLE_EXAMPLE.md"
        ],
        "Guides": [
          "Agents.md",
          "guides/USER_POST_EXAMPLE.md",
          "guides/GSI_USAGE_GUIDE.md",
          "guides/BELONGS_TO_GUIDE.md",
          "guides/PARTIAL_SORT_KEY_EXAMPLE.md"
        ],
        "Streaming": [
          "guides/STREAMING_QUICKSTART.md",
          "guides/STREAMING_GUIDE.md",
          "guides/STREAMING_PROPOSAL.md"
        ]
      ],
      groups_for_modules: [
        "Core": [
          Dynamo.Schema,
          Dynamo.Table,
          Dynamo.Encoder,
          Dynamo.Decoder
        ],
        "Streaming": [
          Dynamo.Table.Stream,
          Dynamo.Table.Stream.Producer
        ],
        "Utilities": [
          Dynamo.Config,
          Dynamo.Error,
          Dynamo.Helper,
          Dynamo.Logger
        ]
      ]
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
      {:req, "~> 0.5.0"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      
      # Optional: For streaming support
      {:gen_stage, "~> 1.2", optional: true},
      {:flow, "~> 1.2", optional: true}
    ]
  end
end
