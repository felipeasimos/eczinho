const std = @import("std");
const rl = @import("raylib");
const options = @import("options");
const ecs = @import("eczinho");

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 400;
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
const GoalCollision = enum { Left, Right };

const Context = ecs.AppContextBuilder.init()
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
const Removed = Context.Removed;

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
    if (reader.readOne()) |goal| {
        reader.clear();
        const entt = single[0];
        commands.remove(Ball, entt);
        switch (goal) {
            .Right => res.get().enemy += 1,
            .Left => res.get().player += 1,
        }
    }
}

fn checkCollision(
    a: anytype,
    b: anytype,
    // a: struct { Rect, Position },
    // b: struct { Rect, Position },
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

const ball_ptr = Query(.{ .q = &.{ Rect, *Position, *Velocity }, .with = &.{Ball} });
const enemy = Query(.{ .q = &.{ Rect, Position }, .with = &.{Enemy} });
const player = Query(.{ .q = &.{ Rect, Position }, .with = &.{Player} });
fn checkPaddleBallCollision(b: ball_ptr, e: enemy, p: player) !void {
    const ball_rect, const ball_pos_ptr, const ball_vel_ptr = b.optSingle() orelse return;
    const enemy_info = e.single();
    const player_info = p.single();
    const result: ?struct { f32, f32 } = collision_result: {
        if (checkCollision(.{ ball_rect, ball_pos_ptr }, enemy_info)) {
            const enemy_half = enemy_info[1].y + (enemy_info[0].height / 2);
            const ball_half = ball_pos_ptr.y + (ball_rect.height / 2);
            const safe_x = @as(f32, @floatFromInt(rl.getScreenWidth())) - enemy_info[0].width - ball_rect.width;
            const center_diff = (ball_half - enemy_half) / enemy_half;
            break :collision_result .{ safe_x, center_diff };
        } else if (checkCollision(.{ ball_rect, ball_pos_ptr }, player_info)) {
            const player_half = player_info[1].y + (player_info[0].height / 2);
            const ball_half = ball_pos_ptr.y + (ball_rect.height / 2);

            const safe_x = player_info[0].width;
            const center_diff = (ball_half - player_half) / player_half;
            break :collision_result .{ safe_x, center_diff };
        }
        break :collision_result null;
    };
    if (result) |collision_info| {
        const safe_x, const center_diff = collision_info;
        ball_vel_ptr.x *= -1.2;
        ball_pos_ptr.x = safe_x;

        ball_vel_ptr.y = center_diff * BALL_MAX_SPEED;
    }
}

fn checkTopBottomCollision(q: Query(.{ .q = &.{ Rect, *Position, *Velocity }, .with = &.{Ball} })) void {
    const rect, const pos_ptr, const vel_ptr = q.optSingle() orelse return;

    if (pos_ptr.y + rect.height > @as(f32, @floatFromInt(rl.getScreenHeight())) and vel_ptr.y > 0) {
        vel_ptr.y *= -1;
        pos_ptr.y = @as(f32, @floatFromInt(rl.getScreenHeight())) - rect.height - 1;
    } else if (pos_ptr.y < 0 and vel_ptr.y < 0) {
        vel_ptr.y *= -1;
        pos_ptr.y = 1;
    }
}

fn handleControls(q: Query(.{ .q = &.{ *Position, Rect }, .with = &.{Player} }), writer: EventWriter(ecs.AppEvents.AppExit)) void {
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
    if (rl.windowShouldClose()) {
        writer.write(ecs.AppEvents.AppExit{});
    }
}

fn moveEnemy(q: Query(.{ .q = &.{ *Position, Rect }, .with = &.{Enemy} })) void {
    // const vel_ptr, const pos_ptr, const rect = q.single();
    // const screen_height: f32 = @floatFromInt(rl.getScreenHeight());
    // if (pos_ptr.y + rect.height > screen_height) {
    //     vel_ptr.y *= -1;
    //     pos_ptr.y = screen_height - rect.height;
    // } else if (pos_ptr.y < 0) {
    //     vel_ptr.y *= -1;
    //     pos_ptr.y = 0;
    // }
    const pos_ptr, const rect = q.single();
    if (rl.isKeyDown(rl.KeyboardKey.down)) {
        if (pos_ptr.y + rect.height < @as(f32, @floatFromInt(rl.getScreenHeight()))) {
            pos_ptr.y += PADDLE_SPEED;
        }
    } else if (rl.isKeyDown(rl.KeyboardKey.up)) {
        if (pos_ptr.y > 0) {
            pos_ptr.y -= PADDLE_SPEED;
        }
    }
}

fn randomInRange(rnd: std.Random, min: f32, max: f32) f32 {
    return min + rnd.float(f32) * (max - min);
}

fn createBall(commands: Commands, random: Resource(std.Random), q: Query(.{ .with = &.{Ball} })) void {
    if (q.len() != 0) {
        return;
    }
    const rnd: std.Random = random.clone();
    const angle = randomInRange(rnd, std.math.pi * 3.0 / 4.0, std.math.pi * 5.0 / 4.0);
    const speed = BALL_MIN_SPEED + (rnd.float(f32) * (BALL_MAX_SPEED - BALL_MIN_SPEED));

    const width: f32 = @floatFromInt(rl.getScreenWidth());
    const height: f32 = @floatFromInt(rl.getScreenHeight());
    _ = commands.spawn()
        .add(Position{ .x = width / 2, .y = height / 2 })
        // .add(Velocity{ .x = @cos(angle) * speed, .y = speed })
        .add(Velocity{ .x = @cos(angle) * speed, .y = @sin(angle) * speed })
        .add(Rect{ .width = BALL_SIDE, .height = BALL_SIDE })
        .add(Ball{});
}

fn respawnBall(commands: Commands, r: Removed(Ball)) void {
    if (r.readOne()) |entt| {
        _ = commands.entity(entt)
            .add(Ball{});
    }
}

fn repositionBall(q: Query(.{ .q = &.{ *Position, *Velocity }, .added = &.{Ball} }), random: Resource(std.Random)) void {
    if (q.optSingle()) |data| {
        const pos_ptr, const vel_ptr = data;
        const rnd: std.Random = random.clone();
        const angle = randomInRange(rnd, std.math.pi * 3.0 / 4.0, std.math.pi * 5.0 / 4.0);
        const speed = BALL_MIN_SPEED + (rnd.float(f32) * (BALL_MAX_SPEED - BALL_MIN_SPEED));

        const width: f32 = @floatFromInt(rl.getScreenWidth());
        const height: f32 = @floatFromInt(rl.getScreenHeight());

        pos_ptr.* = Position{ .x = width / 2, .y = height / 2 };
        vel_ptr.* = Velocity{ .x = @cos(angle) * speed, .y = @sin(angle) * speed };
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
        .add(Position{ .x = @as(f32, @floatFromInt(rl.getScreenWidth())) - PADDLE_WIDTH, .y = 0 })
        .add(Rect{ .width = PADDLE_WIDTH, .height = PADDLE_HEIGHT })
        .add(Enemy{});
    // _ = commands.spawn()
    //     .add(Enemy{})
    //     .add(Position{ .x = @as(f32, @floatFromInt(rl.getScreenWidth())) - PADDLE_WIDTH, .y = 0 })
    //     .add(Rect{ .width = PADDLE_WIDTH, .height = PADDLE_HEIGHT })
    //     .add(Velocity{ .y = PADDLE_SPEED, .x = 0 });
}

fn renderRectangles(q: Query(.{ .q = &.{ Position, Rect } })) void {
    rl.beginDrawing();
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

fn renderScore(score: Resource(Score)) !void {
    defer rl.endDrawing();

    const enemy_score = score.clone().enemy;
    const player_score = score.clone().player;
    var buf: [1024]u8 = undefined;
    const str = try std.fmt.bufPrintZ(&buf, "{} | {}", .{ enemy_score, player_score });
    const screen_width: i32 = rl.getScreenWidth();
    const screen_height: i32 = rl.getScreenHeight();
    const text_width = rl.measureText(str, 100);
    rl.drawText(str, @divFloor(screen_width, 2) - @divFloor(text_width, 2), @divFloor(screen_height, 2), 100, rl.Color.white);
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
        .addSystem(.Update, respawnBall)
        .addSystem(.Update, repositionBall)
        .addSystem(.Update, handleControls)
        .addSystem(.Update, checkTopBottomCollision)
        .addSystem(.Update, checkPaddleBallCollision)
        .addSystem(.Update, reactGoalCollision)
        .addSystem(.Update, checkGoalCollision)
        .addSystem(.Update, updatePositions)
        .addSystem(.Update, moveEnemy)
        .addSystem(.Render, renderRectangles)
        .addSystem(.Render, renderScore)
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
}
