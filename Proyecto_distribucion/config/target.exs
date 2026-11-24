import Config

# Shoehorn arranca la app principal y maneja errores al iniciar.
config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Nerves revisa que arranquen las apps y vuelve atras si alguna falla.
config :nerves_runtime, startup_guard_enabled: true

# Ajusta el reloj en equipos que no tienen reloj de tiempo real.
config :nerves, :erlinit, update_clock: true

# En la Pi, /data apunta a la particion persistente de la app.
config :cpd_doc, operation_log_path: "/data/cpd_doc/operations.log"

# Dejamos los mensajes de consola para la consola de Nerves.
config :logger, :default_handler, false

# Permite entrar por SSH y subir firmware con las llaves de ~/.ssh.
keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No encontre llaves SSH publicas en ~/.ssh. Hace falta una para entrar a la Pi
    y subirle firmware. Agrega una llave publica y vuelve a compilar.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1)

# Ajusta la red con VintageNet y usa CO como codigo del pais.
hotspot_ssid = System.get_env("HOTSPOT_SSID")
hotspot_psk = System.get_env("HOTSPOT_PSK")

if hotspot_ssid in [nil, ""] or hotspot_psk == nil or String.length(hotspot_psk) < 8,
  do:
    Mix.raise("""
        export HOTSPOT_SSID="cpd2026"
        export HOTSPOT_PSK="1234567890"
    """)

config :vintage_net,
  regulatory_domain: "CO",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0",
     %{
       type: VintageNetWiFi,
       vintage_net_wifi: %{
         networks: [
           %{key_mgmt: :wpa_psk, ssid: hotspot_ssid, psk: hotspot_psk}
         ]
       },
       ipv4: %{method: :dhcp}
     }}
  ]

config :mdns_lite,
  # Anuncia el nombre de la Pi y tambien nerves.local para conectarte facil.
  hosts: [:hostname, "nerves"],
  ttl: 120,

  # Anuncia SSH y EPMD en la red local.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "epmd",
      transport: "tcp",
      port: 4369
    }
  ]
