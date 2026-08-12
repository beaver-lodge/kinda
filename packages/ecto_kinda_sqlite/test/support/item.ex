defmodule EctoKindaSQLite.Item do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "items" do
    field :active, :boolean, default: true
    field :name, :string
    field :payload, :binary
    field :quantity, :integer, default: 0
    timestamps()
  end

  def changeset(item, attributes) do
    item
    |> cast(attributes, [:active, :name, :payload, :quantity])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
