defmodule CpdDoc.OperationLog do
  @moduledoc false
  require Logger

  def load(path) do
    case File.read(path) do
      {:ok, contents} ->
        messages =
          contents
          |> String.split("\n", trim: true)
          |> Enum.with_index(1)
          |> Enum.reduce([], fn {line, line_number}, recovered ->
            case decode_record(line) do
              {:ok, message} ->
                [message | recovered]

              :error ->
                Logger.warning("Ignoring invalid operation log record #{line_number} in #{path}")
                recovered
            end
          end)

        {:ok, Enum.reverse(messages)}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def append(_path, []), do: :ok

  def append(path, messages) when is_list(messages) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, file} <- File.open(path, [:append, :binary]) do
      result =
        Enum.reduce_while(messages, :ok, fn message, :ok ->
          record = Base.encode64(:erlang.term_to_binary(message)) <> "\n"

          case IO.binwrite(file, record) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      sync_result = if result == :ok, do: :file.sync(file), else: result
      close_result = File.close(file)

      case {sync_result, close_result} do
        {:ok, :ok} -> :ok
        {{:error, _} = error, _} -> error
        {_, {:error, _} = error} -> error
      end
    end
  end

  defp decode_record(line) do
    with {:ok, binary} <- Base.decode64(line),
         {:remote, raw_message} = message <- :erlang.binary_to_term(binary),
         {:ok, _parsed} <- CpdDoc.Protocol.parse(raw_message) do
      {:ok, message}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end
end
