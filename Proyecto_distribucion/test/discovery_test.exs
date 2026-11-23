defmodule CpdDoc.DiscoveryTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Discovery

  test "busca vecinos en la red /28 del hotspot" do
    neighbor_addresses = Discovery.neighbor_ips("172.20.10.3", 28)

    assert length(neighbor_addresses) == 13
    assert hd(neighbor_addresses) == "172.20.10.1"
    assert List.last(neighbor_addresses) == "172.20.10.14"
    refute "172.20.10.3" in neighbor_addresses
  end

  test "busca vecinos en redes /24 y /28" do
    assert length(Discovery.neighbor_ips("192.168.43.10", 24)) == 253

    assert Discovery.neighbor_ips("10.0.0.20", 28) ==
             Enum.map(17..30, fn host_number -> "10.0.0.#{host_number}" end) -- ["10.0.0.20"]
  end

  test "no recorre redes mas grandes que /24" do
    assert Discovery.neighbor_ips("10.1.2.3", 16) == []
  end
end
