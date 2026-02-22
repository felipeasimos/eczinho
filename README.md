## Eczinho

Eczinho is a little archetype-style ECS built in pure Zig with a bevy-flavored API.

## Running examples

```
# pong example using raylib, W and S to move paddle. ESC to exit
zig build --build-file examples/pong/build.zig
```


# TODO

- [ ] bundles
- [ ] chunks
- [ ] zbench
- [ ] move more code to comptime
   - [ ] scheduler
   - [ ] event store
   - [ ] app builder
- [ ] cache queries
- [ ] hierarchy
- [ ] 0.16 std.Io multithreading
