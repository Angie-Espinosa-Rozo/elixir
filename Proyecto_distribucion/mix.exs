defmodule CpdDoc.MixProject do
  use Mix.Project

  @app :cpd_doc
  @version "0.1.0"
  @all_targets [
    :bbb,
    :mangopi_mq_pro,
    :qemu_aarch64,
    :rpi,
    :rpi0,
    :rpi0_2,
    :rpi2,
    :rpi3,
    :rpi4,
    :rpi5,
    :trellis,
    :x86_64
  ]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.20",
      archives: [nerves_bootstrap: "~> 1.17"],
      listeners: listeners(Mix.target(), Mix.env()),
      elixirc_paths: elixirc_paths(Mix.target()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}]
    ]
  end

  # Aqui se define que arranca la aplicacion.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {CpdDoc.Application, []}
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  # Aqui van las dependencias del proyecto.
  defp deps do
    [
      # Estas dependencias se usan en todos los equipos.
      {:nerves, "~> 1.13", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:logger_backends, "~> 1.0"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.5.0"},

      # Nerves.Runtime tambien se usa en la laptop para desarrollar y probar.
      # Mira config/host.exs para ver sus ajustes.
      {:nerves_runtime, "~> 0.13.12"},

      # Estas dependencias se usan en los equipos Nerves, no en la laptop.
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},

      # Cada sistema corresponde a un equipo distinto.
      # Al actualizarlo, revisa sus cambios de Linux y Erlang.
      {:nerves_system_bbb, "~> 2.19", runtime: false, targets: :bbb},
      {:nerves_system_mangopi_mq_pro, "~> 0.6", runtime: false, targets: :mangopi_mq_pro},
      {:nerves_system_qemu_aarch64, "~> 0.1", runtime: false, targets: :qemu_aarch64},
      {:nerves_system_rpi, "~> 2.0", runtime: false, targets: :rpi},
      {:nerves_system_rpi0, "~> 2.0", runtime: false, targets: :rpi0},
      {:nerves_system_rpi0_2, "~> 2.0", runtime: false, targets: :rpi0_2},
      {:nerves_system_rpi2, "~> 2.0", runtime: false, targets: :rpi2},
      {:nerves_system_rpi3, "~> 2.0", runtime: false, targets: :rpi3},
      {:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4},
      {:nerves_system_rpi5, "~> 2.0", runtime: false, targets: :rpi5},
      {:nerves_system_trellis, "~> 0.4", runtime: false, targets: :trellis},
      {:nerves_system_x86_64, "~> 1.24", runtime: false, targets: :x86_64}
    ]
  end

  def release do
    [
      overwrite: true,
      # El nodo distribuido se prende al arrancar, con la IP del equipo.
      cookie: "cpd2026",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  defp listeners(_, _), do: []

  defp elixirc_paths(:host), do: ["lib"]
  defp elixirc_paths(_), do: ["lib", "lib_target"]
end
