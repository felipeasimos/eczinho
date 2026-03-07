## Eczinho

Eczinho is a little archetype-style ECS built in pure Zig with a bevy-flavored API.

## Running examples

```
# pong example using raylib, W and S to move paddle. ESC to exit
zig build --build-file examples/pong/build.zig
```

# TODO

- [ ] add test scenarios to tests/
- [ ] choose storage options per-component type:
   - [ ] sparse sets (like EnTT/Bevy)
   - [ ] archetype
- [ ] choose dense storage option per archetype:
   - [ ] archetype table (like Bevy)
   - [ ] archetype chunks (like DOTS)
- [ ] bulk operations
- [ ] tracy
- [ ] move more code to comptime
   - [ ] scheduler
   - [ ] event store
   - [ ] app builder
- [ ] cache queries
- [ ] 0.16 std.Io multithreading
- [ ] core bundles
   - [ ] hierarchy
   - [ ] reflection bundle
   - [ ] spatial bundle
      - [ ] transform -> translation, rotation, scale
   - [ ] debug gui bundle
   - [ ] camera 2d bundle
   - [ ] camera 3d bundle

## Different Storage Options (not implemented yet)

* The idea is to enable the developer to choose which type of storage each component will use
   * bundle authors can define default storage option for their components
      * can always be overwritten by the final gamedev

* options: (.SparseSet, .Archetype)
   * default option: sparse sets

* it should be possible to specify which storage option each archetype will use:
   * (.Table, .Chunking)
      * default: .Table

### Archetypes 

* Overall better for components that are not added/removed with frequency
* Faster queries
* one storage type has to be choosen per archetype, in order to maintain performance guarantees of each type.
   * mixing different component storage types throughout different archetypes might not be a good idea, but its open to the developer

* scheduling: each system parallelizes first query per-archetype
   * and for each archetype, it parallelizes at the work unit level
   * remember: the other queries are given in full

#### Chunking

* Higher granualarity and compact sets of components
   * better for high core counts: can make good use of the parallelism
   * more deterministic allocation scenario
* work unit: chunk

#### Table

* Just simple component arrays for each component type inside a given archetype
   * better for low core counts: don't have to deal with the overhead of parallelism that chunking would need (and wouldn't be worth it in a low core scenario)
   * appends in the arrays can move a lot of entities potentially
* work unit: system

### Sparse Sets (per-component storage type)

Like EnTT. Great for components that are removed / added with high frequency.
