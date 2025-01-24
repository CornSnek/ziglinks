const std = @import("std");
const utilities = @import("utilities.zig");
const ANSI = utilities.ANSI;
const endl = utilities.endl;
const Options = @import("Options.zig");
const ini_reader = @import("ini_reader.zig");
const keys_map = @import("keys_map.zig");
const OptionsVariables = Options.OptionsVariables;
pub const Parser = struct {
    /// Each section has more keys.
    pub const VersionsHashMap = std.StringHashMapUnmanaged([]const u8);
    const Context = struct {
        pub fn hash(_: Context, K: ?[]const u8) u64 {
            return if (K) |k| std.hash.Wyhash.hash(0, k) else 0;
        }
        pub fn eql(_: Context, K1: ?[]const u8, K2: ?[]const u8) bool {
            return utilities.optional_str_eql(K1, K2);
        }
    };
    ini_hm: std.HashMapUnmanaged(?[]const u8, VersionsHashMap, Context, 80) = .{},
    /// Get keys and values for each version section. Parser should initially be undefined before calling this.
    pub fn init(self: *Parser, allocator: std.mem.Allocator, ov: OptionsVariables) !void {
        const stderr = std.io.getStdErr().writer();
        const ini_file = try std.fs.cwd().openFile(ov.ini_file, .{});
        defer ini_file.close();
        self.* = Parser{};
        var last_section_maybe: ?[]const u8 = null;
        var last_section_used: bool = false;
        defer if (!last_section_used and last_section_maybe != null) allocator.free(last_section_maybe.?);
        var lexer = try ini_reader.IniLexerFile.init(std.fs.cwd(), ov.ini_file, .{});
        defer lexer.deinit(allocator);
        while (lexer.next(allocator)) |token_op| {
            if (token_op) |token| {
                switch (token.value) {
                    .section => |s| {
                        if (!last_section_used and last_section_maybe != null) allocator.free(last_section_maybe.?);
                        last_section_used = false;
                        last_section_maybe = s;
                    },
                    .key => |k| {
                        errdefer allocator.free(k);
                        const value_t = try lexer.next(allocator) orelse unreachable;
                        errdefer value_t.deinit(allocator);
                        if (!keys_map.Keys.has(k))
                            try stderr.print(ANSI("Parser: '{s}' is not used as a key. Please check --keys for the correct spelling or valid keys." ++ endl, .{ 1, 33 }), .{k});
                        last_section_used = true;
                        const gop = try self.ini_hm.getOrPut(allocator, last_section_maybe);
                        var hm: *Parser.VersionsHashMap = gop.value_ptr;
                        errdefer hm.deinit(allocator);
                        if (!gop.found_existing) hm.* = .{};
                        const nested_hm_gop = try hm.getOrPut(allocator, k);
                        if (nested_hm_gop.found_existing) {
                            try stderr.print(ANSI("Parser: '{s}' already exists for the section [{s}], and its value will be overridden from '{s}' to '{s}'" ++ endl, .{ 1, 33 }), .{
                                k,
                                last_section_maybe orelse "(global)",
                                nested_hm_gop.value_ptr.*,
                                value_t.value.value.str,
                            });
                            allocator.free(k);
                            allocator.free(nested_hm_gop.value_ptr.*);
                            nested_hm_gop.value_ptr.* = value_t.value.value.str;
                        } else {
                            nested_hm_gop.value_ptr.* = value_t.value.value.str;
                        }
                    },
                    .value => unreachable,
                    else => token.deinit(allocator),
                }
            } else break;
        } else |e| return e;
    }
    pub fn get_os_vhm(self: Parser) ?*const Parser.VersionsHashMap {
        return switch (@import("builtin").os.tag) {
            .windows => self.ini_hm.getPtr("!Windows"),
            .linux => self.ini_hm.getPtr("!Linux"),
            .macos => self.ini_hm.getPtr("!MacOS"),
            else => return null,
        };
    }
    pub fn get_combined(self: Parser, version: []const u8) !CombinedHashMap {
        return .{
            .global_vhm = self.ini_hm.getPtr(null),
            .os_vhm = self.get_os_vhm(),
            .version_vhm = self.ini_hm.getPtr(version) orelse return error.InvalidVersionString,
        };
    }
    pub fn deinit(self: *Parser, allocator: std.mem.Allocator) void {
        var self_it = self.ini_hm.iterator();
        while (self_it.next()) |kvp| {
            //Free section string
            if (kvp.key_ptr.*) |v| allocator.free(v);
            var nested_hm_it = kvp.value_ptr.iterator();
            //Free the nested StringHashMap (kvp.value_ptr.*) keys/values, and deinit the StringHashMap.
            while (nested_hm_it.next()) |kvp2| {
                allocator.free(kvp2.key_ptr.*);
                allocator.free(kvp2.value_ptr.*);
            }
            kvp.value_ptr.deinit(allocator);
        }
        self.ini_hm.deinit(allocator);
    }
};
/// Get the string value from the version_vhm, os_vhm, global_vhm, and default key's value in that order.
pub const CombinedHashMap = struct {
    global_vhm: ?*const Parser.VersionsHashMap,
    os_vhm: ?*const Parser.VersionsHashMap,
    version_vhm: *const Parser.VersionsHashMap,
    pub fn get(self: @This(), key: []const u8) ?[]const u8 {
        if (self.version_vhm.get(key)) |v| {
            return v;
        } else if (self.os_vhm != null and self.os_vhm.?.get(key) != null) {
            return self.os_vhm.?.get(key);
        } else if (self.global_vhm != null and self.global_vhm.?.get(key) != null) {
            return self.global_vhm.?.get(key);
        } else if (keys_map.Keys.StrToEnum.get(key)) |e| {
            return keys_map.Keys.Info[@intFromEnum(e)].default;
        } else return null;
    }
    pub fn get_all(self: @This(), allocator: std.mem.Allocator) !Parser.VersionsHashMap {
        var vhm: Parser.VersionsHashMap = .{};
        errdefer vhm.deinit(allocator);
        if (self.global_vhm) |gvhm| {
            var global_vhm_it = gvhm.iterator();
            while (global_vhm_it.next()) |kv|
                try vhm.put(allocator, kv.key_ptr.*, kv.value_ptr.*);
        }
        if (self.os_vhm) |ovhm| {
            var os_vhm_it = ovhm.iterator();
            while (os_vhm_it.next()) |kv|
                try vhm.put(allocator, kv.key_ptr.*, kv.value_ptr.*);
        }
        var v_vhm_it = self.version_vhm.iterator();
        while (v_vhm_it.next()) |kv|
            try vhm.put(allocator, kv.key_ptr.*, kv.value_ptr.*);
        return vhm;
    }
};
