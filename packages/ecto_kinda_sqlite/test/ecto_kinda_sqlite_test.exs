defmodule EctoKindaSQLiteTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias EctoKindaSQLite.{Item, TestRepo}

  setup do
    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "runs Repo queries and schema CRUD" do
    assert %{rows: [[1]]} = TestRepo.query!("select ?", [1])

    assert {:ok, item} =
             %Item{}
             |> Item.changeset(%{
               name: "first",
               quantity: 2,
               active: true,
               payload: <<0, 1, 2>>
             })
             |> TestRepo.insert()

    assert %Item{name: "first", payload: <<0, 1, 2>>, quantity: 2} = TestRepo.get!(Item, item.id)

    assert {:ok, updated} =
             item
             |> Item.changeset(%{quantity: 3})
             |> TestRepo.update()

    assert updated.quantity == 3
    assert {:ok, _deleted} = TestRepo.delete(updated)
    refute TestRepo.get(Item, item.id)
  end

  test "supports insert_all and Ecto query updates" do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    assert {2, nil} =
             TestRepo.insert_all(Item, [
               %{name: "one", quantity: 1, inserted_at: now, updated_at: now},
               %{name: "two", quantity: 2, inserted_at: now, updated_at: now}
             ])

    assert {2, nil} = TestRepo.update_all(from(item in Item), inc: [quantity: 10])

    assert TestRepo.all(from(item in Item, order_by: item.name, select: item.quantity)) == [
             11,
             12
           ]
  end

  test "commits, rolls back, and supports SQLite savepoints" do
    assert {:ok, :committed} =
             TestRepo.transaction(fn ->
               TestRepo.insert!(%Item{name: "committed"})
               :committed
             end)

    assert TestRepo.get_by(Item, name: "committed")

    assert {:error, :rolled_back} =
             TestRepo.transaction(fn ->
               TestRepo.insert!(%Item{name: "rolled-back"})
               TestRepo.rollback(:rolled_back)
             end)

    assert TestRepo.get_by(Item, name: "committed")
    refute TestRepo.get_by(Item, name: "rolled-back")

    assert {:ok, :saved} =
             TestRepo.transaction(fn ->
               TestRepo.insert!(%Item{name: "before-savepoint"})
               TestRepo.query!("SAVEPOINT ecto_kinda_nested")
               TestRepo.insert!(%Item{name: "inside-savepoint"})
               TestRepo.query!("ROLLBACK TO SAVEPOINT ecto_kinda_nested")
               TestRepo.query!("RELEASE SAVEPOINT ecto_kinda_nested")
               :saved
             end)

    assert TestRepo.get_by(Item, name: "before-savepoint")
    refute TestRepo.get_by(Item, name: "inside-savepoint")
  end

  test "streams bounded batches inside a transaction" do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    TestRepo.insert_all(
      Item,
      Enum.map(1..5, &%{name: "item-#{&1}", quantity: &1, inserted_at: now, updated_at: now})
    )

    assert {:ok, [1, 2, 3, 4, 5]} =
             TestRepo.transaction(fn ->
               Item
               |> order_by([item], item.quantity)
               |> select([item], item.quantity)
               |> TestRepo.stream(max_rows: 2)
               |> Enum.to_list()
             end)
  end

  test "maps unique constraints into changeset errors" do
    TestRepo.insert!(%Item{name: "duplicate"})

    assert {:error, changeset} =
             %Item{}
             |> Item.changeset(%{name: "duplicate"})
             |> TestRepo.insert()

    assert {"has already been taken", _metadata} = changeset.errors[:name]
  end

  test "enforces foreign keys created by migrations" do
    assert_raise Kinda.SQLite.Error, ~r/FOREIGN KEY constraint failed/, fn ->
      TestRepo.query!("insert into children(parent_id) values (?)", [-1])
    end
  end

  test "allows an owned Sandbox connection to be shared with a child process" do
    TestRepo.insert!(%Item{name: "shared"})

    parent = self()

    task =
      Task.async(fn ->
        send(parent, {:sandbox_child, self()})
        receive do: (:query -> TestRepo.get_by!(Item, name: "shared").name)
      end)

    assert_receive {:sandbox_child, child}
    :ok = Sandbox.allow(TestRepo, self(), child)
    send(child, :query)

    assert Task.await(task) == "shared"
  end
end
