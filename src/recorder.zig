const std = @import("std");

pub var instance: Recorder = .{ .child_args = &.{} };

pub const Config = struct {
    framerate: u16,
    output_dir: []const u8,

    fn framerate_as_str(self: Config, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{}", .{self.framerate});
    }
};

pub const Process = struct {
    name: []const u8,
    machine_name: []const u8,
    pid: u32,
    desktop_id: i32,
    geometry: struct {
        x_offset: i32,
        y_offset: i32,
        width: u32,
        height: u32,
    },

    pub fn deinit(self: Process, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.machine_name);
    }

    pub fn format(self: Process, writer: *std.Io.Writer) !void {
        try writer.print("{s}; pid: {}; workspace: {}; geometry: {}", .{self.name, self.pid, self.desktop_id, self.geometry});
    }

    pub fn eql(item1: Process, item2: Process) bool {
        if (!std.mem.eql(u8, item1.name, item2.name)) return false;
        if (item1.pid != item2.pid) return false;

        return true;
    }
};

const Recorder = struct {
    child: ?std.process.Child = null,
    child_args: [][]const u8,
    process: ?Process = null,
    audio_source: ?[]const u8 = null,
    is_recording: bool = false,

    // TODO: Create deinit fn

    pub fn start_recording(self: *Recorder, config: Config, process: Process, allocator: std.mem.Allocator, io: std.Io) !void {
        self.audio_source = try get_default_audio(allocator, io);
        std.debug.print("Recording with device {s}\n", .{self.audio_source.?});

        const datestr = try get_datestr(allocator, io);
        defer allocator.free(datestr);

        const safe_name = try sanitize_filename(allocator, process.name);
        defer allocator.free(safe_name);

        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}-{s}.mp4", .{config.output_dir, safe_name, datestr});
        defer allocator.free(full_path);

        const args_tmp = [_][]const u8 {
            "wf-recorder",
            "-f", full_path,
            "--framerate", try config.framerate_as_str(allocator),
            "--overwrite",
            "--codec", "hevc_nvenc",
            "--codec-param", "preset=p5",
            "--codec-param", "tune=hq",
            "--codec-param", "rc=vbr",
            "--codec-param", "cq=26",
            try std.fmt.allocPrint(allocator, "--audio={s}", .{self.audio_source.?}),
            "--geometry", try std.fmt.allocPrint(allocator, "{},{} {}x{}", .{
                process.geometry.x_offset,
                process.geometry.y_offset,
                process.geometry.width,
                process.geometry.height})
        };

        std.debug.print("wf-recorder args:\n", .{});
        for (args_tmp) |arg| {
            std.debug.print("{s} ", .{arg});
        }
        // The format is "x,y WxH"
        var args = try allocator.alloc([]const u8, args_tmp.len);
        for (args_tmp, 0..) |arg, i| {
            args[i] = try allocator.dupe(u8, arg);
        }

        self.is_recording = true;

        self.child = try std.process.spawn(io, .{ .argv = args });
        self.process = process;
    }

    pub fn stop_recording(self: *Recorder, io: std.Io) void {
        self.child.?.kill(io);
        self.child = null;
        self.process = null;
        self.is_recording = false;
    }

    pub fn get_audio_source() void {
        // todo 
        // pactl list sources | grep Name
    }

    pub fn set_audio_source() void {
        // todo 
    }
};

const NS_PER_MS: u64 = 1_000_000;

/// Window titles can contain '/', which would otherwise be interpreted as a
/// path separator (e.g. Reddit tab titles like "... : r/sweden - Chromium"),
/// causing ffmpeg's avio_open to fail because the resulting subdirectory
/// doesn't exist.
fn sanitize_filename(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const sanitized = try allocator.dupe(u8, name);
    for (sanitized) |*c| {
        if (c.* == '/') c.* = '-';
    }
    return sanitized;
}

fn get_datestr(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    const timestamp_ns = std.Io.Clock.real.now(io).nanoseconds;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(@divTrunc(timestamp_ns, std.time.ns_per_s)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return try std.fmt.allocPrint(allocator, "{}-{}-{}-{}-{}", 
        .{year_day.year, month_day.month.numeric(), month_day.day_index+1, day_seconds.getHoursIntoDay(), day_seconds.getMinutesIntoHour()});
}

const HyprMonitor = struct {
    activeWorkspace: struct { id: i32 },
};

const HyprClient = struct {
    mapped: bool,
    hidden: bool,
    at: [2]i32,
    size: [2]u32,
    workspace: struct { id: i32 },
    class: []const u8,
    title: []const u8,
    pid: u32,
};

fn run_hyprctl(allocator: std.mem.Allocator, io: std.Io, comptime subcommand: []const u8) !std.process.RunResult {
    return try std.process.run(allocator, io, .{
        .argv = &.{ "hyprctl", subcommand, "-j" },
    });
}

/// Returns the windows on whichever workspace is currently shown on some monitor.
/// Hyprland keeps geometry for windows on non-visible workspaces too, but that
/// geometry doesn't correspond to any actual on-screen position, so those
/// windows are filtered out here.
pub fn get_visible_windows(allocator: std.mem.Allocator, io: std.Io) !std.ArrayList(Process) {
    var processes: std.ArrayList(Process) = .empty;

    const monitors_result = try run_hyprctl(allocator, io, "monitors");
    defer allocator.free(monitors_result.stdout);
    defer allocator.free(monitors_result.stderr);

    const monitors_parsed = try std.json.parseFromSlice([]HyprMonitor, allocator, monitors_result.stdout, .{ .ignore_unknown_fields = true });
    defer monitors_parsed.deinit();

    const clients_result = try run_hyprctl(allocator, io, "clients");
    defer allocator.free(clients_result.stdout);
    defer allocator.free(clients_result.stderr);

    const clients_parsed = try std.json.parseFromSlice([]HyprClient, allocator, clients_result.stdout, .{ .ignore_unknown_fields = true });
    defer clients_parsed.deinit();

    for (clients_parsed.value) |client| {
        if (!client.mapped or client.hidden) continue;

        const is_visible = for (monitors_parsed.value) |monitor| {
            if (monitor.activeWorkspace.id == client.workspace.id) break true;
        } else false;
        if (!is_visible) continue;

        try processes.append(allocator, .{
            .pid = client.pid,
            .desktop_id = client.workspace.id,
            .geometry = .{
                .x_offset = client.at[0],
                .y_offset = client.at[1],
                .width = client.size[0],
                .height = client.size[1],
            },
            .machine_name = try allocator.dupe(u8, client.class),
            .name = try allocator.dupe(u8, client.title),
        });
    }

    return processes;
}

fn get_default_audio(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    const res = try std.process.run(allocator, io, .{.argv = &.{"pactl", "get-default-sink"}});
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);

    const trimmed = std.mem.trim(u8, res.stdout, &.{'\n'});
    
    return try std.fmt.allocPrint(allocator, "{s}.monitor", .{trimmed});
}
