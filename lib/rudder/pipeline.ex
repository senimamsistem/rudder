defmodule Rudder.Pipeline do
  alias Rudder.Events
  require Logger

  defmodule ProofSubmissionIrreparableError do
    defexception message: "default message"
  end

  defmodule Spawner do
    use DynamicSupervisor

    @spec start_link(any) :: none
    def start_link(_) do
      DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__, strategy: :one_for_one)
    end

    @impl true
    @spec init(any) ::
            {:ok,
             %{
               extra_arguments: list,
               intensity: non_neg_integer,
               max_children: :infinity | non_neg_integer,
               period: pos_integer,
               strategy: :one_for_one
             }}
    def init(_) do
      DynamicSupervisor.init(strategy: :one_for_one)
    end

    @spec push_hash(any, any) :: :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
    def push_hash(bsp_key, urls) do
      DynamicSupervisor.start_child(
        __MODULE__,
        {Agent,
         fn ->
           Rudder.Pipeline.process_specimen(bsp_key, urls)
         end}
      )
    end
  end

  @spec process_specimen(any, any) :: any
  def process_specimen(bsp_key, urls) do
    start_pipeline_ms = System.monotonic_time(:millisecond)

    try do
      with [_chain_id, _block_height, _block_hash, specimen_hash] <- String.split(bsp_key, "_"),
           {:ok, specimen} <- Rudder.IPFSInteractor.discover_block_specimen(urls),
           {:ok, decoded_specimen} <- Rudder.Avro.BlockSpecimen.decode(specimen),
           {:ok, block_specimen} <- extract_block_specimen(decoded_specimen),
           {:ok, block_result_file_path} <-
             Rudder.BlockProcessor.sync_queue(block_specimen),
           {block_height, ""} <- Integer.parse(block_specimen.block_height),
           block_result_metadata <-
             %Rudder.BlockResultMetadata{
               chain_id: block_specimen.chain_id,
               block_height: block_height,
               block_specimen_hash: specimen_hash,
               file_path: block_result_file_path
             } do
        return_val =
          case Rudder.BlockResultUploader.upload_block_result(block_result_metadata) do
            {:ok, cid, block_result_hash} ->
              :ok = Rudder.Journal.commit(bsp_key)
              {:ok, cid, block_result_hash}

            {:error, :irreparable, errormsg} ->
              raise(Rudder.Pipeline.ProofSubmissionIrreparableError, errormsg)

            {:error, error, _block_result_hash} ->
              Logger.info(
                "#{block_height} has error on upload/proof submission: #{inspect(error)}"
              )

              write_to_backlog(bsp_key, urls, error)
              {:error, error}
          end

        Events.rudder_pipeline_success(System.monotonic_time(:millisecond) - start_pipeline_ms)
        return_val
      else
        err ->
          write_to_backlog(bsp_key, urls, err)
      end
    after
      # resource cleanups
      Briefly.cleanup()
    rescue
      e in Rudder.Pipeline.ProofSubmissionIrreparableError ->
        write_to_backlog(bsp_key, urls, e)
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        Events.rudder_pipeline_failure(System.monotonic_time(:millisecond) - start_pipeline_ms)
        Process.exit(Process.whereis(:bspec_listener), :irreparable)

      e ->
        write_to_backlog(bsp_key, urls, e)
    end
  end

  defp extract_block_specimen(decoded_specimen) do
    start_decode_ms = System.monotonic_time(:millisecond)

    with {:ok, block_height} <- Map.fetch(decoded_specimen, "startBlock"),
         {:ok, replica_event} <- fetch_replica_event(decoded_specimen),
         {:ok, data} <- Map.fetch(replica_event, "data"),
         {:ok, chain_id} <- Map.fetch(data, "NetworkId") do
      :ok = Events.bsp_decode(System.monotonic_time(:millisecond) - start_decode_ms)

      {:ok,
       %Rudder.BlockSpecimen{
         chain_id: chain_id,
         block_height: Integer.to_string(block_height),
         contents: Poison.encode!(data)
       }}
    else
      err -> err
    end
  end

  defp fetch_replica_event(decoded_specimen) do
    case Map.fetch(decoded_specimen, "replicaEvent") do
      {:ok, replica_event} ->
        [replica_event | _] = replica_event
        {:ok, replica_event}

      err ->
        err
    end
  end

  defp write_to_backlog(bsp_key, urls, err) do
    Logger.warn("key #{bsp_key} written to backlog with #{urls}; error: #{inspect(err)}")
    Rudder.Journal.abort(bsp_key)
  end
end
