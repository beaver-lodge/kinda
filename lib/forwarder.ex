defmodule Kinda.Forwarder do
  @callback forward() :: :ok | :error
  @callback check!() :: :ok | :error
  @callback array() :: :ok | :error
  @callback to_term() :: :ok | :error
  @callback opaque_ptr() :: :ok | :error
end
