defmodule CpdDoc.DiscoveryTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Discovery

  test "neighbor addresses in the iPhone hotspot /28 subnet" do
    neighbor_addresses = Discovery.neighbor_ips("172.20.10.3", 28)

    assert length(neighbor_addresses) == 13
    assert hd(neighbor_addresses) == "172.20.10.1"
    assert List.last(neighbor_addresses) == "172.20.10.14"
    refute "172.20.10.3" in neighbor_addresses
  end

  test "neighbor addresses in a /24 and a /28 that does not start at zero" do
    assert length(Discovery.neighbor_ips("192.168.43.10", 24)) == 253

    assert Discovery.neighbor_ips("10.0.0.20", 28) ==
             Enum.map(17..30, fn host_number -> "10.0.0.#{host_number}" end) -- ["10.0.0.20"]
  end

  test "subnets larger than /24 are not scanned" do
    assert Discovery.neighbor_ips("10.1.2.3", 16) == []
  end
end
