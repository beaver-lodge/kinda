#!/bin/bash
set -e

ROOT_DIR=$(elixir --eval ":code.root_dir() |> IO.puts()")
VERSION=$(elixir --eval ":erlang.system_info(:version) |> IO.puts()")
export BINDIR=$ROOT_DIR/erts-$VERSION/bin
EXE=$BINDIR/erlexec

echo "ROOT_DIR: $ROOT_DIR"
echo "VERSION: $VERSION"
echo "EXE: $EXE"

FULL=$(ELIXIR_CLI_DRY_RUN=1 mix "$@")
FULL=${FULL/erl/${EXE}}
echo "FULL: $FULL"

# Run under GDB with automated backtrace
gdb -ex "run" -ex "bt" -ex "quit" --args $FULL
