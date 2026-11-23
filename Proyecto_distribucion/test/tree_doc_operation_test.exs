defmodule CpdDoc.TreeDocOperationTest do
  use ExUnit.Case, async: true

  alias CpdDoc.{Causal, Protocol, TreeDoc}

  test "codifica una inserción con el formato de red compartido" do
    actor = :pc_a
    {document, operation} = TreeDoc.insert(TreeDoc.new(), 0, "á", {actor, 1})
    message = Protocol.encode_operation(operation, actor, %{actor => 1})

    assert TreeDoc.text(document) == "á"
    assert {:remote, %{op: :ins, from: ^actor, vc: %{^actor => 1}, ch: "á"}} = message

    assert {:ok, received_message} = Protocol.parse(elem(message, 1))
    received_operation = Protocol.to_tree_operation(received_message)
    assert TreeDoc.text(TreeDoc.apply_operation(TreeDoc.new(), received_operation)) == "á"
  end

  test "las inserciones concurrentes convergen en cualquier orden" do
    {document_a, operation_a} = TreeDoc.insert(TreeDoc.new(), 0, "A", {:a, 1})
    {document_b, operation_b} = TreeDoc.insert(TreeDoc.new(), 0, "B", {:b, 1})

    a_then_b = TreeDoc.apply_operation(document_a, operation_b)
    b_then_a = TreeDoc.apply_operation(document_b, operation_a)

    assert TreeDoc.text(a_then_b) == TreeDoc.text(b_then_a)
    assert TreeDoc.text(a_then_b) == "AB"
  end

  test "un borrado recibido antes de la inserción mantiene oculto el carácter" do
    {document, insert_operation} = TreeDoc.insert(TreeDoc.new(), 0, "x", {:a, 1})
    {_document, delete_operation} = TreeDoc.delete(document, 0)
    deleted_first = TreeDoc.apply_operation(TreeDoc.new(), delete_operation)
    deleted_first = TreeDoc.apply_operation(deleted_first, insert_operation)

    assert TreeDoc.text(deleted_first) == ""
  end

  test "el protocolo rechaza mensajes mal formados y caracteres inválidos" do
    valid = %{op: :ins, from: :a, vc: %{a: 1}, pos: [{1, 1, :a}], ch: "ñ"}
    assert {:ok, _message} = Protocol.parse(valid)
    assert :ignore = Protocol.parse(%{valid | pos: []})
    assert :ignore = Protocol.parse(%{valid | ch: "ab"})
    assert :ignore = Protocol.parse(%{valid | vc: %{a: 0}})
    assert :ignore = Protocol.parse(:malformed_message)
  end

  test "la entrega causal espera operaciones faltantes y descarta duplicados" do
    first = %{op: :ins, from: :a, vc: %{a: 1}, pos: [{1, 1, :a}], ch: "a"}
    second = %{op: :ins, from: :a, vc: %{a: 2}, pos: [{1, 2, :a}], ch: "b"}

    {clock, buffer, events} = Causal.receive_message(%{}, [], second)
    assert clock == %{}
    assert buffer == [second]
    assert events == []

    {clock, buffer, [^first, ^second]} = Causal.receive_message(clock, buffer, first)
    assert clock == %{a: 2}
    assert buffer == []
    assert {^clock, ^buffer, []} = Causal.receive_message(clock, buffer, first)
  end

  test "la validación local rechaza caracteres inválidos o demasiado grandes" do
    document = TreeDoc.new()
    assert {:error, :invalid_character} = TreeDoc.insert(document, 0, <<255>>, {:a, 1})

    assert {:error, :invalid_character} =
             TreeDoc.insert(document, 0, String.duplicate("x", 4_097), {:a, 1})
  end

  test "un documento nuevo no contiene texto ni átomos visibles" do
    document = TreeDoc.new()

    assert TreeDoc.text(document) == ""
    assert TreeDoc.visible_entries(document) == []
  end

  test "las inserciones consecutivas al final conservan su orden" do
    {document, _operation} = TreeDoc.insert(TreeDoc.new(), 0, "A", {:a, 1})
    {document, _operation} = TreeDoc.insert(document, 1, "B", {:a, 1})
    {document, _operation} = TreeDoc.insert(document, 2, "C", {:a, 1})

    assert TreeDoc.text(document) == "ABC"
  end

  test "una inserción en el medio queda entre los caracteres vecinos" do
    {document, _operation} = TreeDoc.insert(TreeDoc.new(), 0, "A", {:a, 1})
    {document, _operation} = TreeDoc.insert(document, 1, "C", {:a, 1})
    {document, _operation} = TreeDoc.insert(document, 1, "B", {:a, 1})

    assert TreeDoc.text(document) == "ABC"
  end

  test "una inserción al inicio precede el texto existente" do
    {document, _operation} = TreeDoc.insert(TreeDoc.new(), 0, "B", {:a, 1})
    {document, _operation} = TreeDoc.insert(document, 0, "A", {:a, 1})

    assert TreeDoc.text(document) == "AB"
  end

  test "el borrado oculta solo el carácter seleccionado" do
    {document, _operation} = TreeDoc.insert(TreeDoc.new(), 0, "A", {:a, 1})
    {document, _operation} = TreeDoc.insert(document, 1, "B", {:a, 1})
    {document, _operation} = TreeDoc.insert(document, 2, "C", {:a, 1})
    {document, _operation} = TreeDoc.delete(document, 1)

    assert TreeDoc.text(document) == "AC"
    assert length(TreeDoc.ordered_entries(document)) == 3
    assert length(TreeDoc.visible_entries(document)) == 2
  end

  test "el borrado rechaza índices negativos, fuera de rango y texto vacío" do
    document = TreeDoc.new()

    assert {:error, :invalid_position} = TreeDoc.delete(document, 0)
    assert {:error, :invalid_position} = TreeDoc.delete(document, -1)

    {document, _operation} = TreeDoc.insert(document, 0, "A", {:a, 1})
    assert {:error, :invalid_position} = TreeDoc.delete(document, -1)
    assert {:error, :invalid_position} = TreeDoc.delete(document, 1)
  end

  test "la inserción rechaza índices negativos y posteriores al final" do
    document = TreeDoc.new()

    assert {:error, :invalid_position} = TreeDoc.insert(document, -1, "A", {:a, 1})
    assert {:error, :invalid_position} = TreeDoc.insert(document, 1, "A", {:a, 1})

    {document, _operation} = TreeDoc.insert(document, 0, "A", {:a, 1})
    assert {:error, :invalid_position} = TreeDoc.insert(document, 2, "B", {:a, 1})
  end

  test "aplicar dos veces una inserción conserva un solo carácter" do
    {_document, operation} = TreeDoc.insert(TreeDoc.new(), 0, "X", {:a, 1})
    once = TreeDoc.apply_operation(TreeDoc.new(), operation)
    twice = TreeDoc.apply_operation(once, operation)

    assert TreeDoc.text(once) == "X"
    assert TreeDoc.text(twice) == "X"
    assert TreeDoc.ordered_entries(twice) == TreeDoc.ordered_entries(once)
  end

  test "la fusión de réplicas conserva el mismo texto en ambos sentidos" do
    {document_a, _operation_a} = TreeDoc.insert(TreeDoc.new(), 0, "A", {:a, 1})
    {document_b, _operation_b} = TreeDoc.insert(TreeDoc.new(), 0, "B", {:b, 1})

    merged_ab = TreeDoc.merge(document_a, document_b)
    merged_ba = TreeDoc.merge(document_b, document_a)

    assert TreeDoc.text(merged_ab) == TreeDoc.text(merged_ba)
    assert TreeDoc.text(merged_ab) == "AB"
  end

  test "el protocolo acepta borrados válidos y rechaza posiciones mal formadas" do
    valid_delete = %{op: :del, from: :a, vc: %{a: 1}, pos: [{0, 1, :a}]}

    assert {:ok, ^valid_delete} = Protocol.parse(valid_delete)
    assert :ignore = Protocol.parse(%{valid_delete | pos: [{2, 1, :a}]})
    assert :ignore = Protocol.parse(%{valid_delete | vc: %{a: -1}})
  end
end
