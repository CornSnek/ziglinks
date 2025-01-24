const std = @import("std");
pub const os_tag = @import("builtin").os.tag;
pub const arch = @import("builtin").cpu.arch;
pub const endl: []const u8 = if (os_tag == .windows) "\r\n" else "\n";
pub const sl: u8 = if (os_tag != .windows) '/' else '\\';
pub const sl_str: []const u8 = if (os_tag != .windows) "/" else "\\";
//The binary names (Not symlink names) of zig and zls
pub const zig_bin: []const u8 = if (os_tag != .windows) "zig" else "zig.exe";
pub const zls_bin: []const u8 = if (os_tag != .windows) "zls" else "zls.exe";
//To keep track symlinks and zig/zls versions that have been added in the symlinks folder.
pub const symlinks_ini: []const u8 = "~symlinks.ini";
/// Comptime ANSI escape codes wrapping a string. Escape codes are tuples of u8.
pub fn ANSI(comptime str: []const u8, comptime esc_codes: anytype) []const u8 {
    var return_str: []const u8 = "\x1b[";
    for (0..esc_codes.len) |i| {
        const u8_str = std.fmt.comptimePrint("{}", .{esc_codes[i]});
        return_str = return_str ++ u8_str ++ if (i != esc_codes.len - 1) ";" else "m";
    }
    return_str = return_str ++ str ++ "\x1b[0m";
    return return_str;
}
/// Just a wrapper around std.process.argsAlloc, adding .peek() to not increment the counter and .discard() to discard the next argument.
pub const ArgsIterator = struct {
    it_arr: [][:0]u8,
    it_i: usize = 0,
    pub fn init(allocator: std.mem.Allocator) !ArgsIterator {
        return .{ .it_arr = try std.process.argsAlloc(allocator) };
    }
    pub fn next(self: *ArgsIterator) ?[]const u8 {
        if (self.it_i < self.it_arr.len) {
            const str = self.it_arr[self.it_i];
            self.it_i += 1;
            return str;
        } else return null;
    }
    pub fn discard(self: *ArgsIterator) void {
        if (self.it_i < self.it_arr.len) self.it_i += 1;
    }
    pub fn peek(self: ArgsIterator) ?[]const u8 {
        return if (self.it_i < self.it_arr.len) self.it_arr[self.it_i] else null;
    }
    pub fn deinit(self: ArgsIterator, allocator: std.mem.Allocator) void {
        std.process.argsFree(allocator, self.it_arr);
    }
};
pub fn optional_str_eql(s1: ?[]const u8, s2: ?[]const u8) bool {
    return if (s1 == null and s2 == null) true else if (s1 != null and s2 != null) std.mem.eql(u8, s1.?, s2.?) else false;
}

const PathType = enum { file, dir };
/// Makes a comptime string that appends '/' or '\\' for each word in dirs.
/// Example: as_file_path(.{"a","bc","def"},.dir) would output "a/bc/def/" or "a\\bc\\def\\"
pub fn as_os_path(comptime dirs: anytype, comptime path_type: PathType) []const u8 {
    var return_str: []const u8 = &.{};
    for (dirs, 0..) |dir, i| {
        return_str = return_str ++ dir;
        if (i != dirs.len - 1) {
            return_str = return_str ++ sl_str;
        } else {
            if (path_type == .dir) {
                return_str = return_str ++ sl_str;
            }
        }
    }
    return return_str;
}
pub fn allowed_as_filename(str: []const u8) bool {
    for (str) |c| {
        switch (c) {
            else => return false,
            'a'...'z', 'A'...'Z', '0'...'9', '.', '+', '-', '_', ' ' => {},
        }
    }
    return true;
}
pub fn os_to_program_str(os: std.Target.Os.Tag) ?[]const u8 {
    return switch (os) {
        .windows => "Windows",
        .linux => "Linux",
        .macos => "MacOS",
        else => null,
    };
}
