const std = @import("std");
const utilities = @import("utilities.zig");
const ANSI = utilities.ANSI;
const endl = utilities.endl;
const os_tag = utilities.os_tag;
const arch = utilities.arch;
const sl_str = utilities.sl_str;
const os_to_program_str = utilities.os_to_program_str;
const Options = @import("Options.zig");
const ini_reader = @import("ini_reader.zig");
const Keys = @import("keys_map.zig").Keys;
pub fn get_master(self: *Options, _: []const u8) anyerror!?u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    try stdout.writeAll(comptime ANSI("Downloading data from https://ziglang.org/download/index.json...\n", .{ 1, 34 }));
    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();
    var json_arr = std.ArrayList(u8).init(self.allocator);
    defer json_arr.deinit();
    const res = try client.fetch(.{
        .location = .{ .url = "https://ziglang.org/download/index.json" },
        .response_storage = .{ .dynamic = &json_arr },
        .method = .GET,
        .keep_alive = false,
    });
    if (res.status == .ok) {
        var scanner: std.json.Scanner = std.json.Scanner.initStreaming(self.allocator);
        defer scanner.deinit();
        scanner.feedInput(json_arr.items);
        scanner.endInput();
        while (scanner.next()) |t| {
            if (t == .string) {
                if (std.mem.eql(u8, t.string, "master")) {
                    std.debug.assert((scanner.next() catch unreachable) == .object_begin);
                    break;
                }
            }
            if (t == .end_of_document) {
                try stderr.writeAll(comptime ANSI("Unable to find the \"master.version\" key" ++ endl, .{ 1, 31 }));
                return 1;
            }
        } else |e| return e;
        var obj_depth: usize = 0;
        var master_filename: ?[]const u8 = null;
        var master_link: ?[]const u8 = null;
        //Extract master key's "version" and each "tarball" links for this os
        while (scanner.next()) |t| {
            if (t == .string) {
                if (std.mem.eql(u8, t.string, "version")) {
                    const version_v = scanner.next() catch unreachable;
                    std.debug.assert(version_v == .string);
                    master_filename = version_v.string;
                }
                if (obj_depth == 0) { //Extract subkey values of the proper arch and os
                    if (std.mem.indexOf(u8, t.string, @tagName(arch)) != null and std.mem.indexOf(u8, t.string, @tagName(os_tag)) != null) {
                        std.debug.assert(scanner.next() catch unreachable == .object_begin);
                        var obj_depth2: usize = 0;
                        while (scanner.next()) |t2| { //Extract the "tarball" value string
                            if (t2 == .string) {
                                if (std.mem.eql(u8, t2.string, "tarball")) {
                                    const tarball_v = scanner.next() catch unreachable;
                                    std.debug.assert(tarball_v == .string);
                                    master_link = tarball_v.string;
                                }
                            }
                            if (t2 == .object_begin) obj_depth2 += 1;
                            if (t2 == .object_end) {
                                if (obj_depth2 == 0) break;
                                obj_depth2 -= 1;
                            }
                        } else |e| return e;
                    }
                }
            }
            if (t == .object_begin) obj_depth += 1;
            if (t == .object_end) {
                if (obj_depth == 0) break;
                obj_depth -= 1;
            }
        } else |e| return e;
        if (master_link == null) {
            try stderr.print(
                ANSI("https://ziglang.org/download/index.json does not have a link to a master version for your os ({s}) and arch ({s})" ++ endl, .{ 1, 31 }),
                .{ @tagName(os_tag), @tagName(arch) },
            );
            return 1;
        }
        try stdout.print(ANSI("Found version '{s}' with link '{s}'. Attempting to save information to the {s} file." ++ endl, .{ 1, 33 }), .{ master_filename.?, master_link.?, self.ov.ini_file });
        var ini_save: ini_reader.IniSave = .{};
        defer ini_save.deinit(self.allocator);
        var lexer = try ini_reader.IniLexerFile.init(std.fs.cwd(), self.ov.ini_file, .{});
        defer lexer.deinit(self.allocator);
        while (lexer.next(self.allocator)) |t_op| { //Don't write if the master version right now already exists as a string
            if (t_op) |t| {
                switch (t.value) {
                    .section => |s| {
                        try ini_save.tokens.append(self.allocator, t);
                        if (std.mem.eql(u8, s, master_filename.?)) {
                            try stdout.print(ANSI("Warning: Masterversion '{s}' has already been found in the {s} file. Did not save." ++ endl, .{ 1, 33 }), .{ master_filename.?, self.ov.ini_file });
                            return 0;
                        }
                    },
                    else => try ini_save.tokens.append(self.allocator, t),
                }
            } else break;
        } else |e| return e;
        if (ini_save.tokens.getLast().value != .newline) try ini_save.tokens.append(self.allocator, .{ .alloc = false, .value = .newline });
        try ini_save.tokens.appendSlice(self.allocator, &[_]ini_reader.Token{
            .{ .alloc = false, .value = .{ .section = master_filename.? } },
            .{ .alloc = false, .value = .newline },
            .{ .alloc = false, .value = .{ .key = Keys.OSType.str() } },
            .{ .alloc = false, .value = .{ .value = .{ .str = os_to_program_str(os_tag).? } } },
            .{ .alloc = false, .value = .newline },
            .{ .alloc = false, .value = .{ .key = Keys.UsesZlsDownload.str() } },
            .{ .alloc = false, .value = .{ .value = .{ .str = "false" } } },
            .{ .alloc = false, .value = .{ .comment = "You have to manually build ZLS as there are no links for master versions" } },
            .{ .alloc = false, .value = .newline },
            .{ .alloc = false, .value = .{ .key = Keys.RequiresDownload.str() } },
            .{ .alloc = false, .value = .{ .value = .{ .str = "true" } } },
            .{ .alloc = false, .value = .newline },
            .{ .alloc = false, .value = .{ .key = Keys.ZigDownload.str() } },
            .{ .alloc = false, .value = .{ .value = .{ .str = master_link.? } } },
            .{ .alloc = false, .value = .newline },
            .{ .alloc = false, .value = .{ .key = Keys.ZigFolder.str() } },
            .{ .alloc = false, .value = .{ .value = .{ .str = Keys.Info[@intFromEnum(Keys.ZigFolder)].default.? } } },
            .{ .alloc = false, .value = .newline },
            .{ .alloc = false, .value = .{ .key = Keys.ZlsFolder.str() } },
            .{ .alloc = false, .value = .{ .value = .{ .str = Keys.Info[@intFromEnum(Keys.ZlsFolder)].default.? } } },
            .{ .alloc = false, .value = .newline },
        });
        const ini_file = try std.fs.cwd().createFile(self.ov.ini_file, .{ .truncate = true });
        defer ini_file.close();
        const status = try ini_save.save(ini_file.writer(), .{});
        std.debug.assert(status == .ok);
        try stdout.print(
            ANSI("Master version '{[mf]s}' has been saved in the {[inif]s} file." ++ endl ++ "Note: ZLS requires manually building it at https://github.com/zigtools/zls using this version, and copying to the versions" ++ sl_str ++ "{[mf]s}" ++ sl_str ++ "{[zlsf]s} folder." ++ endl, .{ 1, 32 }),
            .{ .mf = master_filename.?, .inif = self.ov.ini_file, .zlsf = Keys.Info[@intFromEnum(Keys.ZlsFolder)].default.? },
        );
        return 0;
    } else {
        try stderr.writeAll(comptime ANSI("Unable to fetch information from https://ziglang.org/download/index.json at this time." ++ endl, .{ 1, 31 }));
        return 1;
    }
    return 0;
}
