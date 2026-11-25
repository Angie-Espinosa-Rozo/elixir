defmodule CpdDoc.Editor do
  @moduledoc """
  A small line-oriented terminal editor for the shared Treedoc document.

  Start it from IEx with `CpdDoc.Editor.start()`. Enter `:exit` to return to IEx.
  """

  @refresh_ms 50
  @default_terminal_width 80
  @default_terminal_rows 24

  def start do
    text = CpdDoc.Replica.text()
    edit_loop(String.length(text), nil)
  end

  defp edit_loop(cursor, notice) do
    text = CpdDoc.Replica.text()
    cursor = min(cursor, String.length(text))
    render(text, cursor, notice, false)
    editor = self()
    input = spawn(fn -> read_input(editor) end)
    wait_for_line(input, text, cursor, notice)
  end

  defp wait_for_line(input, text, cursor, notice) do
    receive do
      {:editor_line, nil} ->
        :ok

      {:editor_line, line} ->
        line = String.trim_trailing(line, "\n") |> String.trim_trailing("\r")
        latest = CpdDoc.Replica.text()
        cursor = sync_cursor(text, latest, cursor)
        {next_cursor, next_notice, continue?} = apply_line(line, latest, cursor)
        if continue?, do: edit_loop(next_cursor, next_notice), else: :ok

      {:editor_insert, line, add_newline?} ->
        latest = CpdDoc.Replica.text()
        cursor = sync_cursor(text, latest, cursor)
        suffix = if add_newline?, do: "\n", else: ""
        {next_cursor, next_notice, continue?} = insert(cursor, line <> suffix)
        if continue?, do: edit_loop(next_cursor, next_notice), else: :ok
    after
      @refresh_ms ->
        latest = CpdDoc.Replica.text()
        cursor = sync_cursor(text, latest, cursor)

        if latest != text do
          render(latest, cursor, nil, true)
        end

        wait_for_line(input, latest, cursor, notice)
    end
  end

  defp sync_cursor(previous_text, latest_text, cursor) do
    if cursor == String.length(previous_text),
      do: String.length(latest_text),
      else: min(cursor, String.length(latest_text))
  end

  defp read_input(editor) do
    case IO.gets("edita> ") do
      nil ->
        send(editor, {:editor_line, nil})

      raw_line ->
        line = String.trim_trailing(raw_line, "\n") |> String.trim_trailing("\r")

        cond do
          String.starts_with?(line, "::") ->
            read_newline_choice(editor, ":" <> String.trim_leading(line, ":"))

          String.starts_with?(line, ":") ->
            send(editor, {:editor_line, line})

          true ->
            read_newline_choice(editor, line)
        end
    end
  end

  defp read_newline_choice(editor, line) do
    case IO.gets("¿Salto de línea? (s/n)> ") do
      nil ->
        send(editor, {:editor_line, nil})

      answer ->
        case String.trim(answer) |> String.downcase() do
          "s" -> send(editor, {:editor_insert, line, true})
          "n" -> send(editor, {:editor_insert, line, false})
          _ ->
            IO.puts("Responde s o n.")
            read_newline_choice(editor, line)
        end
    end
  end

  defp apply_line(":exit", _text, cursor), do: {cursor, "Volviendo a IEx", false}

  defp apply_line(":clear", _text, cursor) do
    case CpdDoc.Replica.clear() do
      :ok -> {0, "Documento borrado", true}
      {:error, reason} -> {cursor, "No se pudo borrar: #{inspect(reason)}", true}
    end
  end

  defp apply_line(<<":d ", count_text::binary>>, text, cursor) do
    case Integer.parse(String.trim(count_text)) do
      {count, ""} when count > 0 ->
        count = min(count, cursor)
        delete(cursor - count, count, text, cursor - count)

      _ ->
        {cursor, "Uso: :d cantidad", true}
    end
  end

  defp apply_line(":" <> _unknown, _text, cursor),
    do: {cursor, "Usa :d N, :clear o :exit", true}

  defp insert(cursor, ""), do: {cursor, nil, true}

  defp insert(cursor, text) do
    case CpdDoc.Replica.insert(cursor, text) do
      :ok -> {cursor + String.length(text), nil, true}
      {:error, reason} -> {cursor, "No se pudo insertar: #{inspect(reason)}", true}
    end
  end

  defp delete(_index, count, _text, cursor) when count <= 0, do: {cursor, nil, true}

  defp delete(index, count, _text, cursor) do
    case CpdDoc.Replica.delete(index, count) do
      :ok -> {cursor, nil, true}
      {:error, reason} -> {cursor, "No se pudo borrar: #{inspect(reason)}", true}
    end
  end

  defp render(text, cursor, notice, live?) do
    if live?, do: IO.write("\e[s\e[H"), else: IO.write(IO.ANSI.clear() <> IO.ANSI.home())

    width = terminal_dimension(:columns, @default_terminal_width)
    rows = terminal_dimension(:rows, @default_terminal_rows)
    panel_width = max(width - 4, 1)
    margin = div(width - panel_width, 2)
    visible_lines = max(rows - 9, 1)
    doc_lines = visible_doc_lines(text, cursor, visible_lines)
    total_lines = length(String.split(text, "\n", trim: false))
    first_line = max(cursor_line(text, cursor) - visible_lines + 1, 0)

    lines =
      [
        "",
        centered(
          "Documento compartido  ·  #{Atom.to_string(node())}  ·  nodos: #{length(Node.list()) + 1}",
          panel_width
        ),
        String.duplicate("─", panel_width)
      ] ++
        doc_lines ++
        [
          String.duplicate("─", panel_width),
          centered(
            "Cursor: #{cursor}  |  líneas #{first_line + 1}-#{min(first_line + visible_lines, total_lines)} de #{total_lines}",
            panel_width
          ),
          centered("Escribe texto y elige s = salto de línea o n = continuar", panel_width),
          centered(":d N borrar atrás · :clear todo · :exit salir", panel_width)
        ]

    lines = if notice, do: List.replace_at(lines, -1, notice), else: lines

    Enum.each(lines, fn line ->
      content = safe_line(line, panel_width) |> String.pad_trailing(panel_width)
      IO.write("\e[2K" <> String.duplicate(" ", margin) <> content <> "\r\n")
    end)

    if live?, do: IO.write("\e[u")
  end

  defp visible_doc_lines(text, cursor, visible_lines) do
    rows = String.split(text, "\n", trim: false)
    start = max(cursor_line(text, cursor) - visible_lines + 1, 0)

    rows
    |> Enum.drop(start)
    |> Enum.take(visible_lines)
    |> then(&(&1 ++ List.duplicate("", visible_lines - length(&1))))
  end

  defp cursor_line(text, cursor) do
    text
    |> String.graphemes()
    |> Enum.take(cursor)
    |> Enum.count(&(&1 == "\n"))
  end

  defp centered(line, width) do
    line_width = String.length(line)
    left_padding = max(div(width - line_width, 2), 0)
    String.duplicate(" ", left_padding) <> line
  end

  defp terminal_dimension(dimension, default) do
    result = if dimension == :columns, do: :io.columns(), else: :io.rows()

    case result do
      {:ok, value} when is_integer(value) and value > 0 -> value
      _ -> default
    end
  end

  defp safe_line(line, width) do
    line
    |> String.graphemes()
    |> Enum.take(width)
    |> Enum.map_join(fn grapheme -> if String.printable?(grapheme), do: grapheme, else: "�" end)
  end
end
