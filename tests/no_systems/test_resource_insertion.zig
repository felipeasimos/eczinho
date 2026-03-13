const eczinho = @import("eczinho");
const std = @import("std");

test "resource insertion" {
    const ResourceA = u64;
    const Context = eczinho.AppContextBuilder.init()
        .addResource(ResourceA)
        .build();

    const Resource = Context.Resource;
    const ResourceStore = Context.ResourceStore;

    var app = eczinho.AppBuilder.init(Context)
        .addSystem(.Startup, (struct {
            pub fn insert(store: *ResourceStore) !void {
                store.insert(@as(ResourceA, 34));
            }
        }).insert)
        .addSystem(.Update, (struct {
            pub fn get(res: Resource(ResourceA)) !void {
                try std.testing.expectEqual(@as(ResourceA, 34), res.clone());
            }
        }).get)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();
    try app.startup();
    try app.runOne();
}
