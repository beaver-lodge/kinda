defmodule Kinda.Capsule.Web3DTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule.Spec
  alias Kinda.Capsule.Web3D
  alias Kinda.Capsule.Web3D.Verifier

  @tag :tmp_dir
  test "builds a versioned Capsule spec for a fresh sandbox", %{tmp_dir: parent} do
    spec = Web3D.spec(parent_directory: parent)

    assert :ok = Spec.validate(spec)
    assert spec.fixture_digest == Web3D.digest_tree(Web3D.fixture_root())
    assert spec.verifier_digest == Verifier.digest()
    assert spec.runtime.viewport == %{width: 1440, height: 900}
  end
end
