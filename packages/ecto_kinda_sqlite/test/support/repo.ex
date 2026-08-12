defmodule EctoKindaSQLite.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :ecto_kinda_sqlite,
    adapter: Ecto.Adapters.KindaSQLite
end
