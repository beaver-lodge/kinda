defmodule EctoKindaDuckDB.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :ecto_kinda_duckdb,
    adapter: Ecto.Adapters.KindaDuckDB
end
