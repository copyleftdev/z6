# Z6 Memory Model

> "Memory is a first-class citizen. Every allocation is explicit, measurable, and bounded."

## Philosophy

In Z6, memory behavior is **never a surprise**. Unpredictable memory usage makes latency measurements meaningless. Therefore:

1. **All allocations are explicit** — No hidden allocations
2. **All allocations are bounded** — No unbounded growth
3. **All allocations are measured** — Memory usage is observable
4. **No garbage collection** — No GC pauses distorting measurements

## Memory Budget

Z6 pre-allocates all memory at initialization. The total memory budget is:

```
Total Memory = Stack + VU Pool + Protocol Handlers + Event Log + I/O Buffers
```

Default configuration:

| Component | Size | Notes |
|-----------|------|-------|
| Stack | 1 MB | Scenario, config, scheduler state |
| VU Pool | VUs × 64 KB | Per-VU state |
| Protocol Handlers | 16 MB | Connection pools, buffers |
| Event Log | 2.5 GB | Ring buffer for events |
| I/O Buffers | 64 MB | Temporary network buffers |
| **Total** | **~2.6 GB** | For 1,000 VUs |

## Allocation Strategy

### Arena Allocation

Most memory is allocated from **arenas** (bump allocators):

```zig
const Arena = struct {
    buffer: []u8,
    offset: usize,
    
    fn alloc(arena: *Arena, size: usize) ![]u8 {
        if (arena.offset + size > arena.buffer.len) {
            return error.OutOfMemory;
        }
        const ptr = arena.buffer[arena.offset..][0..size];
        arena.offset += size;
        return ptr;
    }
    
    fn reset(arena: *Arena) void {
        arena.offset = 0;
    }
};
```

Arenas are used for:

- Scenario parsing
- VU state initialization
- Temporary data structures

Arenas are **reset** between test runs, never freed.

### Pool Allocation

Frequently allocated/deallocated objects use **object pools**:

```zig
fn ObjectPool(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        
        objects: [capacity]T,
        free_list: [capacity]u32,
        free_count: u32,
        
        fn acquire(pool: *Self) !*T {
            if (pool.free_count == 0) return error.PoolExhausted;
            pool.free_count -= 1;
            const index = pool.free_list[pool.free_count];
            return &pool.objects[index];
        }
        
        fn release(pool: *Self, obj: *T) void {
            const index = (@intFromPtr(obj) - @intFromPtr(&pool.objects[0])) / @sizeOf(T);
            pool.free_list[pool.free_count] = @intCast(index);
            pool.free_count += 1;
        }
    };
}
```

Pools are used for:

- Request contexts
- Connection objects
- I/O buffers

Pools have **fixed capacity**. Exhaustion triggers backpressure.

### Stack Allocation

Small, short-lived objects use **stack allocation**:

```zig
fn process_response(response: Response) !void {
    // Stack-allocated buffer
    var header_buf: [4096]u8 = undefined;
    
    // Use buffer...
    const headers = try parse_headers(response, &header_buf);
    
    // Buffer automatically freed when function returns
}
```

Stack allocation is:

- **Zero overhead** — No allocator calls
- **Deterministic** — No fragmentation
- **Fast** — Pointer bump, no bookkeeping

### No Heap Allocation

Z6 **never** calls `malloc`/`free` during the hot path. All memory is:

- Pre-allocated at initialization
- Reused from pools
- Allocated on stack

## Memory Layout

### Per-VU Memory

Each VU owns a fixed 64 KB memory region:

```
┌─────────────────────────────────────┐
│ VU State (256 bytes)                │
│ - id, state, scenario_step, etc.    │
├─────────────────────────────────────┤
│ Connection Pool (16 KB)             │
│ - Pointers to connections           │
├─────────────────────────────────────┤
│ Request/Response Buffers (32 KB)    │
│ - Temporary HTTP buffers            │
├─────────────────────────────────────┤
│ Variable Storage (16 KB)            │
│ - Scenario variables (future)       │
└─────────────────────────────────────┘
```

Total: **65,536 bytes per VU**

For 100,000 VUs: **6.4 GB**

### Event Log Memory

The event log is a **ring buffer**:

```zig
const EventLog = struct {
    buffer: []Event,
    head: u32,  // Next write position
    tail: u32,  // Next flush position
    
    fn append(log: *EventLog, event: Event) !void {
        if (log.is_full()) return error.LogFull;
        
        log.buffer[log.head] = event;
        log.head = (log.head + 1) % @intCast(log.buffer.len);
    }
    
    fn is_full(log: *EventLog) bool {
        return (log.head + 1) % @intCast(log.buffer.len) == log.tail;
    }
};
```

Size calculation:

```
Event Size = 272 bytes
Max Events = 10 million
Log Size = 272 × 10,000,000 = 2.72 GB
```

When the ring buffer fills:

1. **Flush tail to disk**
2. **Advance tail pointer**
3. **Continue appending**

If flush can't keep up, test **aborts**.

### Protocol Handler Memory

Protocol handlers own:

```
┌─────────────────────────────────────┐
│ Connection Pool                     │
│ - Max 10,000 connections            │
│ - 512 bytes per connection          │
│ - Total: 5 MB                       │
├─────────────────────────────────────┤
│ Send Buffers                        │
│ - 1,000 buffers × 8 KB              │
│ - Total: 8 MB                       │
├─────────────────────────────────────┤
│ Recv Buffers                        │
│ - 1,000 buffers × 8 KB              │
│ - Total: 8 MB                       │
└─────────────────────────────────────┘
```

Total: **~21 MB**

## Zero-Copy Paths

Where possible, Z6 avoids copying data:

### Request Sending

```zig
// BAD: Copy request body to send buffer
var send_buf: [8192]u8 = undefined;
@memcpy(&send_buf, request.body);
try socket.send(&send_buf);

// GOOD: Send directly from request body
try socket.send(request.body);
```

### Response Receiving

```zig
// BAD: Copy from recv buffer to response
var recv_buf: [8192]u8 = undefined;
const n = try socket.recv(&recv_buf);
response.body = try allocator.dupe(u8, recv_buf[0..n]);

// GOOD: Receive directly into response buffer
response.body = try socket.recv_into(response.body_buffer);
```

Zero-copy reduces:

- Memory bandwidth usage
- Cache pollution
- Latency spikes

## Memory Alignment

All structures are **cache-line aligned** to avoid false sharing:

```zig
const CacheLineSize = 64;

const VU = struct {
    id: u32,
    state: VUState,
    // ... fields ...
} align(CacheLineSize);

const Event = struct {
    header: EventHeader,
    payload: [240]u8,
    checksum: u64,
} align(CacheLineSize);
```

This ensures:

- Each VU in its own cache line
- Each event in its own cache line
- No false sharing between cores (if multi-threaded in future)

## Memory Measurement

Z6 tracks memory usage:

```zig
const MemoryStats = struct {
    vus_allocated: usize,
    event_log_used: usize,
    protocol_handler_used: usize,
    total_allocated: usize,
    peak_usage: usize,
};
```

Memory stats are reported post-run:

```
Memory Usage:
  VUs: 6.4 GB (100,000 VUs × 64 KB)
  Event Log: 2.1 GB (7.8M events)
  Protocol Handlers: 21 MB
  Total: 8.5 GB
  Peak: 8.5 GB
```

## Out-of-Memory Handling

Z6 **fails fast** on OOM:

```zig
fn allocate_vus(count: u32) ![]VU {
    const size = count * @sizeOf(VU);
    
    if (size > MAX_VU_MEMORY) {
        std.log.err("VU count {d} exceeds memory budget", .{count});
        return error.MemoryBudgetExceeded;
    }
    
    return try allocator.alloc(VU, count);
}
```

No fallback, no swapping, no degradation. **Fail fast and loud.**

## Memory Safety

Z6 uses Zig's compile-time safety:

### Bounds Checking

```zig
// Compile-time check
const buffer: [1024]u8 = undefined;
const slice = buffer[0..512];  // OK
// const invalid = buffer[0..2000];  // Compile error

// Runtime check (in safe mode)
const index: usize = get_index();
const value = buffer[index];  // Panics if index >= 1024
```

### Use-After-Free Prevention

```zig
// Arenas prevent use-after-free
var arena = Arena.init(allocator);
defer arena.deinit();  // All allocations freed together

const obj = try arena.alloc(MyStruct);
// Use obj...
// arena.deinit() prevents further use
```

### No Null Pointers

```zig
// Optional types make nullability explicit
const maybe_value: ?*VU = find_vu(id);
if (maybe_value) |vu| {
    // vu is guaranteed non-null
    process_vu(vu);
}
```

## Memory Budget Calculation

To calculate memory requirements for a scenario:

```
VU_Memory = VU_count × 64 KB

Event_Memory = VU_count × requests_per_VU × 272 bytes × 2
               (2× for request + response events)

Protocol_Memory = 21 MB (fixed)

Total = VU_Memory + Event_Memory + Protocol_Memory
```

Example: 10,000 VUs, 100 requests each

```
VU_Memory = 10,000 × 64 KB = 640 MB
Event_Memory = 10,000 × 100 × 272 × 2 = 544 MB
Protocol_Memory = 21 MB
Total = 1.2 GB
```

## Comparison to Other Systems

| System | Allocation Strategy | Z6 Difference |
|--------|---------------------|---------------|
| K6 | Go GC (pauses) | No GC, pre-allocated |
| Locust | Python GC (slow) | No GC, explicit memory |
| Gatling | JVM GC (tunable) | No GC, deterministic |
| wrk2 | malloc/free | Pools and arenas |

## Memory Configuration

Configurable memory parameters:

```zig
const MemoryConfig = struct {
    max_vus: u32 = 100_000,
    vu_memory_kb: u32 = 64,
    event_log_capacity: u32 = 10_000_000,
    connection_pool_size: u32 = 10_000,
    io_buffer_count: u32 = 1_000,
    io_buffer_size_kb: u32 = 8,
};
```

Memory validation at startup:

```zig
fn validate_config(config: MemoryConfig) !void {
    const total_memory = calculate_memory_budget(config);
    const available_memory = get_system_memory();
    
    if (total_memory > available_memory * 0.8) {
        return error.InsufficientMemory;
    }
}
```

Z6 refuses to start if memory budget exceeds 80% of system memory.

## Future Optimizations

Potential memory improvements (post-v1):

### HUGE Pages

Use 2MB pages for VU pool:

- Reduces TLB misses
- Improves cache efficiency
- Requires root privileges

### NUMA Awareness

Allocate memory on same NUMA node as executing core:

- Reduces memory access latency
- Complex for single-threaded model

### Compression

Compress event log in-flight:

- Reduces memory usage
- Adds CPU overhead
- Must not affect determinism

All optimizations must be **measured** and **validated**.

---

## Summary

Z6's memory model is simple:

- Pre-allocate everything
- Use pools and arenas
- No GC pauses
- Fail fast on OOM

This makes memory behavior **predictable**, which is essential for accurate latency measurement.

---

**Version 1.0 — October 2025**
