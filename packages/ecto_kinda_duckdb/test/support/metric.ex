defmodule EctoKindaDuckDB.Metric do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "metrics" do
    field :category, :string
    field :value, :integer
  end
end
