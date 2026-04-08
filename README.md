## Eczinho

Eczinho is a little hybrid ECS built in pure Zig with a bevy-flavored API.

* Features:
   * customization without runtime overhead, thanks to zig's comptime
   * closed-universe component set, without getting in the way of creating and using bundles
   * optional metadata tracking (Added/Changed/Remove) for queries. Only pay for what you use!


## Running examples

```
# pong example using raylib, W and S to move paddle. ESC to exit
zig build --build-file examples/pong/build.zig
```

## Implementation goals and bevy comparison

- [x] closed-universe component design
   * all components are known at comptime for the final app
- [x] bundling!
   * Even though the component universe is closed, bundling is possible by merging bundle's universes and defining them through functions for dependency injection of the final app context
- [ ] optional per-archetype dense storage strategy (Chunking or Table) (bevy currently doesn't have!)
   * will use runtime interfaces for dense storage structs (another level of indirection)
   * define specific dense signatures that should use an specific strategy
      * will change which struct is initialized during dense storage creation
   * set a default (for example, Table storage) and define a list of dense signatures that would use another
- [x] adding/removing sparse components doesn't move dense components
   * changes entity's archetype (with proper signature), but the archetype data will be pointing to the same data
- [x] opt-in addition / removal / changed tracking for certain components (bevy currently doesn't have)
   * don't pay for what you don't use!
   * don't worry about it being off by default! Queries that use metadata for components without it will show a helpful compile error message to remind you!
- [ ] multithreading & scheduling
   * with chunking: work unit is each chunk (better for high cpu counts!)
   * with table and sparse sets storage: work unit is systems
   * scheduling strategy resolved at comptime
      * optinal optimizations at runtime using run data? (idk)
- [ ] conditional systems
   * only run if query is not empty
- [ ] optional world logging
- [ ] system explicit ordering
- [ ] hooks
- [ ] bulk operations
- [ ] time and delta time (bundle)
- [ ] storage options
   * chunk size (16KB)
      * metadata is kept separately
   * compactation chunk strategy:
      * add to `free_list` when empty
      * on removal, distribute remanining entities in the chunk if the chunk is below a certain threshold
   * sparse set page size

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


## High performance + closed universe component set + customization - LSP Support

> A good architect maximizes the number of decisions not made. _Clean Architecture, Robert C. Martin_

I just had to add this quote somewhere in the README. When developing something focused on performance, indirections are something to always look out for. Zig allows this codebase to abstract so much without dealing with runtime overhead because of it. `fn NewType(comptime options: anytype) type` may be the enemy of LSP support in the user-facing API, but it is really feels worth it.
