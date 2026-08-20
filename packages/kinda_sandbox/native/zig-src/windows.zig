const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
});

const allocator = std.heap.c_allocator;
const read_chunk_size = 64 * 1024;

pub const Process = struct {
    mutex: std.atomic.Mutex = .unlocked,
    process_handle: ?c.HANDLE,
    job_handle: ?c.HANDLE,
    process_id: c.DWORD,
    stdout_handle: ?c.HANDLE,
    stderr_handle: ?c.HANDLE,
    writer: ?std.Thread,
    term: ?Term = null,
    terminal_emitted: bool = false,
};

const Term = union(enum) {
    exit: u32,
    signal: u8,
};

const WriterContext = struct {
    handle: c.HANDLE,
    input: []u8,

    fn run(context: *WriterContext) void {
        defer {
            _ = c.CloseHandle(context.handle);
            allocator.free(context.input);
            allocator.destroy(context);
        }

        var offset: usize = 0;
        while (offset < context.input.len) {
            var written: c.DWORD = 0;
            const amount: c.DWORD = @intCast(@min(context.input.len - offset, 64 * 1024));
            if (c.WriteFile(context.handle, context.input.ptr + offset, amount, &written, null) == 0) return;
            if (written == 0) return;
            offset += written;
        }
    }
};

pub fn spawn(environment: beam.env, args: [*c]const beam.term) !Process {
    const executable = try beam.get_char_slice(environment, args[0]);
    const cwd = try beam.get_char_slice(environment, args[2]);
    const input_value = try beam.get_char_slice(environment, args[4]);
    const command_line = try buildCommandLine(environment, executable, args[1]);
    defer allocator.free(command_line);
    const cwd_wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cwd);
    defer allocator.free(cwd_wide);
    const environment_block = try buildEnvironmentBlock(environment, args[3]);
    defer allocator.free(environment_block);

    var security = std.mem.zeroes(c.SECURITY_ATTRIBUTES);
    security.nLength = @sizeOf(c.SECURITY_ATTRIBUTES);
    security.bInheritHandle = c.TRUE;

    var stdin_read: c.HANDLE = undefined;
    var stdin_write: c.HANDLE = undefined;
    var stdout_read: c.HANDLE = undefined;
    var stdout_write: c.HANDLE = undefined;
    var stderr_read: c.HANDLE = undefined;
    var stderr_write: c.HANDLE = undefined;
    try createPipe(&stdin_read, &stdin_write, &security);
    errdefer closeHandle(stdin_read);
    errdefer closeHandle(stdin_write);
    try createPipe(&stdout_read, &stdout_write, &security);
    errdefer closeHandle(stdout_read);
    errdefer closeHandle(stdout_write);
    try createPipe(&stderr_read, &stderr_write, &security);
    errdefer closeHandle(stderr_read);
    errdefer closeHandle(stderr_write);

    if (c.SetHandleInformation(stdin_write, c.HANDLE_FLAG_INHERIT, 0) == 0 or
        c.SetHandleInformation(stdout_read, c.HANDLE_FLAG_INHERIT, 0) == 0 or
        c.SetHandleInformation(stderr_read, c.HANDLE_FLAG_INHERIT, 0) == 0)
    {
        return error.SetHandleInformationFailed;
    }

    const job = c.CreateJobObjectW(null, null) orelse return error.CreateJobFailed;
    errdefer closeHandle(job);
    var limits = std.mem.zeroes(c.JOBOBJECT_EXTENDED_LIMIT_INFORMATION);
    limits.BasicLimitInformation.LimitFlags = c.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (c.SetInformationJobObject(job, c.JobObjectExtendedLimitInformation, &limits, @sizeOf(@TypeOf(limits))) == 0) {
        return error.ConfigureJobFailed;
    }

    var startup = std.mem.zeroes(c.STARTUPINFOW);
    startup.cb = @sizeOf(c.STARTUPINFOW);
    startup.dwFlags = c.STARTF_USESTDHANDLES;
    startup.hStdInput = stdin_read;
    startup.hStdOutput = stdout_write;
    startup.hStdError = stderr_write;
    var process_info = std.mem.zeroes(c.PROCESS_INFORMATION);

    const creation_flags = c.CREATE_SUSPENDED | c.CREATE_UNICODE_ENVIRONMENT | c.CREATE_NO_WINDOW | c.CREATE_NEW_PROCESS_GROUP;
    if (c.CreateProcessW(
        null,
        command_line.ptr,
        null,
        null,
        c.TRUE,
        creation_flags,
        environment_block.ptr,
        cwd_wide.ptr,
        &startup,
        &process_info,
    ) == 0) return error.CreateProcessFailed;
    errdefer {
        _ = c.TerminateProcess(process_info.hProcess, 1);
        closeHandle(process_info.hThread);
        closeHandle(process_info.hProcess);
    }

    closeHandle(stdin_read);
    closeHandle(stdout_write);
    closeHandle(stderr_write);
    if (c.AssignProcessToJobObject(job, process_info.hProcess) == 0) return error.AssignJobFailed;
    if (c.ResumeThread(process_info.hThread) == std.math.maxInt(c.DWORD)) return error.ResumeProcessFailed;
    closeHandle(process_info.hThread);

    var writer: ?std.Thread = null;
    if (input_value.len == 0) {
        closeHandle(stdin_write);
    } else {
        const context = try allocator.create(WriterContext);
        errdefer allocator.destroy(context);
        context.* = .{ .handle = stdin_write, .input = try allocator.dupe(u8, input_value) };
        errdefer allocator.free(context.input);
        writer = try std.Thread.spawn(.{}, WriterContext.run, .{context});
    }

    return .{
        .process_handle = process_info.hProcess,
        .job_handle = job,
        .process_id = process_info.dwProcessId,
        .stdout_handle = stdout_read,
        .stderr_handle = stderr_read,
        .writer = writer,
    };
}

pub fn readEvent(environment: beam.env, process: *Process) beam.term {
    lock(&process.mutex);
    defer process.mutex.unlock();

    if (process.terminal_emitted) return beam.make_atom(environment, "done");
    if (readStream(environment, &process.stdout_handle, "stdout")) |event| return event;
    if (readStream(environment, &process.stderr_handle, "stderr")) |event| return event;
    observeTermination(process);

    if (process.term) |term| {
        if (process.stdout_handle == null and process.stderr_handle == null) {
            joinWriter(process);
            closeOptionalHandle(&process.process_handle);
            closeOptionalHandle(&process.job_handle);
            process.terminal_emitted = true;
            return terminalEvent(environment, term);
        }
    }

    c.Sleep(20);
    return beam.make_atom(environment, "idle");
}

pub fn terminate(process: *Process, _: u32) void {
    lock(&process.mutex);
    defer process.mutex.unlock();
    const process_handle = process.process_handle orelse return;
    const job_handle = process.job_handle orelse return;
    observeTermination(process);

    // CREATE_NO_WINDOW processes have no console to receive CTRL_BREAK_EVENT.
    // Terminating the job is the only reliable way to stop the full tree.
    _ = c.TerminateJobObject(job_handle, 1);
    _ = c.WaitForSingleObject(process_handle, c.INFINITE);
    observeTermination(process);
}

pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
    const process: *Process = @ptrCast(@alignCast(object orelse return));
    terminate(process, 0);
    joinWriter(process);
    closeOptionalHandle(&process.stdout_handle);
    closeOptionalHandle(&process.stderr_handle);
    closeOptionalHandle(&process.process_handle);
    closeOptionalHandle(&process.job_handle);
}

fn createPipe(read_handle: *c.HANDLE, write_handle: *c.HANDLE, security: *c.SECURITY_ATTRIBUTES) !void {
    if (c.CreatePipe(read_handle, write_handle, security, 0) == 0) return error.CreatePipeFailed;
}

fn readStream(environment: beam.env, handle: *?c.HANDLE, comptime name: []const u8) ?beam.term {
    const value = handle.* orelse return null;
    var available: c.DWORD = 0;
    if (c.PeekNamedPipe(value, null, 0, null, &available, null) == 0) {
        closeOptionalHandle(handle);
        return null;
    }
    if (available == 0) return null;

    var buffer: [read_chunk_size]u8 = undefined;
    var bytes_read: c.DWORD = 0;
    const amount: c.DWORD = @intCast(@min(available, buffer.len));
    if (c.ReadFile(value, &buffer, amount, &bytes_read, null) == 0 or bytes_read == 0) {
        closeOptionalHandle(handle);
        return null;
    }
    var tuple = [_]beam.term{
        beam.make_atom(environment, name),
        beam.make_slice(environment, buffer[0..bytes_read]),
    };
    return beam.make_tuple(environment, &tuple);
}

fn observeTermination(process: *Process) void {
    if (process.term != null) return;
    const process_handle = process.process_handle orelse return;
    if (c.WaitForSingleObject(process_handle, 0) != c.WAIT_OBJECT_0) return;
    var exit_code: c.DWORD = 1;
    if (c.GetExitCodeProcess(process_handle, &exit_code) == 0) {
        process.term = .{ .signal = 0 };
    } else {
        process.term = .{ .exit = exit_code };
    }
}

fn terminalEvent(environment: beam.env, term: Term) beam.term {
    var tuple: [2]beam.term = undefined;
    switch (term) {
        .exit => |status| {
            tuple[0] = beam.make_atom(environment, "exit");
            tuple[1] = beam.make_u32(environment, status);
        },
        .signal => |signal| {
            tuple[0] = beam.make_atom(environment, "signal");
            tuple[1] = beam.make_u8(environment, signal);
        },
    }
    return beam.make_tuple(environment, &tuple);
}

fn buildCommandLine(environment: beam.env, executable: []const u8, list_term: beam.term) ![:0]u16 {
    const argument_count = try beam.get_list_length(environment, list_term);
    var arguments = try allocator.alloc([]const u8, argument_count + 1);
    defer allocator.free(arguments);
    arguments[0] = executable;
    var list = list_term;
    for (arguments[1..]) |*argument| {
        argument.* = try beam.get_char_slice(environment, try beam.get_head_and_iter(environment, &list));
    }

    var capacity: usize = 1;
    for (arguments) |argument| capacity += argument.len * 2 + 3;
    const output = try allocator.allocSentinel(u16, capacity - 1, 0);
    var index: usize = 0;
    for (arguments, 0..) |argument, argument_index| {
        if (argument_index != 0) appendUnit(output, &index, ' ');
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, argument);
        defer allocator.free(wide);
        appendQuotedArgument(output, &index, wide[0..wide.len]);
    }
    output[index] = 0;
    return output[0..index :0];
}

fn appendQuotedArgument(output: []u16, index: *usize, argument: []const u16) void {
    const quote = argument.len == 0 or for (argument) |unit| {
        if (unit == ' ' or unit == '\t' or unit == '"') break true;
    } else false;
    if (!quote) {
        for (argument) |unit| appendUnit(output, index, unit);
        return;
    }

    appendUnit(output, index, '"');
    var backslashes: usize = 0;
    for (argument) |unit| {
        if (unit == '\\') {
            backslashes += 1;
        } else if (unit == '"') {
            appendBackslashes(output, index, backslashes * 2 + 1);
            appendUnit(output, index, '"');
            backslashes = 0;
        } else {
            appendBackslashes(output, index, backslashes);
            backslashes = 0;
            appendUnit(output, index, unit);
        }
    }
    appendBackslashes(output, index, backslashes * 2);
    appendUnit(output, index, '"');
}

fn buildEnvironmentBlock(environment: beam.env, list_term: beam.term) ![:0]u16 {
    const count = try beam.get_list_length(environment, list_term);
    var list = list_term;
    var entries = try allocator.alloc([:0]u16, count);
    defer allocator.free(entries);
    var initialized: usize = 0;
    defer for (entries[0..initialized]) |entry| allocator.free(entry);
    var total: usize = 1;
    for (entries) |*entry| {
        const value = try beam.get_char_slice(environment, try beam.get_head_and_iter(environment, &list));
        entry.* = try std.unicode.utf8ToUtf16LeAllocZ(allocator, value);
        initialized += 1;
        total += entry.len + 1;
    }

    const block = try allocator.allocSentinel(u16, total, 0);
    var index: usize = 0;
    for (entries) |entry| {
        @memcpy(block[index .. index + entry.len + 1], entry[0 .. entry.len + 1]);
        index += entry.len + 1;
    }
    block[index] = 0;
    return block;
}

fn appendBackslashes(output: []u16, index: *usize, count: usize) void {
    for (0..count) |_| appendUnit(output, index, '\\');
}

fn appendUnit(output: []u16, index: *usize, unit: u16) void {
    output[index.*] = unit;
    index.* += 1;
}

fn joinWriter(process: *Process) void {
    if (process.writer) |writer| {
        writer.join();
        process.writer = null;
    }
}

fn closeOptionalHandle(handle: *?c.HANDLE) void {
    if (handle.*) |value| {
        closeHandle(value);
        handle.* = null;
    }
}

fn closeHandle(handle: c.HANDLE) void {
    _ = c.CloseHandle(handle);
}

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}
