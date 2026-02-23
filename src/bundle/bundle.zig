const std = @import("std");
const StageLabel = @import("../stage_label.zig").StageLabel;

pub const Bundle = struct {
    ContextConstructor: fn (comptime Entity: type) BundleContext = (struct {
        pub fn default(comptime _: type) BundleContext {
            return BundleContext.Builder.init().build();
        }
    }).default,
    FunctionsConstructor: fn (comptime AppContext: type) type = (struct {
        pub fn default(comptime _: type) type {
            return struct {};
        }
    }).default,

    /// system constructor should return a type in which all public declarations are either
    /// system functions or stagelabels. Each function should have a public StageLabel
    /// declaration defined right before it, associating that system to a stage.
    /// pub fn BundleSystems(comptime AppContext: type) type {
    ///     return struct {
    ///         pub const Query = Context.Query;
    ///         pub const systemALabel: StageLabel = .Update;
    ///         pub fn systemA(q: Query(.{.q = &.{Velocity, Position}})) !void {
    ///             ...
    ///         }
    ///     };
    /// }
    SystemsConstructor: fn (comptime AppContext: type) type = (struct {
        pub fn default(comptime _: type) type {
            return struct {};
        }
    }).default,

    fn getSystemsStructDeclarations(self: @This(), comptime Context: type) []const std.builtin.Type.Declaration {
        return @typeInfo(self.SystemsConstructor(Context)).@"struct".decls;
    }
    pub fn SystemIterator(comptime Context: type) type {
        return struct {
            index: usize = 0,
            bundle: Bundle,
            pub fn init(bundle: Bundle) @This() {
                return .{ .bundle = bundle };
            }
            fn checkIfStageLabel(T: type) void {
                if (T != StageLabel) {
                    @compileError("Declaration order in bundle is invalid");
                }
            }
            fn checkIfSystem(T: type) void {
                switch (@typeInfo(T)) {
                    .@"fn" => {},
                    else => @compileError("Declaration order in bundle is invalid"),
                }
            }
            fn getDeclarationType(self: @This(), decl: std.builtin.Type.Declaration) type {
                const StructType = self.bundle.SystemsConstructor(Context);
                return @TypeOf(@field(StructType, decl.name));
            }
            pub fn next(self: *@This()) ?struct { []const u8, []const u8 } {
                const Declarations = @typeInfo(self.bundle.SystemsConstructor(Context)).@"struct".decls;
                if (self.index >= Declarations.len) return null;
                const stage_label_decl = Declarations[self.index];
                const system_decl = Declarations[self.index + 1];
                checkIfStageLabel(self.getDeclarationType(stage_label_decl));
                checkIfSystem(self.getDeclarationType(system_decl));
                self.index += 2;
                return .{
                    stage_label_decl.name,
                    system_decl.name,
                };
            }
        };
    }
};

pub const BundleContext = struct {
    ComponentTypes: []const type = &.{},
    ResourceTypes: []const type = &.{},
    EventTypes: []const type = &.{},
    Bundles: []const Bundle = &.{},

    pub const Builder = struct {
        components: []const type = &.{},
        resources: []const type = &.{},
        events: []const type = &.{},
        bundles: []const Bundle = &.{},
        pub fn init() @This() {
            return .{};
        }
        pub fn addBundle(self: @This(), bundle: Bundle) @This() {
            var new = self;
            new.bundles = new.bundles ++ .{bundle};
            return new;
        }
        pub fn addBundles(self: @This(), Bundles: []const Bundle) @This() {
            var new = self;
            for (Bundles) |B| {
                new = new.addBundle(B);
            }
            return new;
        }
        pub fn addComponent(self: @This(), Component: type) @This() {
            var new = self;
            new.components = new.components ++ .{Component};
            return new;
        }
        pub fn addComponents(self: @This(), ComponentTypes: []const type) @This() {
            var new = self;
            for (ComponentTypes) |Component| {
                new = new.addComponent(Component);
            }
            return new;
        }
        pub fn addResource(self: @This(), Resource: type) @This() {
            var new = self;
            new.resources = new.resources ++ .{Resource};
            return new;
        }
        pub fn addResources(self: @This(), ResourceTypes: []const type) @This() {
            var new = self;
            for (ResourceTypes) |Resource| {
                new = new.addResource(Resource);
            }
            return new;
        }
        pub fn addEvent(self: @This(), Event: type) @This() {
            var new = self;
            new.events = new.events ++ .{Event};
            return new;
        }
        pub fn addEvents(self: @This(), EventTypes: []const type) @This() {
            var new = self;
            for (EventTypes) |Event| {
                new = new.addEvent(Event);
            }
            return new;
        }
        pub fn build(self: @This()) BundleContext {
            return .{
                .ComponentTypes = self.components,
                .ResourceTypes = self.resources,
                .EventTypes = self.events,
                .Bundles = self.bundles,
            };
        }
    };

    /// recursively merge dependency bundle context into this one
    /// we still need to keep bundles around because of their systems
    fn flattenContext(self: @This()) @This() {
        var new = self;
        const bundles = self.Bundles;
        for (bundles) |bundle| {
            new = self.merge(bundle.Context);
        }
        return new;
    }
    pub fn merge(self: @This(), other: @This()) @This() {
        const flatten_other = other.flattenContext();
        return .{
            .ComponentTypes = self.ComponentTypes ++ flatten_other.ComponentTypes,
            .ResourceTypes = self.ResourceTypes ++ flatten_other.ResourceTypes,
            .EventTypes = self.EventTypes ++ flatten_other.EventTypes,
            .Bundles = self.Bundles ++ flatten_other.Bundles,
        };
    }
};
