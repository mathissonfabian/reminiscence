const std = @import("std");
const rl = @import("raylib");

pub fn init() void {
    const windowWidth = 600;
    const screenHeight = 450;

    rl.initWindow(windowWidth, screenHeight, "reminiscence");

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

    rl.clearBackground(.white);

    rl.drawText("Reminiscence", 190, 200, 20, .light_gray);
}
