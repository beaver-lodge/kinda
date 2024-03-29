# Kinda

Kinda is an Elixir package using Zig to bind a C library to BEAM the Erlang virtual machine.
The core idea here is using comptime features in Zig to create a "resource kind" which is "higher-kinded" type abstracts the NIF resource object, C type and Elixir module.

The general source code generating and building approach here is highly inspired by the TableGen/.inc in LLVM.
Kinda will generate NIFs exported by resource kinds and and provide Elixir macros to generate higher level API to call them and create resource.
With Kinda, NIFs generated and hand-rolled co-exist and complement each other.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `Kinda` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:kinda, "~> 0.7.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/Kinda>.

## Usage

A full example could be found in [kinda_example](kinda_example)

### More examples

- define a root module for the C library

  ```elixir
  defmodule Foo.CAPI do
    use Kinda.Library, kinds: [Foo.BarKind]
  end
  ```

- define a forwarder module
  ```elixir
  defmodule Foo.Native do
    use Kinda.Forwarder, root_module: CAPI
  end
  ```
- define kinds
  ```elixir
  defmodule Foo.BarKind do
    use Kinda.ResourceKind,
      forward_module: Foo.Native
  end
  ```

## What Kinda does

- Make NIF more of a purely function dispatch. So that you can break the complicity among C/Zig and Elixir.
- Make it possible to pattern matching a C type in Elixir.
- Everything in Kinda could be a NIF resource, including primitive types like integer and C struct. This makes it possible to pass them to C functions as pointers.
- Kinda will generate a NIF function for every C function in your wrapper header, and register every C struct as NIF resource.

## Cool features in Kinda enabled by Zig

- Packing anything into a resource

  Almost all C++/Rust implementation seems to force you to map a fixed size type to a resource type.
  In fact for same resource type, you can have Erlang allocate memory of any size.
  With Zig's comptime `sizeof` you can easily pack a list of items into an array/struct without adding any abstraction and overhead. An illustration:

  ```
    [(address to item1), item1, item2, item3, ...]
  ```

  So the memory is totally managed by Erlang, and you can use Zig's comptime feature to infer everything involved.

- Saving lib/include path to a Zig source and use them in your `build.zig`. You can use Elixir to find all the paths. It is way better than configuring with make/CMake because you are using Elixir a whole programming language to do it. It is described in Zig doc as:

  > Surfacing build configuration as comptime values by providing a file that can be imported by Zig code.

- Inter NIF resource exchange. Because it is Zig, just import the Zig source from another Hex package.

## Differences from Zigler

Kinda borrows a lot of good ideas and code from Zigler (Zigler is awesome~) but there are some differences:

- Kinda's primary goal is to help you consume a C library, not helping you write NIFs in Zig.
- Kinda expects you to have a `build.zig`. So if you want to also sneak CMake/Bazel inside, go for it.
- In functions generated by Kinda, all memory are allocated and managed by Erlang as resource.

## Differences from Rustler

Kinda is also inspired by Rustler. Rustler really define what a ergonomic NIF lib should be like.

- Kinda should have the sugar for resource open and NIF declaration similar to Rustler but are provided in Elixir (`nif_gen` and `type_gen`).
- Due to the absence of official Zig package indexing, as for now Kinda's approach could be more of a monolithic NIF lib while in Rustler, you can break things into different crates which is really nice.
- The only protection Kinda might provide is the resource type checks. Lifetime and other more sophisticated checks are expected to be provided by the C library you are consuming.

## Differences from TableGen

- Usually TableGen generates C/C++ source code. While in Kinda it is expected to generate Elixir AST and get compiled directly.
- To generate Zig code, Kinda takes in C `.h` files instead of `.td` files.

## Core concepts

- `ResourceKind`: a Zig struct to bundle:

  - C types
  - Erlang NIF resource object type
  - functions to open/fetch/make a resource object.
  - there could be higher order `ResourceKind` to bundle one or more different `ResourceKind`s

- `root_module`: the NIF module will load the C shared library
- `forward_module`: module implement functions like `array/2`, `ptr/1` to forward functions to `root_module`. By implementing different callbacks, you might choose to use Elixir struct to wrap a resource or use it directly.
- Recommended module mapping convention:

  - let's say you have a Elixir module to manage a C type. And the NIF module is `SomeLib.CAPI`

    ```elixir
    defmodule SomeLib.I64 do
      defstruct ref: nil
      def create() do
        ref = apply(SomeLib.CAPI, Module.concat([__MODULE__, :create]) |> Kinda.check!
        struct!(__MODULE__, %{ref: ref})
      end
    end
    ```

  - in `SomeLib.CAPI` there should be a NIF generated by Kinda with name `:"Elixir.SomeLib.I64.create"/0`

- wrapper: a `.h` C header file including all the C types and functions you want to use in Elixir. Kinda will generate a NIF module for every wrapper file.
- wrapped functions, C function with corresponding NIF function name, will be called in the NIF module.
- kinds to generate: return type and argument types of every functions in wrapper will be generated. User will need to implement the behavior `Kinda.CodeGen` for a type with a special name (usually it is C function pointer), or it is the type name in C source by default.
- raw nifs: nifs doesn't follow involved in the resource kind naming convention. Insides these NIFs it is recommended to use NIF resource types registered by Kinda.

## Internals

### Source code generation

1. calling Zig's `translation-c` to generate Zig source code from wrapper header
2. parse Zig source into ast and then:

- collect C types declared as constants in Zig (mainly structs), generate kinds for them
- generate kinds for primitive types like int, float, etc.
- generate pointer/array kinds for all types

3. generate NIF source for every C function in the wrapper header
4. generate kind source for every C type used in C functions

## Pre-built mode

- Out of the box Kinda supports generating and loading pre-built NIF library.

  ```elixir
    use Kinda.Prebuilt,
      otp_app: :beaver,
      base_url: "[URL]",
      version: "[VERSION]"
  ```

- It reuses code in [rustler_precompiled](https://github.com/philss/rustler_precompiled.git) to follow the same convention of checksum checks and OTP compatibility rules.
- In Kinda, besides the main NIF library, there might be `kinda-meta-*.ex` for functions signatures and multiple shared libraries the main NIF library depends on. (Zig doesn't support static linking yet so we have to ship shared ones. [Related issue](https://github.com/ziglang/zig/issues/9053))

## Release

- run the example

```
cd kinda_example
mix deps.get
mix test --force
mix compile --force
```
