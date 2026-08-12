defmodule Kinda.QuickJS.Native do
  @moduledoc false
  @on_load :load_nif

  def version, do: :erlang.nif_error({:nif_not_loaded, :version})
  def eval(_code), do: :erlang.nif_error({:nif_not_loaded, :eval})

  def create_runtime(_memory_limit, _stack_limit),
    do: :erlang.nif_error({:nif_not_loaded, :create_runtime})

  def close_runtime(_runtime), do: :erlang.nif_error({:nif_not_loaded, :close_runtime})
  def runtime_stats(_runtime), do: :erlang.nif_error({:nif_not_loaded, :runtime_stats})
  def create_context(_runtime), do: :erlang.nif_error({:nif_not_loaded, :create_context})

  def eval_context(_context, _code, _interrupt_budget),
    do: :erlang.nif_error({:nif_not_loaded, :eval_context})

  def close_context(_context), do: :erlang.nif_error({:nif_not_loaded, :close_context})
  def create_value(_context, _code), do: :erlang.nif_error({:nif_not_loaded, :create_value})
  def export_value(_value), do: :erlang.nif_error({:nif_not_loaded, :export_value})
  def promise_state(_value), do: :erlang.nif_error({:nif_not_loaded, :promise_state})
  def promise_result(_value), do: :erlang.nif_error({:nif_not_loaded, :promise_result})
  def run_jobs(_runtime, _limit), do: :erlang.nif_error({:nif_not_loaded, :run_jobs})
  def close_value(_value), do: :erlang.nif_error({:nif_not_loaded, :close_value})

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_quickjs)}/lib/libKindaQuickJSNIF"
    dylib = "#{nif_file}.dylib"
    if File.exists?(dylib), do: File.ln_s(dylib, "#{nif_file}.so")

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _message}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
