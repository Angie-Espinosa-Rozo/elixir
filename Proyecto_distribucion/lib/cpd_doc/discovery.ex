defmodule CpdDoc.Discovery do
  use GenServer

  def start_link(_arguments) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def connect_to_subnet(ip_address, prefix_length) do
    for neighbor_ip <- neighbor_ips(ip_address, prefix_length) do
      spawn(fn -> Node.connect(String.to_atom("doc@" <> neighbor_ip)) end)
    end

    :ok
  end

  def neighbor_ips(ip_address, prefix_length) do
    [first_octet, second_octet, third_octet, last_octet] =
      Enum.map(String.split(ip_address, "."), &String.to_integer/1)

    if prefix_length < 24 do
      []
    else
      subnet_size = Integer.pow(2, 32 - prefix_length)
      subnet_start = last_octet - rem(last_octet, subnet_size)

      for host_number <- (subnet_start + 1)..(subnet_start + subnet_size - 2),
          host_number != last_octet do
        Enum.join([first_octet, second_octet, third_octet, host_number], ".")
      end
    end
  end

  def init(:ok) do
    :net_kernel.monitor_nodes(true)
    {:ok, %{}}
  end

  def handle_info({:nodeup, node_name}, state) do
    IO.puts("connected to #{inspect(node_name)}")
    {:noreply, state}
  end

  def handle_info({:nodedown, node_name}, state) do
    IO.puts("disconnected from #{inspect(node_name)}")
    {:noreply, state}
  end
end
