# Ajustes generales de la app y el firmware.
import Config

Application.start(:nerves_bootstrap)

# Archivos extra que se copian al firmware.
config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

# Fija la fecha para que las compilaciones se puedan repetir.
config :nerves, source_date_epoch: "1795044054"

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
