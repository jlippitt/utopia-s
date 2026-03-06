const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");

pub fn Lru(comptime K: type, comptime V: type) type {
    return struct {
        const Entry = struct {
            node: std.DoublyLinkedList.Node,
            key: K,
            value: V,
        };

        const MapContext = struct {
            pub fn hash(_: @This(), key: K) K {
                // Value passed in is already hashed
                return key;
            }

            pub fn eql(_: @This(), lhs: K, rhs: K) bool {
                return lhs == rhs;
            }
        };

        const Map = std.HashMapUnmanaged(K, *std.DoublyLinkedList.Node, MapContext, 50);

        const GetOrPutResult = struct {
            value_ptr: *V,
            found_existing: bool,
        };

        const Self = @This();

        map: Map,
        list: std.DoublyLinkedList,
        entries: []Entry,

        pub fn init(
            allocator: std.mem.Allocator,
            pool_size: u32,
            init_value: V,
        ) error{OutOfMemory}!Self {
            const entries = try allocator.alloc(Entry, pool_size);
            errdefer allocator.free(entries);

            // Map has twice the capacity of the texture pool to help reduce collisions
            var texture_map: Map = .empty;
            try texture_map.ensureTotalCapacity(allocator, pool_size * 2);
            errdefer texture_map.deinit(allocator);

            var lru: std.DoublyLinkedList = .{};

            for (entries) |*entry| {
                entry.value = init_value;
                lru.append(&entry.node);
            }

            return .{
                .map = texture_map,
                .list = lru,
                .entries = entries,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.map.deinit();
            allocator.free(self.entries);
        }

        pub fn getOrPut(self: *Self, key: K) GetOrPutResult {
            if (self.map.get(key)) |node| {
                const entry: *Entry = @alignCast(@fieldParentPtr("node", node));
                std.debug.assert(entry.key == key);
                self.list.remove(node);
                self.list.append(node);

                return .{
                    .value_ptr = &entry.value,
                    .found_existing = true,
                };
            }

            const node = self.list.popFirst().?;
            self.list.append(node);

            const entry: *Entry = @alignCast(@fieldParentPtr("node", node));

            _ = self.map.remove(entry.key);
            self.map.putAssumeCapacity(key, node);

            entry.key = key;

            return .{
                .value_ptr = &entry.value,
                .found_existing = false,
            };
        }
    };
}
