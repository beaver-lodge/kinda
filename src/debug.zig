const std = @import("std");
const builtin = @import("builtin");
const beam = @import("beam.zig");
const SelfInfo = std.debug.SelfInfo;

var self_debug_info: ?SelfInfo = null;

fn formatEmptyTraceItem(writer: anytype) !void {
    try writer.writeAll("<unknown>");
}

fn formatTraceItem(writer: anytype, debug_info: *SelfInfo, address: usize) !void {
    const module = debug_info.getModuleForAddress(address) catch {
        try formatEmptyTraceItem(writer);
        return;
    };

    const symbol_info = module.getSymbolAtAddress(beam.allocator, address) catch {
        try formatEmptyTraceItem(writer);
        return;
    };

    if (symbol_info.source_location) |loc| {
        try writer.print("{s}:{d}:{d}", .{
            loc.file_name,
            loc.line,
            loc.column,
        });
    } else {
        try writer.writeAll("<unknown>");
    }

    try writer.print(" ({s})", .{symbol_info.name});
    try writer.print(" [{s}]", .{symbol_info.compile_unit_name});
}

pub fn formatStackTrace(
    writer: anytype,
    stacktrace: std.builtin.StackTrace,
    debug_info: *SelfInfo,
    indent: []const u8,
) !void {
    if (builtin.strip_debug_info) {
        try writer.writeAll("<debug info stripped>\n");
        return;
    }

    var frame_index: usize = 0;
    var frames_left: usize = @min(stacktrace.index, stacktrace.instruction_addresses.len);

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stacktrace.instruction_addresses.len;
    }) {
        try writer.writeAll(indent);
        try writer.print("#{d} ", .{frames_left});

        const return_address = stacktrace.instruction_addresses[frame_index];
        try formatTraceItem(writer, debug_info, return_address -| 1);

        try writer.writeAll("\n");
    }
}
