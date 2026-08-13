const std = @import("std");

pub fn build(b: *std.Build) !void {
    const erlang_include_path = b.graph.environ_map.get("ERTS_INCLUDE_DIR") orelse blk: {
        const argv = [_][]const u8{
            "erl",
            "-eval",
            "io:format(\"~s\", [lists:concat([code:root_dir(), \"/erts-\", erlang:system_info(version), \"/include\"])])",
            "-s",
            "init",
            "stop",
            "-noshell",
        };
        break :blk b.run(&argv);
    };

    const kinda = b.addModule(
        "kinda",
        .{
            .root_source_file = b.path("src/kinda.zig"),
            .link_libc = true,
        },
    );
    kinda.addIncludePath(.{ .cwd_relative = erlang_include_path });

    const contract_tests = b.step(
        "test-contracts",
        "Verify compile-time API contract diagnostics",
    );
    const fixtures = [_]struct {
        path: []const u8,
        diagnostic: []const u8,
    }{
        .{
            .path = "test/compile_fail/entry_exports_missing_field.zig",
            .diagnostic = "Kinda.EntryExports spec is missing required field .name",
        },
        .{
            .path = "test/compile_fail/entry_exports_invalid_nif.zig",
            .diagnostic = "Kinda.EntryExports .nifs must contain ErlNifFunc values",
        },
        .{
            .path = "test/compile_fail/dynamic_entry_exports_missing_field.zig",
            .diagnostic = "Kinda.DynamicEntryExports spec is missing required field .nifs_provider",
        },
        .{
            .path = "test/compile_fail/dynamic_entry_exports_invalid_provider.zig",
            .diagnostic = "Kinda.DynamicEntryExports .nifs_provider must be fn() []ErlNifFunc",
        },
        .{
            .path = "test/compile_fail/resource_registry_invalid_entry.zig",
            .diagnostic = "resource registry entries must be Kinda.ResourceRegistration values",
        },
        .{
            .path = "test/compile_fail/resource_registry_invalid_kind.zig",
            .diagnostic = "resource registry kind must be created by Kinda.ResourceKind",
        },
        .{
            .path = "test/compile_fail/deferred_close_missing_contract_field.zig",
            .diagnostic = "deferred-close contract for",
        },
        .{
            .path = "test/compile_fail/deferred_close_invalid_counter.zig",
            .diagnostic = "must be std.atomic.Value(usize)",
        },
        .{
            .path = "test/compile_fail/deferred_close_invalid_method.zig",
            .diagnostic = "must accept *",
        },
        .{
            .path = "test/compile_fail/result_invalid_nif_function.zig",
            .diagnostic = "Kinda.result.nif function must accept (beam.env, c_int, [*c]const beam.term)",
        },
        .{
            .path = "test/compile_fail/resource_destructor_invalid_arity.zig",
            .diagnostic = "resourceDestructor close must be fn(*",
        },
        .{
            .path = "test/compile_fail/resource_destructor_invalid_parameter.zig",
            .diagnostic = "resourceDestructor close must be fn(*",
        },
        .{
            .path = "test/compile_fail/resource_destructor_invalid_return.zig",
            .diagnostic = "resourceDestructor close must be fn(*",
        },
    };

    inline for (fixtures) |fixture| {
        const compile = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "build-obj",
            "-fno-emit-bin",
            "-lc",
            "--dep",
            "kinda",
        });
        compile.addPrefixedFileArg("-Mroot=", b.path(fixture.path));
        compile.addArg("-I");
        compile.addArg(erlang_include_path);
        compile.addPrefixedFileArg("-Mkinda=", b.path("src/kinda.zig"));
        compile.expectExitCode(1);
        compile.expectStdErrMatch(fixture.diagnostic);
        contract_tests.dependOn(&compile.step);
    }
}
