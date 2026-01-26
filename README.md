## Roadmap

- [x] paged sparse set
- [x] archetype with comptime types
- [x] optimize for zero-width types
- [x] bitset component type id iterator
- [x] components: integer increment id for each component
- [x] systems
- [x] more tests
- [x] resources
- [ ] event
   - [ ] update reader indices after swap
      - [ ] event store needs access to event reader runtime data
      - [ ] system request event reader runtime data from event store
      1. system requests new event reader from event store (an index is given)
      2. event reader init() takes event reader persistent data as index
      3. this index is given as an argument to read functions
   - [ ] per-system event data
- [ ] added, changed and removed queries
- [ ] cache queries
- [ ] hierarchy
- [ ] bundles
   - [ ] reflection bundle
   - [ ] spatial bundle
      - [ ] transform -> translation, rotation, scale
      - [ ] 
   - [ ] debug gui bundle
   - [ ] camera 2d bundle
   - [ ] camera 3d bundle
- [ ] example game with raylib -> ping pong
- [ ] more unit tests
- [ ] move more code to comptime
   - [ ] scheduler
   - [ ] event store
   - [ ] app builder
- [ ] 0.16 std.Io multithreading
