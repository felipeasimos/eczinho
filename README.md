## Roadmap

- [x] paged sparse set
- [x] archetype with comptime types
- [x] optimize for zero-width types
- [x] bitset component type id iterator
- [x] components: integer increment id for each component
- [ ] app
   - [x] app builder
   - [ ] systems
      - [ ] query
         - [ ] with
         - [ ] without
         - [ ] optional
         - [ ] changed -> component changed tick and system run tick
         - [ ] added -> component added tick and system run tick
         - [ ] removed -> component removed tick and system run tick
      - [ ] Scheduler
         - [x] call init query with requirements from system
      - [x] Commands queue
