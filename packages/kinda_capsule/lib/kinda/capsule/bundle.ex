defmodule Kinda.Capsule.Bundle do
  @moduledoc "Exports, verifies, and regrades immutable episode evidence bundles."

  alias Kinda.Capsule.{Artifact, Error, Score, Trace}

  @schema "kinda.capsule.episode/v1"

  @spec export(Trace.t(), binary(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def export(%Trace{} = trace, destination, options \\ []) when is_binary(destination) do
    sources = Keyword.get(options, :artifact_sources, %{})

    with :ok <- validate_export(trace, destination, sources),
         :ok <- File.mkdir_p(destination),
         :ok <- File.mkdir(Path.join(destination, "artifacts")),
         :ok <- File.mkdir(Path.join(destination, "verifier")),
         {:ok, documents} <- write_documents(trace, destination),
         :ok <- copy_artifacts(trace.artifacts, sources, destination),
         {:ok, digest} <- write_manifest(trace, documents, destination) do
      {:ok, digest}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, bundle_error(:export, :filesystem_failure, reason)}
    end
  end

  @spec verify(binary()) :: {:ok, map()} | {:error, Error.t()}
  def verify(destination) when is_binary(destination) do
    manifest_path = Path.join(destination, "manifest.json")

    with {:ok, encoded} <- File.read(manifest_path),
         {:ok, manifest} <- JSON.decode(encoded),
         :ok <- verify_schema(manifest),
         :ok <- verify_bundle_digest(manifest),
         :ok <- verify_documents(destination, manifest["documents"]),
         :ok <- verify_artifacts(destination, manifest["artifacts"]) do
      {:ok, manifest}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, bundle_error(:regrade, :invalid_bundle, reason)}
      false -> {:error, bundle_error(:regrade, :invalid_bundle, :digest_mismatch)}
    end
  end

  @spec regrade(binary(), module(), keyword()) :: {:ok, Score.t()} | {:error, Error.t()}
  def regrade(destination, verifier, options \\ []) when is_atom(verifier) do
    with {:ok, manifest} <- verify(destination),
         :ok <- verify_verifier(manifest, verifier),
         {:ok, bundle} <- load_bundle(destination, manifest),
         {:ok, %Score{} = score} <- safely_regrade(verifier, bundle, options),
         true <- Score.valid?(score) do
      {:ok, score}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, bundle_error(:regrade, :verifier_failure, reason)}
      false -> {:error, bundle_error(:regrade, :invalid_score, nil)}
      other -> {:error, bundle_error(:regrade, :invalid_verifier_return, other)}
    end
  end

  defp validate_export(trace, destination, sources) do
    cond do
      File.exists?(destination) ->
        {:error, bundle_error(:export, :destination_exists, destination)}

      not is_map(sources) ->
        {:error, bundle_error(:export, :invalid_sources, nil)}

      not Enum.all?(trace.artifacts, &Artifact.valid?/1) ->
        {:error, bundle_error(:export, :invalid_artifact, nil)}

      not unique_artifacts?(trace.artifacts) ->
        {:error, bundle_error(:export, :duplicate_artifact, nil)}

      not Enum.all?(trace.artifacts, &valid_source?(&1, sources)) ->
        {:error, bundle_error(:export, :missing_artifact_source, nil)}

      true ->
        :ok
    end
  end

  defp unique_artifacts?(artifacts) do
    ids = Enum.map(artifacts, & &1.id)
    paths = Enum.map(artifacts, & &1.path)
    Enum.uniq(ids) == ids and Enum.uniq(paths) == paths
  end

  defp valid_source?(artifact, sources) do
    case Map.fetch(sources, artifact.id) do
      {:ok, source} ->
        is_binary(source) and File.regular?(source) and digest_file(source) == artifact.sha256

      :error ->
        false
    end
  end

  defp write_documents(trace, destination) do
    documents = %{
      "task.json" => %{
        task_version: trace.task_version,
        fixture_digest: trace.episode.fixture_digest,
        seed: json_value(trace.seed)
      },
      "trace.json" => trace_document(trace),
      "score.json" => json_value(trace.score),
      "verifier/result.json" => json_value(trace.score)
    }

    Enum.reduce_while(documents, {:ok, %{}}, fn {path, value}, {:ok, digests} ->
      encoded = JSON.encode!(value)

      case File.write(Path.join(destination, path), encoded) do
        :ok -> {:cont, {:ok, Map.put(digests, path, sha256(encoded))}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp copy_artifacts(artifacts, sources, destination) do
    Enum.reduce_while(artifacts, :ok, fn artifact, :ok ->
      target = Path.join(destination, artifact.path)

      with :ok <- File.mkdir_p(Path.dirname(target)),
           {:ok, _bytes} <- File.copy(Map.fetch!(sources, artifact.id), target) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp write_manifest(trace, documents, destination) do
    payload =
      json_value(%{
        schema: @schema,
        episode: json_value(trace.episode),
        documents: documents,
        artifacts: Enum.map(trace.artifacts, &json_value/1)
      })

    digest = payload |> JSON.encode!() |> sha256()
    manifest = Map.put(payload, "bundle_digest", digest)

    case File.write(Path.join(destination, "manifest.json"), JSON.encode!(manifest)) do
      :ok -> {:ok, digest}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_schema(%{"schema" => @schema}), do: :ok
  defp verify_schema(_manifest), do: {:error, :unsupported_schema}

  defp verify_bundle_digest(%{"bundle_digest" => expected} = manifest) when is_binary(expected) do
    actual = manifest |> Map.delete("bundle_digest") |> JSON.encode!() |> sha256()
    if secure_equal?(actual, expected), do: :ok, else: {:error, :bundle_digest_mismatch}
  end

  defp verify_bundle_digest(_manifest), do: {:error, :missing_bundle_digest}

  defp verify_documents(root, documents) when is_map(documents) do
    verify_entries(root, Map.to_list(documents))
  end

  defp verify_documents(_root, _documents), do: {:error, :invalid_documents}

  defp verify_artifacts(root, artifacts) when is_list(artifacts) do
    with {:ok, entries} <- artifact_entries(artifacts) do
      verify_entries(root, entries)
    end
  end

  defp verify_artifacts(_root, _artifacts), do: {:error, :invalid_artifacts}

  defp verify_entries(root, entries) do
    if Enum.all?(entries, fn {path, expected} ->
         is_binary(expected) and expected != "" and safe_regular_entry?(root, path) and
           digest_file(Path.join(root, path)) == expected
       end) do
      :ok
    else
      {:error, :entry_digest_mismatch}
    end
  end

  defp artifact_entries(artifacts) do
    Enum.reduce_while(artifacts, {:ok, []}, fn
      %{"path" => path, "sha256" => digest}, {:ok, entries} ->
        {:cont, {:ok, [{path, digest} | entries]}}

      _artifact, _entries ->
        {:halt, {:error, :invalid_artifact_entry}}
    end)
  end

  defp verify_verifier(
         %{
           "episode" => %{
             "verifier_version" => version,
             "verifier_digest" => digest
           }
         },
         verifier
       ) do
    if Code.ensure_loaded?(verifier) and function_exported?(verifier, :version, 0) and
         function_exported?(verifier, :digest, 0) and
         function_exported?(verifier, :regrade, 2) and verifier.version() == version and
         verifier.digest() == digest do
      :ok
    else
      {:error, :verifier_identity_mismatch}
    end
  end

  defp verify_verifier(_manifest, _verifier), do: {:error, :missing_verifier_identity}

  defp load_bundle(destination, manifest) do
    with {:ok, task} <- read_json(destination, "task.json"),
         {:ok, trace} <- read_json(destination, "trace.json"),
         {:ok, score} <- read_json(destination, "score.json") do
      {:ok, %{root: destination, manifest: manifest, task: task, trace: trace, score: score}}
    end
  end

  defp read_json(root, path) do
    with {:ok, encoded} <- File.read(Path.join(root, path)), do: JSON.decode(encoded)
  end

  defp safely_regrade(verifier, bundle, options) do
    verifier.regrade(bundle, options)
  rescue
    exception -> {:error, {:error, exception}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp trace_document(trace) do
    %{
      capsule_id: trace.capsule_id,
      episode_id: trace.episode_id,
      task_version: trace.task_version,
      verifier_version: trace.verifier_version,
      seed: json_value(trace.seed),
      steps: Enum.map(trace.steps, &json_value/1),
      artifacts: Enum.map(trace.artifacts, &json_value/1),
      score: json_value(trace.score)
    }
  end

  defp json_value(nil), do: nil
  defp json_value(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(%_module{} = value) do
    value |> Map.from_struct() |> json_value()
  end

  defp json_value(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_value(item)} end)
  end

  defp json_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_value()
  defp json_value(value), do: inspect(value)

  defp digest_file(path) do
    case File.read(path) do
      {:ok, contents} -> sha256(contents)
      {:error, _reason} -> nil
    end
  end

  defp sha256(contents), do: Base.encode16(:crypto.hash(:sha256, contents), case: :lower)

  defp secure_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right),
       do: :crypto.hash_equals(left, right)

  defp secure_equal?(_left, _right), do: false

  defp safe_bundle_path?(path) when is_binary(path) do
    path != "" and Path.type(path) == :relative and not Enum.member?(Path.split(path), "..")
  end

  defp safe_bundle_path?(_path), do: false

  defp safe_regular_entry?(root, path) do
    safe_bundle_path?(path) and regular_path_components?(Path.expand(root), Path.split(path))
  end

  defp regular_path_components?(root, components) do
    components
    |> Enum.with_index()
    |> Enum.reduce_while(root, fn {component, index}, current ->
      path = Path.join(current, component)
      final? = index == length(components) - 1

      case File.lstat(path) do
        {:ok, %{type: :regular}} when final? -> {:cont, path}
        {:ok, %{type: :directory}} when not final? -> {:cont, path}
        _result -> {:halt, false}
      end
    end)
    |> is_binary()
  end

  defp bundle_error(phase, reason, cause) do
    Error.exception(phase: phase, reason: reason, cause: cause)
  end
end
