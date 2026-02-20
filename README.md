## Eczinho

Eczinho is a little archetype-style ECS built in pure Zig with a bevy-flavored API.

## Running examples

```
# pong example using raylib, W and S to move paddle. ESC to exit
zig build --build-file examples/pong/build.zig
```


# TODO

- [ ] zbench
- [ ] more tests as example in source files
- [ ] more test files
- [ ] bundles
   - [ ] reflection bundle
   - [ ] spatial bundle
      - [ ] transform -> translation, rotation, scale
   - [ ] debug gui bundle
   - [ ] camera 2d bundle
   - [ ] camera 3d bundle
- [ ] more unit tests
- [ ] move more code to comptime
   - [ ] scheduler
   - [ ] event store
   - [ ] app builder
- [ ] cache queries
- [ ] hierarchy
- [ ] 0.16 std.Io multithreading
