defmodule EctoKindaSQLite.Migration do
  @moduledoc false

  use Ecto.Migration

  def change do
    create table(:items) do
      add :active, :boolean, null: false, default: true
      add :name, :string, null: false
      add :payload, :binary
      add :quantity, :integer, null: false, default: 0
      timestamps()
    end

    create unique_index(:items, [:name])

    create table(:parents) do
      add :name, :string, null: false
    end

    create table(:children) do
      add :parent_id, references(:parents, on_delete: :delete_all), null: false
    end
  end
end
