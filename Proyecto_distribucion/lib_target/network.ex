defmodule CpdDoc.Network do
  use GenServer

  @network_check_interval 10_000
  @retry_interval 5_000

  def start_link(_arguments) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    VintageNet.subscribe(["interface", "wlan0", "addresses"])
    send(self(), :check_network)
    Process.send_after(self(), :search_neighbors, @network_check_interval)
    {:ok, %{ip_address: nil, prefix_length: nil}}
  end

  def handle_info(:search_neighbors, network_state) do
    if network_state.ip_address != nil and Node.alive?() do
      CpdDoc.Discovery.connect_to_subnet(
        network_state.ip_address,
        network_state.prefix_length
      )
    end

    Process.send_after(self(), :search_neighbors, @network_check_interval)
    {:noreply, network_state}
  end

  def handle_info(:check_network, network_state) do
    addresses = VintageNet.get(["interface", "wlan0", "addresses"], [])
    {:noreply, update_network_state(ipv4_address(addresses), network_state)}
  end

  def handle_info({VintageNet, _property, _old_value, new_value, _metadata}, network_state) do
    {:noreply, update_network_state(ipv4_address(new_value), network_state)}
  end

  defp update_network_state(new_network_state, current_network_state) do
    if new_network_state == current_network_state and Node.alive?() do
      current_network_state
    else
      stop_distributed_node()
      start_distributed_node(new_network_state)
    end
  end

  defp stop_distributed_node do
    if Node.alive?() do
      IO.puts("Stopping node #{inspect(Node.self())}")
      Node.stop()
    end
  end

  defp start_distributed_node(nil) do
    IO.puts("wlan0 has no IPv4 address; waiting")
    %{ip_address: nil, prefix_length: nil}
  end

  defp start_distributed_node(network_state) do
    System.cmd("epmd", ["-daemon"])
    node_name = String.to_atom("doc@" <> network_state.ip_address)

    case Node.start(node_name, name_domain: :longnames) do
      {:ok, _pid} ->
        Node.set_cookie(:cpd2026)
        IO.puts("Started node #{inspect(Node.self())}")
        network_state

      {:error, reason} ->
        IO.puts("Could not start #{inspect(node_name)}: #{inspect(reason)}; retrying in 5 seconds")
        Process.send_after(self(), :check_network, @retry_interval)
        %{ip_address: nil, prefix_length: nil}
    end
  end

  defp ipv4_address(nil), do: nil

  defp ipv4_address(addresses) do
    case Enum.find(addresses, fn address -> address.family == :inet end) do
      nil ->
        nil

      address ->
        %{
          ip_address: Enum.join(Tuple.to_list(address.address), "."),
          prefix_length: address.prefixlen
        }
    end
  end
end
