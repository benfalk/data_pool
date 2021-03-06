defmodule DataPool.Mixfile do
  use Mix.Project

  def project do
    [app: :data_pool,
     version: "1.0.2",
     elixir: "~> 1.1",
     description: description,
     package: package,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:e_queue, "~> 1.0.0"},
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.11", only: :dev}
    ]
  end

  defp description do
    """
    Utility to buffer items into a queue that follow a simple block
    pattern on calls to push and pop when the queue at a max size or
    empty.
    """
  end

  defp package do
    [
      maintainers: ["Benjamin Falk"],
      links: %{"GitHub" => "https://github.com/benfalk/data_pool"},
      licenses: ["MIT License"]
    ]
  end
end
