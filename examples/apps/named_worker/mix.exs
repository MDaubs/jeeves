defmodule NamedWorker.Mixfile do
  use Mix.Project

  @name    :named_worker
  @version "0.1.0"
  @deps [
    service: [ path: "../../.." ]
  ]

  ##################################################
  
  def project do
    [
      app:         @name,
      version:     @version,
      deps:        @deps,
      build_path:  "../../_build",
      config_path: "../../config/config.exs",
      deps_path:   "../../deps",
      lockfile:    "../../mix.lock",
      elixir:      "~> 1.5-dev",
    ]
  end

  def application do
    [ ]
  end

end
