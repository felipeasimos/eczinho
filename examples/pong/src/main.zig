const std = @import("std");
const rl = @import("raylib");
const options = @import("options");
const ecs = @import("eczinho");

const SCREEN_WIDTH = 1200;
const SCREEN_HEIGHT = 800;
const PADDLE_WIDTH = 50;
const PADDLE_HEIGHT = 200;
const BALL_SIDE = 10;
const BALL_MAX_SPEED = 15;
const BALL_MIN_SPEED = 10;
const PADDLE_SPEED = 7;

// components
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
const Ball = struct {};
const Score = struct { player: u32 = 0, enemy: u32 = 0 };

// events
const BallPaddleCollision = struct {
    center_diff: f32,
    safe_x: f32,
    paddle: enum { Left, Right },
};
const TopBottomCollision = enum {
    Top,
    Bottom,
};
const GoalCollision = enum { Left, Right };

const Context = ecs.AppContextBuilder.init()
    .addEvents(&.{
        BallPaddleCollision,
        TopBottomCollision,
    })
    .addEvent(GoalCollision)
    .addResource(std.Random)
    .addResource(Score)
    .addComponents(&.{
        Velocity,
        Position,
        Rect,
        Player,
        Enemy,
    })
    .addComponent(Ball)
    .build();
const Commands = Context.Commands;
const EventReader = Context.EventReader;
const EventWriter = Context.EventWriter;
const Query = Context.Query;
const Resource = Context.Resource;
const Entity = Context.Entity;

fn updatePositions(q: Query(.{ .q = &.{ *Position, Velocity } })) void {
    var iter = q.iter();
    while (iter.next()) |tuple| {
        const pos_ptr, const vel = tuple;
        pos_ptr.x += vel.x;
        pos_ptr.y += vel.y;
    }
}

fn reactGoalCollision(commands: Commands, res: Resource(Score), q: Query(.{ .q = &.{Entity}, .with = &.{Ball} }), reader: EventReader(GoalCollision)) !void {
    const single = q.optSingle() orelse return;
    if (reader.optRead()) |goal| {
        const entt = single[0];
        commands.despawn(entt);
        switch (goal) {
            .Right => res.get().enemy += 1,
            .Left => res.get().player += 1,
        }
    }
}

fn reactBallPaddleCollision(q: Query(.{ .q = &.{ *Velocity, *Position }, .with = &.{Ball} }), reader: EventReader(BallPaddleCollision)) void {
    if (reader.optRead()) |col| {
        const vel_ptr, const pos_ptr = q.single();
        vel_ptr.x *= -1;

        pos_ptr.x = col.safe_x;

        vel_ptr.y *= col.center_diff;
    }
}

fn reactTopBottomCollision(q: Query(.{ .q = &.{ *Velocity, *Position, Rect }, .with = &.{Ball} }), reader: EventReader(TopBottomCollision)) void {
    if (reader.optRead()) |col| {
        const vel_ptr, const pos_ptr, const rect = q.single();
        vel_ptr.y *= -1;

        pos_ptr.y = switch (col) {
            .Top => 1,
            .Bottom => @as(f32, @floatFromInt(rl.getScreenHeight())) - rect.height - 1,
        };
    }
}

fn checkCollision(
    a: struct { Rect, Position },
    b: struct { Rect, Position },
) bool {
    const a_rect, const a_pos = a;
    const b_rect, const b_pos = b;

    const a_min_x = a_pos.x;
    const a_min_y = a_pos.y;
    const a_max_x = a_pos.x + a_rect.width;
    const a_max_y = a_pos.y + a_rect.height;

    const b_min_x = b_pos.x;
    const b_min_y = b_pos.y;
    const b_max_x = b_pos.x + b_rect.width;
    const b_max_y = b_pos.y + b_rect.height;

    return a_min_x < b_max_x and
        a_max_x > b_min_x and
        a_min_y < b_max_y and
        a_max_y > b_min_y;
}

const ball = Query(.{ .q = &.{ Rect, Position }, .with = &.{Ball} });
fn checkGoalCollision(b: ball, writer: EventWriter(GoalCollision)) void {
    if (b.peek()) |single| {
        const rect, const pos = single;
        if (pos.x + rect.width > @as(f32, @floatFromInt(rl.getScreenWidth()))) {
            writer.write(GoalCollision.Right);
        } else if (pos.x < 0) {
            writer.write(GoalCollision.Left);
        }
    }
}

const enemy = Query(.{ .q = &.{ Rect, Position }, .with = &.{Enemy} });
const player = Query(.{ .q = &.{ Rect, Position }, .with = &.{Player} });
fn checkPaddleBallCollision(b: ball, e: enemy, p: player, writer: EventWriter(BallPaddleCollision)) !void {
    const ball_info = b.optSingle() orelse return;
    const enemy_info = e.single();
    const player_info = p.single();
    if (checkCollision(ball_info, enemy_info)) {
        const enemy_half = enemy_info[1].y + (enemy_info[0].height / 2);
        const ball_half = ball_info[1].y + (ball_info[0].height / 2);
        writer.write(BallPaddleCollision{
            .paddle = .Right,
            .safe_x = @as(f32, @floatFromInt(rl.getScreenWidth())) - enemy_info[0].width - ball_info[0].width,
            .center_diff = (ball_half - enemy_half) / enemy_half,
        });
    } else if (checkCollision(ball_info, player_info)) {
        const player_half = player_info[1].y + (player_info[0].height / 2);
        const ball_half = ball_info[1].y + (ball_info[0].height / 2);
        writer.write(BallPaddleCollision{
            .paddle = .Left,
            .safe_x = player_info[0].width,
            .center_diff = (ball_half - player_half) / player_half,
        });
    }
}

fn checkTopBottomCollision(q: Query(.{ .q = &.{ Rect, Position }, .with = &.{Ball} }), writer: EventWriter(TopBottomCollision)) void {
    const rect, const pos = q.optSingle() orelse return;
    if (pos.y + rect.height > @as(f32, @floatFromInt(rl.getScreenHeight()))) {
        writer.write(TopBottomCollision.Bottom);
    } else if (pos.y < 0) {
        writer.write(TopBottomCollision.Top);
    }
}

fn handleControls(q: Query(.{ .q = &.{ *Position, Rect }, .with = &.{Player} })) void {
    const pos_ptr, const rect = q.single();
    if (rl.isKeyDown(rl.KeyboardKey.s)) {
        if (pos_ptr.y + rect.height < @as(f32, @floatFromInt(rl.getScreenHeight()))) {
            pos_ptr.y += PADDLE_SPEED;
        }
    } else if (rl.isKeyDown(rl.KeyboardKey.w)) {
        if (pos_ptr.y > 0) {
            pos_ptr.y -= PADDLE_SPEED;
        }
    }
}

fn moveEnemy(q: Query(.{ .q = &.{ *Velocity, *Position, Rect }, .with = &.{Enemy} })) void {
    const vel_ptr, const pos_ptr, const rect = q.single();
    const screen_height: f32 = @floatFromInt(rl.getScreenHeight());
    if (pos_ptr.y + rect.height > screen_height) {
        vel_ptr.y *= -1;
        pos_ptr.y = screen_height - rect.height;
    } else if (pos_ptr.y < 0) {
        vel_ptr.y *= -1;
        pos_ptr.y = 0;
    }
}

fn createBall(commands: Commands, random: Resource(std.Random), q: Query(.{ .with = &.{Ball} })) void {
    if (q.len() != 0) {
        return;
    }
    const rnd: std.Random = random.clone();
    const angle = rnd.float(f32) * 2 * std.math.pi;
    const speed = BALL_MIN_SPEED + (rnd.float(f32) * (BALL_MAX_SPEED - BALL_MIN_SPEED));

    const width: f32 = @floatFromInt(rl.getScreenWidth());
    const height: f32 = @floatFromInt(rl.getScreenHeight());
    _ = commands.spawn()
        .add(Position{ .x = width / 2, .y = height / 2 })
        .add(Velocity{ .x = @cos(angle) * speed, .y = speed })
        // .add(Velocity{ .x = @cos(angle) * speed, .y = @sin(angle) * speed })
        .add(Rect{ .width = BALL_SIDE, .height = BALL_SIDE })
        .add(Ball{});
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
        .add(Rect{ .width = PADDLE_WIDTH, .height = PADDLE_HEIGHT })
        .add(Velocity{ .y = PADDLE_SPEED, .x = 0 });
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
        .addSystem(.Startup, createBall)
        .addSystem(.Update, createBall)
        .addSystem(.Update, handleControls)
        .addSystem(.Update, reactGoalCollision)
        .addSystem(.Update, checkGoalCollision)
        .addSystem(.Update, reactBallPaddleCollision)
        .addSystem(.Update, checkPaddleBallCollision)
        .addSystem(.Update, reactTopBottomCollision)
        .addSystem(.Update, checkTopBottomCollision)
        .addSystem(.Update, updatePositions)
        .addSystem(.Update, moveEnemy)
        .addSystem(.Render, renderRectangles)
        .build(allocator);
    defer app.deinit();
    var prng = std.Random.DefaultPrng.init(blk: {
        // SAFETY: defined immediatly after
        var seed: u64 = undefined;
        std.crypto.random.bytes(std.mem.asBytes(&seed));
        break :blk seed;
    });
    try app.insert(prng.random());
    try app.insert(Score{});

    try app.run();
    // while (!rl.windowShouldClose()) {
    //     rl.beginDrawing();
    //     defer rl.endDrawing();
    //     rl.clearBackground(rl.Color.white);
    // }
}
