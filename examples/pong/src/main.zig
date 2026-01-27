const std = @import("std");
const rl = @import("raylib");
const options = @import("options");
const ecs = @import("eczinho");

const SCREEN_WIDTH = 1200;
const SCREEN_HEIGHT = 800;
const PADDLE_WIDTH = 50;
const PADDLE_HEIGHT = 200;
const BALL_SIDE = 10;
const PADDLE_SPEED = 1;

const Position = struct {
    x: f32,
    y: f32,
};
const Velocity = struct {
    x: f32,
    y: f32,
};
const Rect = struct {
    width: f32,
    height: f32,
};
const Player = struct {};
const Enemy = struct {};

const Context = ecs.AppContextBuilder.init()
    .addComponents(&.{
        Velocity,
        Position,
        Rect,
        Player,
        Enemy,
    })
    .build();
const Commands = Context.Commands;
// const EventReader = Context.EventReader;
// const EventWriter = Context.EventWriter;
const Query = Context.Query;
// const Resource = Context.Resource;

fn handleControls(q: Query(.{ .q = &.{ *Position, Rect }, .with = &.{Player} })) void {
    const pos_ptr, const rect = q.single();
    if (rl.isKeyDown(rl.KeyboardKey.s)) {
        if (pos_ptr.*.y + rect.height < @as(f32, @floatFromInt(rl.getScreenHeight()))) {
            pos_ptr.*.y += PADDLE_SPEED;
        }
    } else if (rl.isKeyDown(rl.KeyboardKey.w)) {
        if (pos_ptr.*.y > 0) {
            pos_ptr.*.y -= PADDLE_SPEED;
        }
    }
}

fn createPlayerPaddle(commands: Commands) void {
    _ = commands.spawn()
        .add(Position{ .x = 0, .y = 0 })
        .add(Rect{ .width = PADDLE_WIDTH, .height = PADDLE_HEIGHT })
        .add(Player{});
}

fn createEnemyPaddle(commands: Commands) void {
    _ = commands.spawn()
        .add(Enemy{})
        .add(Position{ .x = @as(f32, @floatFromInt(rl.getScreenWidth())) - PADDLE_WIDTH, .y = 0 })
        .add(Rect{ .width = PADDLE_WIDTH, .height = PADDLE_HEIGHT });
}

fn renderRectangles(q: Query(.{ .q = &.{ Position, Rect } })) void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.Color.black);

    var iter = q.iter();
    while (iter.next()) |data| {
        const pos, const rect = data;
        rl.drawRectangleLinesEx(
            .{ .x = pos.x, .y = pos.y, .width = rect.width, .height = rect.height },
            2,
            rl.Color.white,
        );
    }
}

pub fn main() !void {
    rl.setConfigFlags(.{
        .fullscreen_mode = false,
    });
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, std.fmt.comptimePrint("Pong with eczinho - {s}", .{options.git_commit_hash}));
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var debug_allocator = std.heap.DebugAllocator(.{ .safety = true }).init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var app = ecs.AppBuilder.init(Context)
        .addSystem(.Startup, createPlayerPaddle)
        .addSystem(.Startup, createEnemyPaddle)
        .addSystem(.Update, handleControls)
        .addSystem(.Render, renderRectangles)
        .build(allocator);
    defer app.deinit();

    try app.run();
    // while (!rl.windowShouldClose()) {
    //     rl.beginDrawing();
    //     defer rl.endDrawing();
    //     rl.clearBackground(rl.Color.white);
    // }
}
