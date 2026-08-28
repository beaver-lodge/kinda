defmodule Kinda.Capsule.Web3DTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule.Spec
  alias Kinda.Capsule.Web3D
  alias Kinda.Capsule.Web3D.Task
  alias Kinda.Capsule.Web3D.Verifier

  @tag :tmp_dir
  test "builds a versioned Capsule spec for a fresh sandbox", %{tmp_dir: parent} do
    spec = Web3D.spec(parent_directory: parent)

    assert :ok = Spec.validate(spec)
    assert spec.fixture_digest == Web3D.digest_tree(Web3D.fixture_root())
    assert spec.verifier_digest == Verifier.digest()
    assert spec.runtime.viewport == %{width: 1440, height: 900}
  end

  @tag :tmp_dir
  test "trusted task writes integrity evidence from owned digests", %{tmp_dir: workspace} do
    artifacts = Path.join(workspace, "artifacts")
    File.mkdir!(artifacts)
    File.write!(Path.join(workspace, "package-lock.json"), "fixture")
    fixture_digest = sha256("fixture")
    verifier_digest = sha256("verifier")

    File.write!(
      Path.join(artifacts, "browser.json"),
      JSON.encode!(%{"verifier_digest" => verifier_digest})
    )

    assert :ok =
             Task.write_integrity_evidence(workspace,
               protected_digest: fixture_digest,
               browser_verifier_digest: verifier_digest
             )

    assert {:ok, %{"fixture" => true, "verifier" => true, "produced_by" => producer}} =
             artifacts |> Path.join("integrity.json") |> File.read!() |> JSON.decode()

    assert producer == "kinda-capsule-trusted-task@0.1.0"
  end

  defp sha256(value) do
    value |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end
end
