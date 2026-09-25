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

    try draw_button("Record", windowWidth-200, 200);
    try draw_button("Stop", windowWidth-200, 300);
}

// TODO: Register callback, scale button after button text
fn draw_button(text: [:0]const u8, posX: i32, posY: i32) !void
{
    const FONT_SIZE: i32 = 24;
    const BTN_WIDTH: i32 = 150;
    const BTN_HEIGHT: i32 = 70;

    rl.drawRectangle(posX, posY, BTN_WIDTH, BTN_HEIGHT, .gold);
    const txt_msm = rl.measureTextEx(try rl.getFontDefault(), text, FONT_SIZE, FONT_SIZE/10);
    rl.drawText(text, posX+(@divTrunc(BTN_WIDTH - @as(i32, @intFromFloat(txt_msm.x)), 2)), posY+(@divTrunc(BTN_HEIGHT - @as(i32, @intFromFloat(txt_msm.y)), 2)), FONT_SIZE, .black);
}
