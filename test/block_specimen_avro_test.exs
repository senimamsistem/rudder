defmodule Rudder.BlockSpecimenDecoderEncoderTest do
  use ExUnit.Case, async: true

  setup do
    block_specimen_avro = start_supervised(Rudder.Avro.BlockSpecimen)
    %{block_specimen_avro: block_specimen_avro}
  end

  test "Rudder.Avro.BlockSpecimen.list/0 returns an empty list", %{
    block_specimen_avro: _block_specimen_avro
  } do
    assert Rudder.Avro.BlockSpecimen.list() == :ok
  end

  test "Rudder.Avro.BlockSpecimen.get_schema/0 returns correct schema", %{
    block_specimen_avro: _block_specimen_avro
  } do
    assert Rudder.Avro.BlockSpecimen.get_schema() ==
             "com.covalenthq.brp.avro.ReplicationSegment"
  end

  test "Rudder.Avro.BlockSpecimen.decode_file/1 decodes binary specimen file", %{
    block_specimen_avro: _block_specimen_avro
  } do
    specimen_path =
      "./test-data/codec-0.35/encoded/1-17090940-replica-0x7b8e1d463a0fbc6fce05b31c5c30e605aa13efaca14a1f3ba991d33ea979b12b"

    expected_start_block = 17_090_940
    expected_hash = "0x54245042c6cc9a9d80888db816525d097984c3c2ba4f11d64e9cdf6aaefe5e8d"

    {:ok, decoded_specimen} = Rudder.Avro.BlockSpecimen.decode_file(specimen_path)

    {:ok, decoded_specimen_start_block} = Map.fetch(decoded_specimen, "startBlock")
    {:ok, specimen_event} = Map.fetch(decoded_specimen, "replicaEvent")

    [head | _tail] = specimen_event
    decoded_specimen_hash = Map.get(head, "hash")

    assert decoded_specimen_start_block == expected_start_block
    assert decoded_specimen_hash == expected_hash
  end

  test "Rudder.Avro.BlockSpecimen.decode_dir/1 streams directory binary files", %{
    block_specimen_avro: _block_specimen_avro
  } do
    dir_path = "./test-data/codec-0.35/encoded/*"

    expected_start_block = 17_090_940
    expected_last_block = 17_090_960

    expected_start_hash = "0x54245042c6cc9a9d80888db816525d097984c3c2ba4f11d64e9cdf6aaefe5e8d"
    expected_last_hash = "0x6a1a24cfbee3d64c7f6c7fd478ec0e1112176d1340f18d0ba933352c6ce2026a"

    decode_specimen_stream = Rudder.Avro.BlockSpecimen.decode_dir(dir_path)

    start_block_stream = List.first(decode_specimen_stream)
    last_block_stream = List.last(decode_specimen_stream)

    {:ok, decoded_start_block} =
      start_block_stream
      |> Enum.to_list()
      |> List.keytake(:ok, 0)
      |> elem(0)
      |> elem(1)
      |> Map.fetch("startBlock")

    {:ok, [head | _tail]} =
      start_block_stream
      |> Enum.to_list()
      |> List.keytake(:ok, 0)
      |> elem(0)
      |> elem(1)
      |> Map.fetch("replicaEvent")

    decoded_start_hash = Map.get(head, "hash")

    {:ok, decoded_last_block} =
      last_block_stream
      |> Enum.to_list()
      |> List.keytake(:ok, 0)
      |> elem(0)
      |> elem(1)
      |> Map.fetch("startBlock")

    {:ok, [head | _tail]} =
      last_block_stream
      |> Enum.to_list()
      |> List.keytake(:ok, 0)
      |> elem(0)
      |> elem(1)
      |> Map.fetch("replicaEvent")

    decoded_last_hash = Map.get(head, "hash")

    assert decoded_start_block == expected_start_block
    assert decoded_start_hash == expected_start_hash

    assert decoded_last_block == expected_last_block
    assert decoded_last_hash == expected_last_hash
  end

  test "Rudder.Avro.BlockSpecimen.decode_dir/1 decodes all binary files", %{
    block_specimen_avro: _block_specimen_avro
  } do
    dir_path = "./test-data/codec-0.35/encoded/*"

    expected_specimens = 3

    decode_specimen_stream = Rudder.Avro.BlockSpecimen.decode_dir(dir_path)

    # stream resolved earlier to full specimen list
    resolved_stream = decode_specimen_stream |> Enum.map(fn x -> Enum.to_list(x) end)
    resolved_specimens = length(resolved_stream)

    assert resolved_specimens == expected_specimens
  end

  test "Rudder.Avro.BlockSpecimen.encode_file/1 encodes segment json file", %{
    block_specimen_avro: _block_specimen_avro
  } do
    segment_path = "./test-data/codec-0.35/segment/17090940.segment.json"

    expected_start_block = 17_090_940
    expected_hash = "0x54245042c6cc9a9d80888db816525d097984c3c2ba4f11d64e9cdf6aaefe5e8d"

    {:ok, encoded_segment_avro} = Rudder.Avro.BlockSpecimen.encode_file(segment_path)

    {:ok, decoded_segment_avro} =
      Avrora.decode_plain(encoded_segment_avro, schema_name: "block-ethereum")

    {:ok, decoded_segment_start_block} = Map.fetch(decoded_segment_avro, "startBlock")
    {:ok, replica_event} = Map.fetch(decoded_segment_avro, "replicaEvent")

    [head | _tail] = replica_event
    decoded_segment_hash = Map.get(head, "hash")

    assert decoded_segment_start_block == expected_start_block
    assert decoded_segment_hash == expected_hash
  end

  test "Rudder.Avro.BlockSpecimen.encode_dir/1 streams encoded .json files", %{
    block_specimen_avro: _block_specimen_avro
  } do
    dir_path = "./test-data/codec-0.35/segment/*"

    expected_start_block = 17_090_940
    expected_last_block = 17_090_960

    encoded_segment_stream = Rudder.Avro.BlockSpecimen.encode_dir(dir_path)

    start_segment_stream = List.first(encoded_segment_stream)
    last_segment_stream = List.last(encoded_segment_stream)

    encoded_start_segment_bytes =
      start_segment_stream
      |> Enum.to_list()
      |> List.keytake(:ok, 0)
      |> elem(0)
      |> elem(1)

    {:ok, decoded_start_segment} =
      Avrora.decode_plain(encoded_start_segment_bytes, schema_name: "block-ethereum")

    decoded_start_segment_number = Map.get(decoded_start_segment, "startBlock")

    encoded_last_segment_bytes =
      last_segment_stream
      |> Enum.to_list()
      |> List.keytake(:ok, 0)
      |> elem(0)
      |> elem(1)

    {:ok, decoded_last_segment} =
      Avrora.decode_plain(encoded_last_segment_bytes, schema_name: "block-ethereum")

    decoded_last_segment_number = Map.get(decoded_last_segment, "startBlock")

    assert decoded_start_segment_number == expected_start_block
    assert decoded_last_segment_number == expected_last_block
  end
end
