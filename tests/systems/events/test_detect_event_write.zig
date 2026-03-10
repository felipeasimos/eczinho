const std = @import("std");
const eczinho = @import("eczinho");

test "check if event was written" {
    const ComponentA = u64;
    const EventA = u32;
    const ReadCounter = struct { count: u32 = 0 };
    const WriteCounter = struct { count: u32 = 0 };
    const Context = eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .addResource(ReadCounter)
        .addResource(WriteCounter)
        .addEvent(EventA)
        .build();

    const Resource = Context.Resource;
    const ResourceStore = Context.ResourceStore;
    const EventWriter = Context.EventWriter;
    const EventReader = Context.EventReader;

    var app = eczinho.AppBuilder.init(Context)
        .addSystem(.Startup, (struct {
            pub fn insertResources(store: *ResourceStore) !void {
                store.insert(ReadCounter{});
                store.insert(WriteCounter{});
            }
        }).insertResources)
        .addSystem(.Update, (struct {
            pub fn readEvent(reader: EventReader(EventA), read_count: Resource(ReadCounter)) void {
                if (reader.readOne()) |_| {
                    read_count.get().*.count += 1;
                }
            }
        }).readEvent)
        .addSystem(.Update, (struct {
            pub fn writeEvent(writer: EventWriter(EventA), write_count: Resource(WriteCounter)) void {
                writer.write(@as(EventA, 2));
                write_count.get().*.count += 1;
            }
        }).writeEvent)
        .build(std.testing.allocator);
    defer app.deinit();

    try app.startup();

    try std.testing.expectEqual(0, app.resource_store.clone(ReadCounter).count);
    try std.testing.expectEqual(0, app.resource_store.clone(WriteCounter).count);

    // write event
    // nothing to read yet
    try app.runOne();

    try std.testing.expectEqual(0, app.resource_store.clone(ReadCounter).count);
    try std.testing.expectEqual(1, app.resource_store.clone(WriteCounter).count);

    // written events become readable
    // write new one too
    try app.runOne();

    try std.testing.expectEqual(1, app.resource_store.clone(ReadCounter).count);
    try std.testing.expectEqual(2, app.resource_store.clone(WriteCounter).count);

    // written become readable + 1 to read
    // write new one + 1 to write
    try app.runOne();

    try std.testing.expectEqual(2, app.resource_store.clone(ReadCounter).count);
    try std.testing.expectEqual(3, app.resource_store.clone(WriteCounter).count);
}
