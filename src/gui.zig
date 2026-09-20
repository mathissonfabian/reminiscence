const std = @import("std");
const rl = @import("raylib");
const recorder = @import("recorder.zig");

const windowWidth = 1000;
const windowHeight = 850;

pub fn init() void {

    rl.initWindow(windowWidth, windowHeight, "reminiscence");
    rl.setTargetFPS(30);
}

pub fn advance() !void {
    if (rl.windowShouldClose()) {
        return;
    }
    if (rl.isKeyDown(.left_control) and rl.isKeyPressed(.c)) {
        rl.closeWindow();

        return;
    }

    // Draw
    //----------------------------------------------------------------------------------
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(.black);

    const title = "Reminiscence";
    const title_size = 32;
    const title_width = rl.measureText(title, title_size);
    rl.drawText(title, @divTrunc(windowWidth - title_width, 2), 50, title_size, .gold);

    const window_title = blk: {
        if (recorder.instance.process) |process| {
            var buf: [256]u8 = undefined;
            break :blk std.fmt.bufPrintZ(&buf, "Recording: {s}", .{process.name}) catch "Recording: ?";
        } else {
            break :blk "Not recording";
        }
    };

    var buf: [256]u8 = undefined;
    const source = recorder.instance.audio_source orelse "No audio source found";
    const audio_source = try std.fmt.bufPrintSentinel(&buf, "Audio Output: {s}", .{source}, 0);

    const rec_name_size = 20;
    const rec_name_width = rl.measureText(window_title, rec_name_size);
    rl.drawText(window_title, @divTrunc(windowWidth - rec_name_width, 2), windowHeight/2, rec_name_size, .light_gray);

    const rec_audio_size = 20;
    const rec_audio_width = rl.measureText(audio_source, rec_audio_size);
    rl.drawText(audio_source, @divTrunc(windowWidth - rec_audio_width, 2), windowHeight/2+40, rec_audio_size, .light_gray);
}
