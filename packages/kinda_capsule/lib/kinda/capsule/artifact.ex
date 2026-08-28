defmodule Kinda.Capsule.Artifact do
  @moduledoc "Digest-addressed evidence manifest entry."

  alias Kinda.Capsule.EvidenceRef

  @kinds [:image, :video, :trace, :metrics, :log, :document, :other]

  @enforce_keys [:id, :name, :kind, :path, :sha256, :media_type, :produced_by]
  defstruct [:id, :name, :kind, :path, :sha256, :media_type, :produced_by, metadata: %{}]

  @type producer :: %{optional(:step) => non_neg_integer(), optional(:verifier) => binary()}
  @type t :: %__MODULE__{
          id: binary(),
          name: binary(),
          kind: atom(),
          path: binary(),
          sha256: binary(),
          media_type: binary(),
          produced_by: producer(),
          metadata: map()
        }

  @spec from_file(binary(), binary(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_file(root, relative_path, options) when is_binary(root) and is_binary(relative_path) do
    expanded_root = Path.expand(root)
    source = Path.expand(relative_path, expanded_root)

    with true <- inside?(source, expanded_root),
         {:ok, contents} <- File.read(source) do
      digest = Base.encode16(:crypto.hash(:sha256, contents), case: :lower)
      name = Keyword.get(options, :name, Path.basename(relative_path))

      artifact = %__MODULE__{
        id: Keyword.get(options, :id, digest),
        name: name,
        kind: Keyword.get(options, :kind, :other),
        path: Path.join("artifacts", name),
        sha256: digest,
        media_type: Keyword.get(options, :media_type, "application/octet-stream"),
        produced_by: Keyword.get(options, :produced_by, %{}),
        metadata: Keyword.get(options, :metadata, %{})
      }

      if valid?(artifact), do: {:ok, artifact}, else: {:error, :invalid_artifact}
    else
      false -> {:error, :path_outside_root}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec evidence_ref(t(), keyword()) :: EvidenceRef.t()
  def evidence_ref(%__MODULE__{id: id}, options \\ []) do
    %EvidenceRef{
      artifact: id,
      fragment: Keyword.get(options, :fragment),
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = artifact) do
    Enum.all?(
      [artifact.id, artifact.name, artifact.path, artifact.sha256, artifact.media_type],
      fn
        value -> is_binary(value) and value != ""
      end
    ) and valid_digest?(artifact.sha256) and artifact.kind in @kinds and
      safe_path?(artifact.path) and
      is_map(artifact.produced_by) and is_map(artifact.metadata)
  end

  def valid?(_artifact), do: false

  defp inside?(path, root) do
    relative = Path.relative_to(path, root)
    relative == "." or not Enum.member?(Path.split(relative), "..")
  end

  defp safe_path?(path) do
    case Path.split(path) do
      ["artifacts" | rest] when rest != [] ->
        Path.type(path) == :relative and not Enum.member?(rest, "..")

      _parts ->
        false
    end
  end

  defp valid_digest?(digest) do
    byte_size(digest) == 64 and String.match?(digest, ~r/\A[0-9a-f]{64}\z/)
  end
end
