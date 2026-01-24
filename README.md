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
   - [ ] deal with const event -> per-(system, event) read index must be saved somewhere else
      - [ ] better code for dealing with requirements and pre/post handles of requirements in scheduler
         1. system type that calls function using proper arguments
         2. also properly initialize arguments
         3. also properly deinits arguments
         4. keep system type in enum array in scheduler
- [ ] added, changed and removed queries
- [ ] example game with raylib -> ping pong
- [ ] more unit tests
- [ ] 0.16 std.Io multithreading
