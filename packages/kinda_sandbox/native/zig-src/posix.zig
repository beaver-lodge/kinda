const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("poll.h");
    @cInclude("signal.h");
    @cInclude("stdint.h");
    @cInclude("stdlib.h");
    @cInclude("sys/types.h");
    @cInclude("sys/wait.h");
    @cInclude("unistd.h");
});

const allocator = std.heap.c_allocator;
const closed_fd: c_int = -1;
const read_chunk_size = 64 * 1024;

pub const Process = struct {
    mutex: std.atomic.Mutex = .unlocked,
    pid: c.pid_t,
    stdin_fd: c_int,
    stdout_fd: c_int,
    stderr_fd: c_int,
    status_fd: c_int,
    stdin: []u8,
    stdin_offset: usize = 0,
    term: ?Term = null,
    terminal_emitted: bool = false,
};

const Term = union(enum) {
    exit: u8,
    signal: u8,
};

pub fn spawn(environment: beam.env, args: [*c]const beam.term) !Process {
    const executable = try duplicateString(environment, args[0]);
    defer allocator.free(executable);
    const command_args = try duplicateStringList(environment, args[1]);
    defer freeStrings(command_args);
    const cwd = try duplicateString(environment, args[2]);
    defer allocator.free(cwd);
    const environment_entries = try duplicateStringList(environment, args[3]);
    defer freeStrings(environment_entries);
    const input = try duplicateString(environment, args[4]);
    errdefer allocator.free(input);

    const argv = try allocator.alloc(?[*:0]const u8, command_args.len + 2);
    defer allocator.free(argv);
    argv[0] = executable.ptr;
    for (command_args, 0..) |argument, index| argv[index + 1] = argument.ptr;
    argv[argv.len - 1] = null;

    const envp = try allocator.alloc(?[*:0]const u8, environment_entries.len + 1);
    defer allocator.free(envp);
    for (environment_entries, 0..) |entry, index| envp[index] = entry.ptr;
    envp[envp.len - 1] = null;

    var stdin_pipe: [2]c_int = undefined;
    var stdout_pipe: [2]c_int = undefined;
    var stderr_pipe: [2]c_int = undefined;
    var error_pipe: [2]c_int = undefined;
    var status_pipe: [2]c_int = undefined;
    try makePipe(&stdin_pipe);
    errdefer closePair(&stdin_pipe);
    try makePipe(&stdout_pipe);
    errdefer closePair(&stdout_pipe);
    try makePipe(&stderr_pipe);
    errdefer closePair(&stderr_pipe);
    try makePipe(&error_pipe);
    errdefer closePair(&error_pipe);
    try makePipe(&status_pipe);
    errdefer closePair(&status_pipe);
    if (c.fcntl(error_pipe[1], c.F_SETFD, c.FD_CLOEXEC) == -1) return error.SetCloseOnExecFailed;

    const monitor_pid = c.fork();
    if (monitor_pid == -1) return error.ForkFailed;

    if (monitor_pid == 0) monitorExec(executable, argv, cwd, envp, &stdin_pipe, &stdout_pipe, &stderr_pipe, &error_pipe, &status_pipe);

    closeFd(&stdin_pipe[0]);
    closeFd(&stdout_pipe[1]);
    closeFd(&stderr_pipe[1]);
    closeFd(&error_pipe[1]);
    closeFd(&status_pipe[1]);

    var pid: c.pid_t = 0;
    if (c.read(status_pipe[0], &pid, @sizeOf(c.pid_t)) != @sizeOf(c.pid_t) or pid <= 0) {
        return error.MonitorFailed;
    }

    var child_errno: c_int = 0;
    const error_bytes = c.read(error_pipe[0], &child_errno, @sizeOf(c_int));
    closeFd(&error_pipe[0]);
    if (error_bytes > 0) {
        closeFd(&stdin_pipe[1]);
        closeFd(&stdout_pipe[0]);
        closeFd(&stderr_pipe[0]);
        closeFd(&status_pipe[0]);
        return error.ExecFailed;
    }

    try setNonBlocking(stdin_pipe[1]);
    try setNonBlocking(stdout_pipe[0]);
    try setNonBlocking(stderr_pipe[0]);
    try setNonBlocking(status_pipe[0]);

    if (input.len == 0) closeFd(&stdin_pipe[1]);

    return .{
        .pid = pid,
        .stdin_fd = stdin_pipe[1],
        .stdout_fd = stdout_pipe[0],
        .stderr_fd = stderr_pipe[0],
        .status_fd = status_pipe[0],
        .stdin = input,
    };
}

pub fn readEvent(environment: beam.env, process: *Process) beam.term {
    lock(&process.mutex);
    defer process.mutex.unlock();

    if (process.terminal_emitted) return beam.make_atom(environment, "done");

    var poll_fds = [_]c.struct_pollfd{
        .{ .fd = process.stdout_fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = process.stderr_fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = process.stdin_fd, .events = c.POLLOUT, .revents = 0 },
    };

    _ = c.poll(&poll_fds, poll_fds.len, 50);

    pumpStdin(process, poll_fds[2].revents);

    if (readStream(environment, &process.stdout_fd, "stdout", poll_fds[0].revents)) |event| {
        return event;
    }

    if (readStream(environment, &process.stderr_fd, "stderr", poll_fds[1].revents)) |event| {
        return event;
    }

    observeTermination(process);

    if (process.term) |term| {
        if (process.stdout_fd == closed_fd and process.stderr_fd == closed_fd) {
            process.terminal_emitted = true;
            return terminalEvent(environment, term);
        }
    }

    return beam.make_atom(environment, "idle");
}

pub fn terminate(process: *Process, grace_milliseconds: u32) void {
    lock(&process.mutex);
    defer process.mutex.unlock();

    observeTermination(process);
    if (process.term != null) return;

    _ = c.kill(-process.pid, c.SIGTERM);
    const iterations = @max(grace_milliseconds / 10, 1);
    var index: u32 = 0;
    while (index < iterations) : (index += 1) {
        observeTermination(process);
        if (process.term != null) return;
        _ = c.usleep(10 * 1000);
    }

    _ = c.kill(-process.pid, c.SIGKILL);
    while (process.term == null) {
        observeTermination(process);
        if (process.term == null) _ = c.usleep(1000);
    }
}

pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
    const process: *Process = @ptrCast(@alignCast(object orelse return));
    terminate(process, 0);
    closeFd(&process.stdin_fd);
    closeFd(&process.stdout_fd);
    closeFd(&process.stderr_fd);
    closeFd(&process.status_fd);
    allocator.free(process.stdin);
}

fn childExec(
    executable: [:0]u8,
    argv: []?[*:0]const u8,
    cwd: [:0]u8,
    envp: []?[*:0]const u8,
    stdin_pipe: *[2]c_int,
    stdout_pipe: *[2]c_int,
    stderr_pipe: *[2]c_int,
    error_pipe: *[2]c_int,
) noreturn {
    closeFd(&error_pipe[0]);
    _ = c.setpgid(0, 0);

    if (c.dup2(stdin_pipe[0], c.STDIN_FILENO) == -1 or
        c.dup2(stdout_pipe[1], c.STDOUT_FILENO) == -1 or
        c.dup2(stderr_pipe[1], c.STDERR_FILENO) == -1 or
        c.chdir(executablePointer(cwd)) == -1)
    {
        childFail(error_pipe[1]);
    }

    closePair(stdin_pipe);
    closePair(stdout_pipe);
    closePair(stderr_pipe);
    _ = c.execve(executablePointer(executable), @ptrCast(argv.ptr), @ptrCast(envp.ptr));
    childFail(error_pipe[1]);
}

fn monitorExec(
    executable: [:0]u8,
    argv: []?[*:0]const u8,
    cwd: [:0]u8,
    envp: []?[*:0]const u8,
    stdin_pipe: *[2]c_int,
    stdout_pipe: *[2]c_int,
    stderr_pipe: *[2]c_int,
    error_pipe: *[2]c_int,
    status_pipe: *[2]c_int,
) noreturn {
    closeFd(&status_pipe[0]);
    const target_pid = c.fork();
    if (target_pid == -1) childFail(status_pipe[1]);

    if (target_pid == 0) {
        closeFd(&status_pipe[1]);
        childExec(executable, argv, cwd, envp, stdin_pipe, stdout_pipe, stderr_pipe, error_pipe);
    }

    _ = c.write(status_pipe[1], &target_pid, @sizeOf(c.pid_t));
    closePair(stdin_pipe);
    closePair(stdout_pipe);
    closePair(stderr_pipe);
    closePair(error_pipe);

    var status: c_int = 0;
    while (c.waitpid(target_pid, &status, 0) == -1 and errnoValue() == c.EINTR) {}
    _ = c.write(status_pipe[1], &status, @sizeOf(c_int));
    closeFd(&status_pipe[1]);
    c._exit(0);
}

fn childFail(error_fd: c_int) noreturn {
    const value: c_int = errnoValue();
    _ = c.write(error_fd, &value, @sizeOf(c_int));
    c._exit(127);
}

fn duplicateString(environment: beam.env, term: beam.term) ![:0]u8 {
    const value = try beam.get_char_slice(environment, term);
    return allocator.dupeZ(u8, value);
}

fn duplicateStringList(environment: beam.env, list_term: beam.term) ![][:0]u8 {
    const length = try beam.get_list_length(environment, list_term);
    const values = try allocator.alloc([:0]u8, length);
    errdefer allocator.free(values);
    var initialized: usize = 0;
    errdefer for (values[0..initialized]) |value| allocator.free(value);

    var list = list_term;
    for (values) |*value| {
        const head = try beam.get_head_and_iter(environment, &list);
        value.* = try duplicateString(environment, head);
        initialized += 1;
    }
    return values;
}

fn freeStrings(values: [][:0]u8) void {
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn makePipe(pipe: *[2]c_int) !void {
    if (c.pipe(pipe) == -1) return error.PipeFailed;
}

fn setNonBlocking(fd: c_int) !void {
    const flags = c.fcntl(fd, c.F_GETFL, @as(c_int, 0));
    if (flags == -1 or c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK) == -1) {
        return error.SetNonBlockingFailed;
    }
}

fn closePair(pipe: *[2]c_int) void {
    closeFd(&pipe[0]);
    closeFd(&pipe[1]);
}

fn closeFd(fd: *c_int) void {
    if (fd.* != closed_fd) {
        _ = c.close(fd.*);
        fd.* = closed_fd;
    }
}

fn pumpStdin(process: *Process, revents: c_short) void {
    if (process.stdin_fd == closed_fd) return;
    if ((revents & (c.POLLOUT | c.POLLERR | c.POLLHUP)) == 0) return;

    if ((revents & c.POLLOUT) != 0 and process.stdin_offset < process.stdin.len) {
        const remaining = process.stdin[process.stdin_offset..];
        const written = c.write(process.stdin_fd, remaining.ptr, remaining.len);
        if (written > 0) process.stdin_offset += @intCast(written);
    }

    if (process.stdin_offset == process.stdin.len or (revents & (c.POLLERR | c.POLLHUP)) != 0) {
        closeFd(&process.stdin_fd);
    }
}

fn readStream(environment: beam.env, fd: *c_int, comptime name: []const u8, revents: c_short) ?beam.term {
    if (fd.* == closed_fd) return null;
    if ((revents & (c.POLLIN | c.POLLHUP | c.POLLERR)) == 0) return null;

    var buffer: [read_chunk_size]u8 = undefined;
    const bytes_read = c.read(fd.*, &buffer, buffer.len);
    if (bytes_read > 0) {
        var tuple = [_]beam.term{
            beam.make_atom(environment, name),
            beam.make_slice(environment, buffer[0..@intCast(bytes_read)]),
        };
        return beam.make_tuple(environment, &tuple);
    }
    if (bytes_read == 0) closeFd(fd);
    return null;
}

fn observeTermination(process: *Process) void {
    if (process.term != null) return;
    var status: c_int = 0;
    const bytes_read = c.read(process.status_fd, &status, @sizeOf(c_int));
    if (bytes_read != @sizeOf(c_int)) return;
    closeFd(&process.status_fd);

    if (c.WIFEXITED(status)) {
        process.term = .{ .exit = @intCast(c.WEXITSTATUS(status)) };
    } else if (c.WIFSIGNALED(status)) {
        process.term = .{ .signal = @intCast(c.WTERMSIG(status)) };
    } else {
        process.term = .{ .signal = 0 };
    }
    closeFd(&process.stdin_fd);
}

fn terminalEvent(environment: beam.env, term: Term) beam.term {
    var tuple: [2]beam.term = undefined;
    switch (term) {
        .exit => |status| {
            tuple[0] = beam.make_atom(environment, "exit");
            tuple[1] = beam.make_u8(environment, status);
        },
        .signal => |signal| {
            tuple[0] = beam.make_atom(environment, "signal");
            tuple[1] = beam.make_u8(environment, signal);
        },
    }
    return beam.make_tuple(environment, &tuple);
}

fn executablePointer(value: [:0]u8) [*c]const u8 {
    return value.ptr;
}

fn errnoValue() c_int {
    return switch (@import("builtin").os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos => c.__error().*,
        else => c.__errno_location().*,
    };
}

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}
