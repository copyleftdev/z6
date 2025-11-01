---
trigger: always_on
description: "Enforce Tiger Style philosophy: determinism, safety, zero technical debt"
globs: ["*.zig"]
---

# Tiger Style Coding Rules for Z6

## Core Philosophy
<tiger_principles>
- **Simplicity over complexity** - The simple and elegant solution is easier to verify
- **Do it right the first time** - Zero technical debt policy
- **Test before implement** - Write failing tests, then make them pass
- **Fail fast** - Assertions downgrade catastrophness into liveness bugs
- **Explicit over implicit** - No hidden state, no magic
</tiger_principles>

## Assertions (MANDATORY)

<assertion_rules>
- **Minimum 2 assertions per function** - Non-negotiable requirement
- Assert all function arguments (preconditions)
- Assert all return values (postconditions)
- Assert all invariants throughout function execution
- Pair assertions: contract requires both caller and callee assertions
- Example pattern:
  ```zig
  fn process(data: []const u8) !Result {
      assert(data.len > 0); // precondition
      assert(data.len <= MAX_SIZE); // bound check
      
      const result = try compute(data);
      
      assert(result.isValid()); // postcondition
      assert(result.size <= data.len); // invariant
      return result;
  }
  ```
</assertion_rules>

## Control Flow & Loops

<control_flow_rules>
- **All loops MUST be bounded** - No unbounded while(true) without assertion
- Use simple, explicit control flow only
- **NO recursion** - All executions must be provably bounded
- For event loops (while true), immediately follow with unreachable/assert:
  ```zig
  while (true) {
      // event loop body
  }
  unreachable; // or assert(false, "event loop terminated");
  ```
- Prefer for loops with explicit iteration counts
- Break conditions must be obvious and deterministic
</control_flow_rules>

## Error Handling

<error_handling_rules>
- **All errors MUST be explicit** - No silent failures
- **NEVER use `catch {}`** - Silent error suppression is forbidden
- Always handle or propagate errors:
  ```zig
  // FORBIDDEN
  something() catch {}; 
  
  // REQUIRED
  something() catch |err| {
      log.err("Failed to do something: {}", .{err});
      return error.OperationFailed;
  };
  ```
- Use `try` to propagate errors up the call stack
- Document all error cases in function comments
- Error types must be specific, not generic
</error_handling_rules>

## Memory Management

<memory_rules>
- **All allocations must be bounded** - No unbounded growth
- Document memory ownership explicitly
- Pair allocations with deallocations in same scope when possible
- Use defer for cleanup immediately after allocation:
  ```zig
  const buffer = try allocator.alloc(u8, size);
  defer allocator.free(buffer);
  ```
- **No hidden allocations** - All allocations must be explicit
- Check allocation results - never assume success
- Specify maximum memory limits for all data structures
</memory_rules>

## Types & Data

<type_rules>
- **Use explicit sized types** - `u32`, `i64`, etc. (avoid `usize` unless necessary)
- All structs should have explicit field sizes
- Avoid architecture-dependent types
- Document memory layout for packed structs
- Use compile-time known sizes wherever possible
</type_rules>

## Functions

<function_rules>
- Functions must increase probability of correctness
- Single responsibility - one clear purpose per function
- Input validation via assertions
- Output validation via assertions
- Keep functions small and testable
- Pure functions when possible (no side effects)
- Document preconditions, postconditions, and invariants
</function_rules>

## Concurrency & Determinism

<determinism_rules>
- **Single-threaded by design** for Z6 core
- Logical ticks, not wall-clock time
- All operations must be deterministic given same seed
- No system calls that introduce non-determinism in core logic
- PRNG must be seeded explicitly
- Document any potential non-deterministic behavior
</determinism_rules>

## Code Style

<style_rules>
- Use `zig fmt` - formatting must be consistent
- Descriptive variable names (no single letters except loop counters)
- Comments explain WHY, not WHAT
- Group related functionality
- Explicit is better than clever
- No magic numbers - use named constants
</style_rules>

## Testing

<testing_rules>
- **Write tests BEFORE implementation** - TDD is mandatory
- Minimum 90% test coverage
- Test happy path AND error paths
- Test boundary conditions
- Property-based tests for complex logic
- Fuzz tests for all parsers (minimum 1M inputs)
</testing_rules>

## Documentation

<documentation_rules>
- All public functions must have doc comments
- Explain preconditions and postconditions
- Document error conditions
- Provide usage examples for complex APIs
- Keep docs in sync with code
</documentation_rules>

## Forbidden Practices

<forbidden>
- ❌ `catch {}` - Silent error suppression
- ❌ `while (true)` without unreachable/assert after
- ❌ Recursion
- ❌ Unbounded loops
- ❌ Unbounded allocations
- ❌ Functions with < 2 assertions
- ❌ Magic numbers
- ❌ Architecture-dependent behavior
- ❌ Hidden state or global mutable state
- ❌ Implicit allocations
- ❌ Technical debt of any kind
</forbidden>

## Before Committing

<pre_commit_checklist>
- [ ] All functions have minimum 2 assertions
- [ ] All loops are provably bounded
- [ ] No silent error handling
- [ ] Code formatted with `zig fmt`
- [ ] All tests pass
- [ ] No TODO comments (or tracked in issues)
- [ ] Documentation updated
- [ ] Memory bounds specified
</pre_commit_checklist>

---

**Remember:** Tiger Style is about precision engineering. Code must be correct, auditable, and maintainable. If in doubt, make it simpler and more explicit.