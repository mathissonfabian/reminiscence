const std = @import("std");

const recorder = @import("recorder.zig");
const gui = @import("gui.zig");
const rl = @import("raylib");

fn process_monitor(config: recorder.Config, allocator: std.mem.Allocator, io: std.Io) !void {
    while (true) {
        // should probably create thread for the recorder
        var processes = try recorder.get_visible_windows(allocator, io);
        defer processes.deinit(allocator);
        defer {
            for (processes.items) |p| {
                p.deinit(allocator);
            }
        }

        if (processes.items.len > 0) {
            std.debug.print("Found {} process/es\n", .{processes.items.len});
            for (processes.items) |p| {
                std.debug.print("{f}\n", .{p});
            }

            const process = &processes.items[0];
            try recorder.instance.start_recording(config, process.*, allocator, io);
            std.debug.print("Starting recording with process: {f}\n", .{process});

            // Break this into another fn?
            // Keep recording until our original process is no longer running
            while (true) {
                var processes2 = try recorder.get_visible_windows(allocator, io);
                defer processes2.deinit(allocator);

                var still_running: bool = false;
                for (processes2.items) |p2| {
                    if (recorder.Process.eql(process.*, p2)) {
                        still_running = true;
                        break;
                    }
                }
                if (!still_running) break;

                try std.Io.sleep(io, .fromMilliseconds(1000), .awake);
            }

            recorder.instance.stop_recording(io);
            std.debug.print("Stopped recording for process {f}\n", .{process});
        }
        else {
            std.debug.print("No processes found\n", .{});
        }

        try std.Io.sleep(io, .fromMilliseconds(1000), .awake);
    }
}

pub fn main(init: std.process.Init) !void {
    gui.init();

    const config = recorder.Config{
        .framerate = 60,
        .output_dir = "./Recordings/",
    };

    // Spawn recorder thread
    _ = try std.Thread.spawn(.{}, process_monitor, .{config, init.gpa, init.io});

    while (true) {
        try gui.advance();
        try std.Io.sleep(init.io, .fromMilliseconds(1000), .awake);
    }
}

