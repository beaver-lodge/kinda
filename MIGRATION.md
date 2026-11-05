# Core API cleanup for 0.12.0-dev

The core now contains 3,000 code lines, down from 5,211 (42.4%). The scope is
still all of `lib/` and `src/`; implementations have not been moved into tests,
examples, or packages to meet the limit. Count nonblank, noncomment lines with:

```sh
cloc lib src --skip-uniqueness --quiet
```

The reduction combines shared numeric conversion, resource storage, NIF entry
setup, declaration generation, and manifest serialization with removal of
unused helpers. Core Elixir formatting uses a 120-column limit. Native callback
completion uses Zig's mutex/event primitives, preserving single completion,
caller handoff, library pinning, bounded deadlines, and unbounded waits. Fixed
size result tuples use stack storage instead of temporary allocations.

Beaver and the bundled packages retain their consumed interfaces. Projects
using the auxiliary interfaces below must migrate before updating.

## Elixir

| Removed interface | Replacement |
| --- | --- |
| `Kinda.CodeGen.KindDecl.default/2`, `primitive_types/0`, `is_primitive_type?/1`, `is_opaque_ptr?/1`, `gen_resource_kind/1` | Construct `%KindDecl{module_name: module, kind_functions: functions}` explicitly. Native code owns Zig type declarations. The unused `kind_name`, `zig_t`, and `fields` struct fields are also removed. |
| `Kinda.CodeGen.nif_ast/4` | Normalize with `nif_decls/3`, then call `nif_ast_from_decls/3`, or use `Kinda.CodeGen`. |
| `Kinda.CodeGen.type_decls/1`, `declaration_manifest/2,3`, `record_types_ast/1` | Use `DeclarationManifest.build/1,2`, `from_parts/2,3`, `type_decls/1`, and `CodeGen.type_decls_ast/1`. |
| `DeclarationManifest.put_signature_manifest/2`, `put_nif_decls/2`, `put_type_decls/2`, `merge_nif_decls/2`, `signature_manifest_version/1` | Construct manifests with `build`/`from_parts`, or update/read their public struct fields. `Declaration.from_generator/2` still normalizes and deduplicates generated resource declarations. |
| `Wrapper.Generate.elixir_functions/2` | Read `wrapper_name` and `params` from `elixir_nif_decls/2`. |
| `Wrapper.Generate.zig_entries/2`, `render_zig_nif_entries/2`, and `Wrapper.Policy.zig_entry/1` | Consumers assemble their own native entry tables; generation retains the canonical declaration and signature manifests. |
| All `Wrapper.Generate.write_*` helpers | Obtain data with the corresponding retained render/manifest functions and write it with the consumer's file handling. |
| `Wrapper.Policy.unsupported_entries/0`, `unsupported?/1`, `unsupported_reason/1` callbacks and `unsupported_reason/0` type | Use the `generation_blocker_*` callbacks. |
| `Wrapper.Generate` JSON manifest type aliases | Public function specs now use maps and the actual declaration struct types. |
| `Kinda.ExampleVerifier.sync_deps/3` | `verify/0,1` continues to fetch package dependencies before running tests. |
| `Kinda.Testing.NIFUpgrade.run!/5` | Use `Kinda.Testing.NativeScenario` upgrade steps; low-level copy/load/restore helpers remain. |

## Zig

The following unused `kinda.beam` declarations are removed:

```text
large_allocator general_purpose_allocator ThreadError test_env
blank_load blank_upgrade
get_c_string get_pid send get_tuple get_slice_of get_slice_of_alloc
make_c_string make_charlist make_c_string_charlist make_charlist_len
make_list make_list_alloc make_c_int_list make_c_long_list
make_i32_list make_i64_list make_f16_list make_f32_list make_f64_list
make_ok_tuple make_ok_atom make_error_tuple make_ref
raise raise_enomem raise_function_clause_error raise_resource_error
raise_assertion_error make_exception raise_exception is_nil
fetch_resource_wrapped fetch_ptr_resource_wrapped make_resource_wrapped
make_ptr_resource_wrapped open_resource_wrapped
```

Use `beam.allocator` for its supported alignments and current Zig allocators
for other allocation requirements. The retained length-aware binary helpers,
`make_term_list`, `make_tuple`, numeric `get`/`make`, and `kinda.nifApi` cover
conversion and direct ERTS access. `is_nil2` performs a nonallocating term
comparison. Use `RawResourceType` or `ResourceKind.resource` for resource
handling, and `raise_call_error` for structured NIF diagnostics.

`kinda.OpaqueField`, `kinda.ResourceKind2`, and `kinda.result.wrap` are also
removed. Use explicit `ResourceKind(T, module_name)` declarations and
`result.nif`/`nif_with_flags` entries. `Internal.OpaqueStruct` and the native
resource slot names consumed by Beaver are retained.
