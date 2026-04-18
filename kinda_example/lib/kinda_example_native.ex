defmodule KindaExample.Native do
  use Kinda.Forwarder, nif_module: KindaExample.NIF
end
