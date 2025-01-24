const Options = @This();
const std = @import("std");
const keys_map = @import("keys_map.zig");
const Keys = keys_map.Keys;
const BooleanMap = keys_map.BooleanMap;
const ini_parser = @import("ini_parser.zig");
const ini_reader = @import("ini_reader.zig");
const utilities = @import("utilities.zig");
const symlinks_ini = utilities.symlinks_ini;
const ANSI = utilities.ANSI;
const endl = utilities.endl;
const os_tag = utilities.os_tag;
const optional_str_eql = utilities.optional_str_eql;
const ArgsIterator = utilities.ArgsIterator;
pub const OptionsVariables = struct {
    ini_file: []const u8 = "ziglinks.ini",
};
allocator: std.mem.Allocator,
bin_path_str: []const u8,
args_it: *ArgsIterator,
ov: OptionsVariables,
/// These string names are the main functions below to use for the hashmap.
pub const functions_as_public = [_][]const u8{
    "usage",
    "keys",
    "read_versions",
    "use_ini",
    "install",
    "clear_symlinks",
    "uninstall",
    "help",
};
//pub fn functions are automatically placed in the options hashmap.
pub fn usage(self: *Options, _: []const u8) anyerror!?u8 {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\ziglinks usage:
        \\This program creates and changes symbolic links for zig.exe (and optionally zls.exe)
        \\in order to change the Zig versions. Zig and ZLS Files are downloaded in the '{[bin_path_str]s}{[s]c}versions{[s]c}' folder.
        \\Append PATH variable with the following path '{[bin_path_str]s}{[s]c}symlinks{[s]c}'
        \\in order to use the symbolic links.
        \\
        \\Type 'ziglinks -help' to see valid options.
        \\
    , .{ .s = utilities.sl, .bin_path_str = self.bin_path_str });
    return 0;
}
pub fn help(_: *Options, _: []const u8) anyerror!?u8 {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Available options:
        \\Commands that do not exit the program after running
        \\--use_ini: Reads the given .ini file. Default is ziglinks.ini
        \\
        \\Commands that exit the program after running:
        \\--usage: Prints the usage of the program.
        \\--read_versions: Prints the keys and values used for each version.
        \\  -filter: Prints only the versions that contains this string.
        \\--install: Downloads, unpacks, and adds symlinks to zig and zls binaires.
        \\  -version: Type the version within the .ini file to install.
        \\  -choose: You have a prompt to choose which version to install using the .ini file.
        \\  -redownload: Deletes files in downloads folder to redownload files given in the .ini file.
        \\  -reinstall-all/-reinstall-zig/-reinstall-zls: Deletes the files given in the versions folder.
        \\--keys: Prints the valid keys used for the .ini file.
        \\--uninstall: Removes a version's name/keys, and uninstalls the version in folders including symlinks.
        \\  -version: Type the version within the .ini file to install.
        \\  -choose: You have a prompt to choose which version to install using the .ini file.
        \\--clear_symlinks: Removes all symlinks in the symlinks folder. Use --install to add symlinks again.
        \\
    , .{});
    return 0;
}
pub fn keys(_: *Options, _: []const u8) anyerror!?u8 {
    const stdout = std.io.getStdOut().writer();
    for (keys_map.Keys.Info) |info| {
        try stdout.print(ANSI("Key: {s}", .{1}) ++ endl ++ "Description: {s}" ++ endl, .{ info.k, info.description });
        if (info.default) |default| try stdout.print("Default value: {s}" ++ endl, .{default});
        try stdout.writeAll(endl);
    }
    return 0;
}
///No global or OS sections
pub const exclude_sections = [_]?[]const u8{ null, "!Windows", "!Linux", "!MacOS" };
pub fn read_versions(self: *Options, _: []const u8) !?u8 {
    var filter_version: ?[]const u8 = null;
    while (self.args_it.peek()) |arg| {
        if (std.mem.eql(u8, arg, "-filter")) {
            self.args_it.discard();
            filter_version = self.args_it.next();
            continue;
        }
        break;
    }
    const stdout = std.io.getStdOut().writer();
    var parser: ini_parser.Parser = undefined;
    try parser.init(self.allocator, self.ov);
    defer parser.deinit(self.allocator);
    var parser_hm_it = parser.ini_hm.iterator();
    next_section: while (parser_hm_it.next()) |kvp| {
        const section: ?[]const u8 = kvp.key_ptr.*;
        for (exclude_sections) |s| {
            if (optional_str_eql(section, s)) continue :next_section;
        }
        if (filter_version) |fv|
            if (std.mem.indexOfPos(u8, section.?, 0, fv) == null) continue;
        const combined = try parser.get_combined(section.?);
        const os_str = combined.get(keys_map.Keys.OSType.str()) orelse continue;
        switch (os_tag) {
            .windows => if (!std.mem.eql(u8, os_str, "Windows")) continue,
            .linux => if (!std.mem.eql(u8, os_str, "Linux")) continue,
            .macos => if (!std.mem.eql(u8, os_str, "MacOS")) continue,
            else => {},
        }
        try stdout.print(ANSI("[{s}]" ++ endl, .{1}), .{section.?});
        for (keys_map.Keys.Info) |info| //Read each valid key for each version.
            if (combined.get(info.k)) |v|
                try stdout.print("{s} = {s}" ++ endl, .{ info.k, v });
        try stdout.writeAll(endl);
    }
    return 0;
}
pub fn use_ini(self: *Options, _: []const u8) anyerror!?u8 {
    const stderr = std.io.getStdErr().writer();
    self.ov.ini_file = self.args_it.next() orelse {
        try stderr.writeAll(comptime ANSI("--use_ini requires a file path.", .{ 1, 31 }) ++ endl);
        return 1;
    };
    return null;
}
pub const install = @import("Options_install.zig").install;
const remove_all_in_dir = @import("Options_install.zig").remove_all_in_dir;
const edit_symlinks = @import("Options_install.zig").edit_symlinks;
pub fn clear_symlinks(_: *Options, _: []const u8) anyerror!?u8 {
    const stdout = std.io.getStdErr().writer();
    var symlinks_dir = try std.fs.cwd().openDir("symlinks", .{ .iterate = true });
    defer symlinks_dir.close();
    try remove_all_in_dir(symlinks_dir);
    try stdout.writeAll(comptime ANSI("All symlinks in the symlinks/ folder have been deleted.", .{ 1, 34 }));
    return 0;
}
pub fn uninstall(self: *Options, _: []const u8) anyerror!?u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    var parser_ini: ini_parser.Parser = undefined;
    try parser_ini.init(self.allocator, self.ov);
    defer parser_ini.deinit(self.allocator);
    var _to_version: ?[]const u8 = null;
    while (self.args_it.peek()) |arg| {
        if (std.mem.eql(u8, arg, "-choose")) {
            self.args_it.discard();
            _to_version = try choose_version(self.allocator, parser_ini, self.ov);
            continue;
        }
        if (std.mem.eql(u8, arg, "-version")) {
            self.args_it.discard();
            _to_version = self.args_it.next();
            continue;
        }
        break;
    }
    if (_to_version == null) {
        try stderr.print(ANSI("No versions specified for '--install' (Use -choose or -version sub-options)" ++ endl, .{ 1, 31 }), .{});
        return 1;
    }
    for (_to_version.?) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '_', ' ' => {},
            else => {
                try stderr.print(ANSI("Invalid version name '{s}' to convert to folder. It should only contain characters from a-z, A-Z, 0-9, '-', '_', '.', and ' ' (space) only." ++ endl, .{ 1, 31 }), .{_to_version.?});
                return 1;
            },
        }
    }
    const to_version: []const u8 = _to_version.?;
    const combined = parser_ini.get_combined(to_version) catch {
        try stderr.print(ANSI("{s} is not a valid version in the .ini file." ++ endl, .{ 1, 31 }), .{to_version});
        return 1;
    };
    const uses_zls_str = combined.get(Keys.UsesZls.str()).?;
    if (!Keys.UsesZls.check()(uses_zls_str)) {
        try stderr.print(ANSI("The {s} key '{s}' is invalid. It should be a boolean value." ++ endl, .{ 1, 31 }), .{ Keys.UsesZls.str(), uses_zls_str });
        return 1;
    }
    const uses_zls = BooleanMap.get(uses_zls_str).?;
    const zig_symlink_name = combined.get(Keys.ZigSymlink.str()).?;
    const zls_symlink_name = combined.get(Keys.ZlsSymlink.str()).?;
    const alt_zig_symlink = combined.get(Keys.AltZigSymlink.str());
    const alt_zls_symlink = combined.get(Keys.AltZlsSymlink.str());
    var downloads_dir = try std.fs.cwd().openDir("downloads", .{ .iterate = true });
    defer downloads_dir.close();
    downloads_dir.deleteTree(to_version) catch {};
    var versions_dir = try std.fs.cwd().openDir("versions", .{ .iterate = true });
    defer versions_dir.close();
    versions_dir.deleteTree(to_version) catch {};
    //Remove references of this version's symlinks.
    var symlinks_dir = try std.fs.cwd().openDir("symlinks", .{ .iterate = true });
    defer symlinks_dir.close();
    edit_symlinks(.remove, self, symlinks_dir, to_version, zig_symlink_name, uses_zls, zls_symlink_name, alt_zig_symlink, alt_zls_symlink) catch |e| {
        try stderr.writeAll(comptime ANSI("Corrupted '" ++ symlinks_ini ++ "'. If you are seeing this message, this might be an unintended bug. Try using the --clear_symlinks option and running the --install option again.\n", .{ 1, 31 }));
        return e;
    };
    symlinks_dir.deleteFile(zig_symlink_name) catch {};
    symlinks_dir.deleteFile(zls_symlink_name) catch {};
    if (alt_zig_symlink) |alt_zig| symlinks_dir.deleteFile(alt_zig) catch {};
    if (alt_zls_symlink) |alt_zls| symlinks_dir.deleteFile(alt_zls) catch {};
    try stdout.print(ANSI("Version {s} uninstalled.\n", .{ 1, 33 }), .{to_version});
    return 0;
}
pub fn invalid(_: *Options, name: []const u8) !?u8 {
    const stderr = std.io.getStdErr().writer();
    try stderr.print(
        \\'{s}' is an invalid option. Type 'ziglinks --help' for valid options.
        \\
    , .{name});
    return 1;
}
pub fn requires_dash(_: *Options, name: []const u8) !?u8 {
    const stderr = std.io.getStdErr().writer();
    try stderr.print(
        \\'{[name]s}' is an invalid option. Did you mean '--{[name]s}'?
        \\
    , .{ .name = name });
    return 1;
}
pub fn choose_version(allocator: std.mem.Allocator, parser: ini_parser.Parser, ov: OptionsVariables) !?[]const u8 {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(ANSI("Used '-choose' sub-option. Please choose the version to use." ++ endl, .{ 1, 34 }), .{});
    var versions_strs = try allocator.alloc([]const u8, 0);
    defer allocator.free(versions_strs);
    var parser_k_it = parser.ini_hm.keyIterator();
    next_key: while (parser_k_it.next()) |k| {
        for (exclude_sections) |s| if (optional_str_eql(k.*, s)) continue :next_key;
        const combined = try parser.get_combined(k.*.?);
        const os_str = combined.get(Keys.OSType.str()) orelse continue;
        switch (os_tag) {
            .windows, .macos, .linux => |os| use_version: {
                if (std.mem.eql(u8, os_str, "Windows") and os == .windows) break :use_version;
                if (std.mem.eql(u8, os_str, "Linux") and os == .linux) break :use_version;
                if (std.mem.eql(u8, os_str, "MacOS") and os == .macos) break :use_version;
                continue;
            },
            else => continue,
        }
        versions_strs = try allocator.realloc(versions_strs, versions_strs.len + 1);
        versions_strs[versions_strs.len - 1] = k.*.?;
    }
    if (versions_strs.len == 0) {
        try stdout.print(ANSI("No versions are in the {s} file." ++ endl, .{ 1, 31 }), .{ov.ini_file});
        return null;
    }
    const stdin = std.io.getStdIn().reader();
    const at_index = while (true) {
        try stdout.writeAll(comptime ANSI("Choose the version you want to use. Type the number:" ++ endl, .{1}));
        for (0..versions_strs.len) |i|
            try stdout.print(ANSI("{}) [{s}]" ++ endl, .{1}), .{ i, versions_strs[i] });
        const i_str = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 10) orelse continue;
        defer allocator.free(i_str);
        const i = std.fmt.parseInt(usize, i_str[0 .. i_str.len - 1], 10) catch continue;
        if (i > versions_strs.len) continue;
        break i;
    };
    return versions_strs[at_index];
}
