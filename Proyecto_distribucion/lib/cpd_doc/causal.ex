defmodule CpdDoc.Causal do
  @moduledoc "Auxiliar para que las operaciones lleguen en orden causal."

  def next_local(clock, actor) do
    sequence = Map.get(clock, actor, 0) + 1
    {sequence, Map.put(clock, actor, sequence)}
  end

  def receive_message(clock, buffer, message) do
    case classify(clock, message) do
      :duplicate ->
        {clock, buffer, []}

      :wait ->
        if Enum.any?(buffer, &same_operation?(&1, message)),
          do: {clock, buffer, []},
          else: {clock, buffer ++ [message], []}

      :deliver ->
        drain(Map.put(clock, message.from, message.vc[message.from]), buffer, [message])
    end
  end

  defp classify(clock, %{from: actor, vc: message_clock}) do
    remote_sequence = Map.get(message_clock, actor, 0)
    local_sequence = Map.get(clock, actor, 0)

    cond do
      remote_sequence <= local_sequence ->
        :duplicate

      remote_sequence == local_sequence + 1 and
          Enum.all?(message_clock, fn {dependency, seq} ->
            dependency == actor or seq <= Map.get(clock, dependency, 0)
          end) ->
        :deliver

      true ->
        :wait
    end
  end

  defp drain(clock, buffer, delivered) do
    waiting = Enum.reject(buffer, &(classify(clock, &1) == :duplicate))

    case Enum.find(waiting, &(classify(clock, &1) == :deliver)) do
      nil ->
        {clock, waiting, Enum.reverse(delivered)}

      next ->
        drain(Map.put(clock, next.from, next.vc[next.from]), List.delete(waiting, next), [
          next | delivered
        ])
    end
  end

  defp same_operation?(left, right),
    do: left.from == right.from and left.vc[left.from] == right.vc[right.from]
end
