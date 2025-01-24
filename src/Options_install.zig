const std = @import("std");
const Options = @import("Options.zig");
const choose_version = Options.choose_version;
const ini_parser = @import("ini_parser.zig");
const Parser = ini_parser.Parser;
const utilities = @import("utilities.zig");
const ANSI = utilities.ANSI;
const endl = utilities.endl;
const os_tag = utilities.os_tag;
const sl_str = utilities.sl_str;
const zig_bin = utilities.zig_bin;
const zls_bin = utilities.zls_bin;
const as_os_path = utilities.as_os_path;
const symlinks_ini = utilities.symlinks_ini;
const keys_map = @import("keys_map.zig");
const Keys = keys_map.Keys;
const BooleanMap = keys_map.BooleanMap;
const ini_reader = @import("ini_reader.zig");
pub fn install(self: *Options, _: []const u8) !?u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    var parser: Parser = undefined;
    try parser.init(self.allocator, self.ov);
    defer parser.deinit(self.allocator);
    var redownload = false;
    var reinstall_zig = false;
    var reinstall_zls = false;
    var _to_version: ?[]const u8 = null;
    while (self.args_it.peek()) |arg| {
        if (std.mem.eql(u8, arg, "-choose")) {
            self.args_it.discard();
            _to_version = try choose_version(self.allocator, parser, self.ov);
            continue;
        }
        if (std.mem.eql(u8, arg, "-redownload")) {
            redownload = true;
            self.args_it.discard();
            continue;
        }
        if (std.mem.eql(u8, arg, "-reinstall_all")) {
            reinstall_zig = true;
            reinstall_zls = true;
            self.args_it.discard();
            continue;
        }
        if (std.mem.eql(u8, arg, "-reinstall_zig")) {
            reinstall_zig = true;
            self.args_it.discard();
            continue;
        }
        if (std.mem.eql(u8, arg, "-reinstall_zls")) {
            reinstall_zls = true;
            self.args_it.discard();
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
    const to_version: []const u8 = _to_version.?;
    for ([_][]const u8{ "!Windows", "!Linux", "!MacOS" }) |str| {
        if (std.mem.eql(u8, to_version, str)) {
            try stderr.print(ANSI("The '{s}' section is reserved for OS key/value use only." ++ endl, .{ 1, 31 }), .{to_version});
            return 1;
        }
    }
    for (to_version) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '_', ' ' => {},
            else => {
                try stderr.print(ANSI("Invalid version name '{s}' to convert to folder. It should only contain characters from a-z, A-Z, 0-9, '-', '_', '.', and ' ' (space) only." ++ endl, .{ 1, 31 }), .{to_version});
                return 1;
            },
        }
    }
    try stdout.print(ANSI("Using version '{s}'" ++ endl, .{1}), .{to_version});
    const combined = parser.get_combined(to_version) catch {
        try stderr.print(ANSI("The version section name '{s}' doesn't exist in the {s} file." ++ endl, .{ 1, 31 }), .{ to_version, self.ov.ini_file });
        return 1;
    };
    const requires_str = combined.get(Keys.RequiresDownload.str()).?;
    if (!Keys.RequiresDownload.check()(requires_str)) {
        try stderr.print(ANSI("The {s} value '{s}' is invalid. It should be a boolean value." ++ endl, .{ 1, 31 }), .{ Keys.RequiresDownload.str(), requires_str });
        return 1;
    }
    const chosen_os_type = combined.get(Keys.OSType.str()) orelse {
        try stderr.print(ANSI("{s} must be 'Windows', 'Linux', or 'MacOS'." ++ endl, .{ 1, 31 }), .{Keys.OSType.str()});
        return 1;
    };
    switch (os_tag) {
        .windows, .macos, .linux => |os| check: {
            if (std.mem.eql(u8, chosen_os_type, "Windows") and os == .windows) break :check;
            if (std.mem.eql(u8, chosen_os_type, "Linux") and os == .linux) break :check;
            if (std.mem.eql(u8, chosen_os_type, "MacOS") and os == .macos) break :check;
            try stderr.print(ANSI("Version OS mismatch! This version uses '{s}'." ++ endl, .{ 1, 31 }), .{chosen_os_type});
            return 1;
        },
        else => {
            try stderr.writeAll(ANSI("The OS for this section should be 'Windows', 'Linux' or 'MacOS'" ++ endl, .{ 1, 31 }));
            return 1;
        },
    }
    const is_downloadable = BooleanMap.get(requires_str).?;
    const zig_download = combined.get(Keys.ZigDownload.str());
    const zls_download = combined.get(Keys.ZlsDownload.str());
    const zig_folder = combined.get(Keys.ZigFolder.str()).?;
    const zls_folder = combined.get(Keys.ZlsFolder.str()).?;
    const zig_symlink_name = combined.get(Keys.ZigSymlink.str()).?;
    const zls_symlink_name = combined.get(Keys.ZlsSymlink.str()).?;
    const uses_zls_str = combined.get(Keys.UsesZls.str()).?;
    if (!Keys.UsesZls.check()(uses_zls_str)) {
        try stderr.print(ANSI("The {s} key '{s}' is invalid. It should be a boolean value." ++ endl, .{ 1, 31 }), .{ Keys.UsesZls.str(), uses_zls_str });
        return 1;
    }
    const uses_zls = BooleanMap.get(uses_zls_str).?;
    const version_folder = try std.fmt.allocPrint(self.allocator, as_os_path(.{ "versions", "{s}" }, .dir), .{to_version});
    defer self.allocator.free(version_folder);
    //Create non-existent directories/files if not yet made.
    std.fs.cwd().makeDir(version_folder) catch {};
    var version_dir = try std.fs.cwd().openDir(version_folder, .{});
    defer version_dir.close();
    version_dir.makeDir(zig_folder) catch {};
    var zig_folder_dir = try version_dir.openDir(zig_folder, .{ .iterate = true });
    defer zig_folder_dir.close();
    version_dir.makeDir(zls_folder) catch {};
    var zls_folder_dir = try version_dir.openDir(zls_folder, .{ .iterate = true });
    defer zls_folder_dir.close();
    var symlinks_dir = try std.fs.cwd().openDir("symlinks", .{});
    defer symlinks_dir.close();
    var symlinks_ini_create: std.fs.File = undefined;
    {
        symlinks_ini_create = try symlinks_dir.createFile(symlinks_ini, .{ .truncate = false });
        defer symlinks_ini_create.close();
        if (try symlinks_ini_create.getEndPos() == 0)
            try symlinks_ini_create.writer().writeAll(";Internally used by ziglinks to keep track of symlinks from different versions when installing/uninstalling. Don't edit." ++ endl);
    }
    var global_downloads_dir = try std.fs.cwd().openDir("downloads", .{});
    defer global_downloads_dir.close();
    global_downloads_dir.makeDir(to_version) catch {};
    var downloads_dir = try global_downloads_dir.openDir(to_version, .{ .iterate = true });
    defer downloads_dir.close();
    if (redownload) {
        try stdout.writeAll(comptime ANSI("-redownload sub-option is set. Redownloading links!" ++ endl, .{1}));
        try remove_all_in_dir(downloads_dir);
    }
    var zig_bin_path: ?[]const u8 = try find_bin_path(self.allocator, zig_folder_dir, ".", zig_bin);
    defer if (zig_bin_path) |zbp| self.allocator.free(zbp);
    var zls_bin_path: ?[]const u8 = try find_bin_path(self.allocator, zls_folder_dir, ".", zls_bin);
    defer if (zls_bin_path) |zbp| self.allocator.free(zbp);
    //Download zig/zls files
    if (is_downloadable) {
        if (zig_download == null) {
            try stderr.print(ANSI("{s} must be set because {s} is set as true." ++ endl, .{ 1, 31 }), .{ Keys.ZigDownload.str(), Keys.RequiresDownload.str() });
            return 1;
        }
        const dm = combined.get(Keys.DownloadManager.str()) orelse {
            try stderr.print(ANSI("{s} must be set because {s} is set as true." ++ endl, .{ 1, 31 }), .{ Keys.DownloadManager.str(), Keys.RequiresDownload.str() });
            return 1;
        };
        const dm_output_flag = combined.get(Keys.DownloadManagerOutputFlag.str()) orelse {
            try stderr.print(ANSI("{s} must be set because {s} is set as true." ++ endl, .{ 1, 31 }), .{ Keys.DownloadManagerOutputFlag.str(), Keys.RequiresDownload.str() });
            return 1;
        };
        const dm_flags = combined.get(Keys.DownloadManagerFlags.str());
        var flag_array: [][]const u8 = try self.allocator.alloc([]const u8, 2);
        defer self.allocator.free(flag_array);
        flag_array[0] = dm;
        flag_array[1] = zig_download.?;
        //This parses non-spaces of the string dm_flags into each []const u8.
        if (dm_flags) |dmf| {
            var get_slice: []const u8 = dmf[0..0];
            for (0..dmf.len) |i| {
                if (dmf[i] == ' ') {
                    if (get_slice.len == 0) {
                        get_slice.ptr += 1; //Next character (might be space).
                        continue;
                    }
                    flag_array = try self.allocator.realloc(flag_array, flag_array.len + 1);
                    flag_array[flag_array.len - 1] = get_slice;
                    get_slice = dmf[i + 1 .. i + 1]; //Get zero-length of next character (might be space).
                } else {
                    get_slice.len += 1;
                }
            }
            if (get_slice.len != 0) {
                flag_array = try self.allocator.realloc(flag_array, flag_array.len + 1);
                flag_array[flag_array.len - 1] = get_slice;
            }
        }
        flag_array = try self.allocator.realloc(flag_array, flag_array.len + 1);
        flag_array[flag_array.len - 1] = dm_output_flag;
        const zd_slash: usize = for (0..zig_download.?.len) |i| {
            if (zig_download.?[zig_download.?.len - 1 - i] == '/') break zig_download.?.len - 1 - i;
        } else {
            try stderr.print(ANSI("The {s} string '{s}' doesn't contain '/'." ++ endl, .{ 1, 31 }), .{ Keys.ZigDownload.str(), zig_download.? });
            return 1;
        };
        flag_array = try self.allocator.realloc(flag_array, flag_array.len + 1);
        const zig_download_file_name = zig_download.?[zd_slash + 1 ..];
        const zig_ext = check_download_extension(zig_download_file_name);
        if (zig_ext == .None) {
            try stderr.print(ANSI("The link '{s}' doesn't contain a .tar.xz, .tar.gz, .tar.zst, or .zip extension. Cannot continue." ++ endl, .{ 1, 31 }), .{zig_download.?});
            return 1;
        }
        const zig_download_file_name_unf = try std.fmt.allocPrint(self.allocator, "{s}.unfinished", .{zig_download_file_name});
        defer self.allocator.free(zig_download_file_name_unf);
        flag_array[flag_array.len - 1] = zig_download_file_name_unf;
        const exit_code = try child_process_download_file(self.allocator, downloads_dir, flag_array, zig_download_file_name, zig_download_file_name_unf, to_version);
        if (exit_code != null) return exit_code;
        var zls_ext: Extension = .None;
        var zls_download_file_name: ?[]const u8 = null;
        if (uses_zls and zls_download != null) {
            var zls_flag_array: [][]const u8 = try self.allocator.dupe([]const u8, flag_array);
            defer self.allocator.free(zls_flag_array);
            zls_flag_array[1] = zls_download.?;
            const zlsd_slash: usize = for (0..zls_download.?.len) |i| {
                if (zls_download.?[zls_download.?.len - 1 - i] == '/') break zls_download.?.len - 1 - i;
            } else {
                try stderr.print(ANSI("The {s} string '{s}' doesn't contain '/'." ++ endl, .{ 1, 31 }), .{ Keys.ZlsDownload.str(), zls_download.? });
                return 1;
            };
            zls_download_file_name = zls_download.?[zlsd_slash + 1 ..];
            zls_ext = check_download_extension(zls_download_file_name.?);
            if (zls_ext == .None) {
                try stderr.print(ANSI("The link '{s}'' doesn't contain a .tar.xz, .tar.gz, or .zip extension. Cannot continue." ++ endl, .{ 1, 31 }), .{zls_download.?});
                return 1;
            }
            const zls_download_file_name_unf = try std.fmt.allocPrint(self.allocator, "{s}.unfinished", .{zls_download_file_name.?});
            defer self.allocator.free(zls_download_file_name_unf);
            zls_flag_array[zls_flag_array.len - 1] = zls_download_file_name_unf;
            const exit_code_zls = try child_process_download_file(self.allocator, downloads_dir, zls_flag_array, zls_download_file_name.?, zls_download_file_name_unf, to_version);
            if (exit_code_zls != null) return exit_code_zls;
        }
        //Unpack zig/zls files
        switch (zig_ext) {
            .TarXz, .TarGz, .TarZst, .Zip => |ext| {
                if (zig_bin_path != null and !reinstall_zig) {
                    try stdout.print(ANSI("Binary '" ++ as_os_path(.{ "versions", "{s}", "{s}", "{s}" }, .file) ++ "' has been detected." ++ endl, .{ 1, 32 }), .{ to_version, zig_folder, zig_bin_path.? });
                } else {
                    if (reinstall_zig) try stdout.writeAll(comptime ANSI("Reinstalling zig..." ++ endl, .{ 1, 33 }));
                    try stdout.print(ANSI("Deleting files within " ++ as_os_path(.{ "versions", "{s}", "{s}" }, .dir) ++ endl, .{1}), .{ to_version, zig_folder });
                    try remove_all_in_dir(zig_folder_dir);
                    try stdout.print(ANSI("Extracting files of {s} into " ++ as_os_path(.{ "versions", "{s}", "{s}" }, .dir) ++ endl, .{1}), .{ to_version, zig_download_file_name, zig_folder });
                    if (ext == .TarXz) {
                        var zig_tarxz_file = try downloads_dir.openFile(zig_download_file_name, .{});
                        defer zig_tarxz_file.close();
                        var zig_tar = try std.compress.xz.decompress(self.allocator, zig_tarxz_file.reader());
                        defer zig_tar.deinit();
                        try std.tar.pipeToFileSystem(zig_folder_dir, zig_tar.reader(), .{ .mode_mode = .ignore });
                    } else if (ext == .Zip) {
                        var zig_zip_file = try downloads_dir.openFile(zig_download_file_name, .{});
                        defer zig_zip_file.close();
                        try std.zip.extract(zig_folder_dir, zig_zip_file.seekableStream(), .{});
                    } else { //.tar.gz and .tar.zst
                        try stderr.writeAll(comptime ANSI("TODO: Add decompression for .tar.xz and .tar.zst. There should be no extensions in 'ziglang.org/download/' right now." ++ endl, .{ 1, 31 }));
                        return 1;
                    }
                    if (zig_bin_path) |zbp| self.allocator.free(zbp); //If reinstalling, but zig_bin_path has been detected (String was allocated twice)
                    zig_bin_path = try find_bin_path(self.allocator, zig_folder_dir, ".", zig_bin);
                    zig_folder_dir.access(zig_bin_path.?, .{}) catch {
                        try stderr.writeAll(comptime ANSI("Error: " ++ zig_bin ++ " cannot be found." ++ endl ++ endl, .{ 1, 31 }));
                        return 1;
                    };
                }
            },
            .None => unreachable,
        }
        if (uses_zls and zls_download != null) {
            switch (zls_ext) {
                .TarXz, .TarGz, .TarZst, .Zip => |ext| {
                    if (zls_bin_path != null and !reinstall_zls) {
                        try stdout.print(ANSI("Binary '" ++ as_os_path(.{ "versions", "{s}", "{s}", "{s}" }, .file) ++ "' has been detected." ++ endl, .{ 1, 32 }), .{ to_version, zls_folder, zls_bin_path.? });
                    } else {
                        if (reinstall_zig) try stdout.writeAll(comptime ANSI("Reinstalling zls..." ++ endl, .{ 1, 33 }));
                        try stdout.print(ANSI("Deleting files within " ++ as_os_path(.{ "versions", "{s}", "{s}" }, .dir) ++ endl, .{1}), .{ to_version, zls_folder });
                        try remove_all_in_dir(zls_folder_dir);
                        try stdout.print(ANSI("Extracting files of {s} into " ++ as_os_path(.{ "versions", "{s}", "{s}" }, .dir) ++ endl, .{1}), .{ to_version, zls_download_file_name.?, zls_folder });
                        const use_pipe_options: std.tar.PipeOptions = .{ .mode_mode = .ignore };
                        if (ext == .TarXz) {
                            var zls_tarxz_file = try downloads_dir.openFile(zls_download_file_name.?, .{});
                            defer zls_tarxz_file.close();
                            var zls_untarxz = try std.compress.xz.decompress(self.allocator, zls_tarxz_file.reader());
                            defer zls_untarxz.deinit();
                            try std.tar.pipeToFileSystem(zls_folder_dir, zls_untarxz.reader(), use_pipe_options);
                        } else if (ext == .TarGz) {
                            var zls_targz_file = try downloads_dir.openFile(zls_download_file_name.?, .{});
                            defer zls_targz_file.close();
                            var zls_untargz = std.compress.gzip.decompressor(zls_targz_file.reader());
                            try std.tar.pipeToFileSystem(zls_folder_dir, zls_untargz.reader(), use_pipe_options);
                        } else if (ext == .Zip) {
                            var zls_zip_file = try downloads_dir.openFile(zls_download_file_name.?, .{});
                            defer zls_zip_file.close();
                            try std.zip.extract(zls_folder_dir, zls_zip_file.seekableStream(), .{});
                        } else { //.tar.zst
                            var zls_tarzst_file = try downloads_dir.openFile(zls_download_file_name.?, .{});
                            defer zls_tarzst_file.close();
                            var buf: [std.compress.zstd.DecompressorOptions.default_window_buffer_len]u8 = undefined;
                            var zls_untarzst = std.compress.zstd.decompressor(zls_tarzst_file.reader(), .{ .window_buffer = &buf });
                            try std.tar.pipeToFileSystem(zls_folder_dir, zls_untarzst.reader(), use_pipe_options);
                        }
                        if (zls_bin_path) |zbp| self.allocator.free(zbp);
                        zls_bin_path = try find_bin_path(self.allocator, zls_folder_dir, ".", zls_bin);
                        zls_folder_dir.access(zls_bin_path.?, .{}) catch {
                            try stderr.writeAll(comptime ANSI("Error: " ++ zls_bin ++ " cannot be found." ++ endl, .{ 1, 31 }));
                            return 1;
                        };
                    }
                },
                .None => unreachable,
            }
        }
    }
    //If zls_download is null, but uses_zls is true.
    if (zls_bin_path == null) {
        try stderr.writeAll(comptime ANSI("Error: " ++ zls_bin ++ " cannot be found." ++ endl, .{ 1, 31 }));
        return 1;
    }
    const alt_zig_symlink = combined.get(Keys.AltZigSymlink.str());
    const alt_zls_symlink = combined.get(Keys.AltZlsSymlink.str());
    //To overwrite current zig/zls symlinks.
    try replace_symlink(self.allocator, symlinks_dir, to_version, zig_folder, zig_bin_path.?, zig_symlink_name, alt_zig_symlink);
    if (uses_zls) try replace_symlink(self.allocator, symlinks_dir, to_version, zls_folder, zls_bin_path.?, zls_symlink_name, alt_zls_symlink);
    try stdout.print(ANSI("Please check if the symlinks are correctly pointing at the binary paths provided. To use the symlink binaries, append the '{s}" ++ sl_str ++ "versions' folder to an environment variable like PATH" ++ endl, .{ 1, 34 }), .{self.bin_path_str});
    edit_symlinks(.replace, self, symlinks_dir, to_version, zig_symlink_name, uses_zls, zls_symlink_name, alt_zig_symlink, alt_zls_symlink) catch |e| {
        try stderr.writeAll(comptime ANSI("Corrupted '" ++ symlinks_ini ++ "'. If you are seeing this message, this might be an unintended bug. Try using the --clear_symlinks option and running the --install option again.\n", .{ 1, 31 }));
        return e;
    };
    return 0;
}
pub fn remove_all_in_dir(iterative_dir: std.fs.Dir) !void {
    var iterative_dir_it = iterative_dir.iterate();
    while (try iterative_dir_it.next()) |entry| {
        switch (entry.kind) {
            .file, .sym_link => try iterative_dir.deleteFile(entry.name),
            .directory => try iterative_dir.deleteTree(entry.name),
            else => {},
        }
    }
}
/// This struct outputs a string of a path delimited by '/' or '\\'. String memory is duplicated and owned by this struct.
const BinPath = struct {
    paths: [][]const u8,
    len: usize,
    allocator: std.mem.Allocator,
    fn init(path: []const u8, allocator: std.mem.Allocator) !BinPath {
        var self: BinPath = .{ .paths = try allocator.alloc([]const u8, 1), .allocator = allocator, .len = 1 };
        self.paths[0] = try allocator.dupe(u8, path);
        return self;
    }
    fn push(self: *BinPath, new_path: []const u8) !void {
        self.len += 1;
        if (self.len > self.paths.len) //Only grow if len is greater.
            self.paths = try self.allocator.realloc(self.paths, self.paths.len + 1);
        self.paths[self.len - 1] = try self.allocator.dupe(u8, new_path);
    }
    fn pop(self: *BinPath) void {
        if (self.len == 0) return;
        self.len -= 1;
        self.allocator.free(self.paths[self.len]);
    }
    /// Caller owns the output string.
    fn output(self: BinPath) ![]const u8 {
        const begin_slice: usize = if (std.mem.eql(u8, self.paths[0], ".")) 1 else 0; //Exclude "."
        return try std.mem.join(self.allocator, sl_str, self.paths[begin_slice..self.len]);
    }
    fn deinit(self: BinPath) void {
        for (self.paths[0..self.len]) |path| self.allocator.free(path);
        self.allocator.free(self.paths);
    }
};
/// Recursivly iterate through a directory's sub directories until a binary name is found or if the binary name doesn't exist.
/// Caller owns string. The string may be optional if not found.
fn find_bin_path(allocator: std.mem.Allocator, dir: std.fs.Dir, sub_dir: []const u8, bin_name: []const u8) !?[]const u8 {
    var bp = try BinPath.init(sub_dir, allocator);
    defer bp.deinit();
    var dirs: []std.fs.Dir = try allocator.alloc(std.fs.Dir, 1);
    defer allocator.free(dirs);
    dirs[0] = try dir.openDir(sub_dir, .{ .iterate = true });
    defer for (dirs) |*_dir| _dir.close(); //If the above errors, don't run defer close all directories.
    var dirs_iters: []std.fs.Dir.Iterator = try allocator.alloc(std.fs.Dir.Iterator, 1);
    defer allocator.free(dirs_iters);
    dirs_iters[0] = dirs[0].iterate();
    var dir_i: usize = 0;
    while (true) {
        const entry = try dirs_iters[dir_i].next() orelse {
            bp.pop();
            if (dir_i == 0) return null;
            dir_i -= 1;
            dirs[dirs.len - 1].close();
            dirs = try allocator.realloc(dirs, dirs.len - 1);
            dirs_iters = try allocator.realloc(dirs_iters, dirs_iters.len - 1);
            continue;
        };
        switch (entry.kind) {
            .directory => {
                dir_i += 1;
                try bp.push(entry.name);
                dirs = try allocator.realloc(dirs, dirs.len + 1);
                dirs[dir_i] = try dirs[dir_i - 1].openDir(entry.name, .{ .iterate = true });
                dirs_iters = try allocator.realloc(dirs_iters, dirs_iters.len + 1); //Moving this above segfaults. Probably because entry was moved due to realloc.
                dirs_iters[dir_i] = dirs[dir_i].iterate();
            },
            .file => {
                if (std.mem.eql(u8, entry.name, bin_name)) {
                    try bp.push(entry.name);
                    return try bp.output();
                }
            },
            else => {},
        }
    }
}
const Extension = enum { None, TarXz, TarGz, TarZst, Zip };
/// .tar.xz and .zip seems to be the compression extensions for zig/zls folders.
fn check_download_extension(file_name: []const u8) Extension {
    const ValidExt = [_]struct { []const u8, Extension }{
        .{ ".tar.xz", .TarXz },
        .{ ".tar.gz", .TarGz },
        .{ ".zip", .Zip },
        .{ ".tar.zst", .TarZst },
    };
    for (ValidExt) |ext| {
        if (ext.@"0".len > file_name.len) continue;
        if (std.mem.eql(u8, file_name[file_name.len - ext.@"0".len ..], ext.@"0")) return ext.@"1";
    }
    return .None;
}
/// If an error happens in the child process, return 1 or a zig error to exit.
fn child_process_download_file(allocator: std.mem.Allocator, downloads_dir: std.fs.Dir, child_process_arr: []const []const u8, file_name: []const u8, file_name_unf: []const u8, to_version: []const u8) !?u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    if (downloads_dir.access(file_name, .{})) |_| {
        try stdout.print(ANSI("File '" ++ as_os_path(.{ "downloads", "{s}", "{s}" }, .file) ++ "' has already been downloaded. Please remove if you need to download the file again." ++ endl, .{ 1, 34 }), .{ to_version, file_name });
    } else |err| {
        switch (err) {
            error.FileNotFound => {},
            else => {
                try stderr.writeAll(comptime ANSI("Unexpected error has happened." ++ endl, .{ 1, 31 }));
                return err;
            },
        }
        try stdout.writeAll("Calling child process: ");
        for (0..child_process_arr.len) |i| try stdout.print("{s} ", .{child_process_arr[i]});
        try stdout.writeAll(endl);
        var child_proc = std.process.Child.init(child_process_arr, allocator);
        const child_proc_downloads_dir = try std.fmt.allocPrint(allocator, as_os_path(.{ "downloads", "{s}" }, .dir), .{to_version});
        defer allocator.free(child_proc_downloads_dir);
        child_proc.cwd = child_proc_downloads_dir;
        const child_proc_term = try child_proc.spawnAndWait();
        switch (child_proc_term) {
            .Exited => |status| {
                if (status != 0) {
                    try stderr.print(ANSI("Couldn't download the file '{s}' correctly." ++ endl, .{ 1, 31 }), .{file_name_unf});
                    return 1;
                }
            },
            else => {
                try stderr.print(ANSI("Couldn't download the file '{s}' correctly." ++ endl, .{ 1, 31 }), .{file_name_unf});
                return 1;
            },
        }
        //move .unfinished file with the .unfinished part removed.
        try downloads_dir.rename(file_name_unf, file_name);
    }
    return null;
}
fn replace_symlink(allocator: std.mem.Allocator, symlinks_dir: std.fs.Dir, to_version: []const u8, zig_folder: []const u8, zig_path: []const u8, zig_symlink: []const u8, alt_zig_symlink: ?[]const u8) !void {
    const stdout = std.io.getStdOut().writer();
    symlinks_dir.deleteFile(zig_symlink) catch {};
    if (alt_zig_symlink) |azs| symlinks_dir.deleteFile(azs) catch {};
    const zig_binary_rel_path = try std.fmt.allocPrint(allocator, as_os_path(.{ "..", "versions", "{s}", "{s}", "{s}" }, .file), .{ to_version, zig_folder, zig_path });
    defer allocator.free(zig_binary_rel_path);
    if (os_tag == .windows) {
        try symlink_windows(allocator, symlinks_dir, zig_symlink, zig_binary_rel_path);
    } else {
        symlinks_dir.symLink(zig_binary_rel_path, zig_symlink, .{}) catch {};
        try stdout.print(ANSI("Symlink '{s}' has been created/overwritten to link at '{s}'." ++ endl, .{ 1, 32 }), .{ zig_symlink, zig_binary_rel_path });
    }
    if (alt_zig_symlink) |zig_symlink2| {
        if (os_tag == .windows) {
            try symlink_windows(allocator, symlinks_dir, zig_symlink2, zig_binary_rel_path);
        } else {
            symlinks_dir.symLink(zig_binary_rel_path, zig_symlink2, .{}) catch {};
            try stdout.print(ANSI("Symlink '{s}' has been created/overwritten to link at '{s}'." ++ endl, .{ 1, 32 }), .{ zig_symlink2, zig_binary_rel_path });
        }
    }
}
/// Because fs.Dir.symLink() doesn't work in Windows.
fn symlink_windows(allocator: std.mem.Allocator, symlinks_dir: std.fs.Dir, symlink_name: []const u8, symlink_path: []const u8) !void {
    const symlink_path_str = try symlinks_dir.realpathAlloc(allocator, ".");
    defer allocator.free(symlink_path_str);
    const symlink_command = try std.fmt.allocPrint(allocator, "cd {s}; new-item -ItemType SymbolicLink -Path {s} -Target {s}; write-host;", .{ symlink_path_str, symlink_name, symlink_path });
    defer allocator.free(symlink_command);
    const ps_start_process_str = try std.fmt.allocPrint(allocator, "start-process powershell -Verb runas -ArgumentList \"{s}\" -Wait", .{symlink_command});
    defer allocator.free(ps_start_process_str);
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    try stdout.print(endl ++ "The program will try to run an elevated powershell command:" ++ endl ++ endl ++ "\"\"\"" ++ endl ++ "{s}" ++ endl ++ "\"\"\"" ++ endl ++ endl, .{ps_start_process_str});
    try stdout.print(ANSI("Please allow administrator priviliges to run the command above to create the symlink '{s}' to the path '{s}'." ++ endl ++ "Press enter to continue..." ++ endl ++ endl, .{ 1, 34 }), .{ symlink_name, symlink_path });
    try press_enter();
    var symlink_proc = std.process.Child.init(&[_][]const u8{ "powershell", "-Command", ps_start_process_str }, allocator);
    switch (try symlink_proc.spawnAndWait()) {
        .Exited => |status| {
            if (status == 0) {
                try stdout.print(ANSI("Symlink '{s}' has been created/overwritten to link at '{s}'." ++ endl, .{ 1, 32 }), .{ symlink_name, symlink_path });
            } else try stderr.writeAll(comptime ANSI("Powershell did not add the symlink. Exited with a non-zero." ++ endl, .{ 1, 33 }));
        },
        else => {
            try stderr.writeAll(comptime ANSI("Powershell quits unexpectedly. Powershell did not add the symlink." ++ endl, .{ 1, 33 }));
        },
    }
}
fn press_enter() !void {
    const stdin = std.io.getStdIn().reader();
    while (try stdin.readByte() != '\n') {}
}
///Create/edit file that gets currently active (zig/zls)_symlink_name and alt_(zig/zls)_symlink_name
pub fn edit_symlinks(
    op: enum { remove, replace },
    self: *Options,
    symlinks_dir: std.fs.Dir,
    to_version: []const u8,
    zig_symlink_name: []const u8,
    uses_zls: bool,
    zls_symlink_name: []const u8,
    alt_zig_symlink: ?[]const u8,
    alt_zls_symlink: ?[]const u8,
) !void {
    var symlinks_lexer = try ini_reader.IniLexerFile.init(symlinks_dir, symlinks_ini, .{});
    defer symlinks_lexer.deinit(self.allocator);
    var ini_save: ini_reader.IniSave = .{};
    defer ini_save.deinit(self.allocator);
    var version_now: []const u8 = &.{};
    defer self.allocator.free(version_now);
    while (symlinks_lexer.next(self.allocator)) |t_op| {
        if (t_op) |t| {
            switch (t.value) {
                .section => |s| { //Remove section of to_version, but keep allocated strings in version_now for reading
                    self.allocator.free(version_now);
                    version_now = try self.allocator.dupe(u8, s);
                    if (std.mem.eql(u8, s, to_version)) {
                        self.allocator.free(s);
                        const newline_t = try symlinks_lexer.next(self.allocator) orelse return error.CorruptedSymlinkFile;
                        newline_t.deinit(self.allocator); //Try to also remove newline from the section
                    } else try ini_save.tokens.append(self.allocator, t);
                },
                .key => |k| {
                    const value_t = try symlinks_lexer.next(self.allocator) orelse return error.CorruptedSymlinkFile;
                    const newline_t = try symlinks_lexer.next(self.allocator) orelse return error.CorruptedSymlinkFile;
                    if (!std.mem.eql(u8, version_now, to_version)) { //Remove instances of zig/zls symlinks from different versions
                        if (std.mem.eql(u8, k, Keys.ZigSymlink.str())) {
                            if (std.mem.eql(u8, value_t.value.get_str(), zig_symlink_name)) {
                                t.deinit(self.allocator);
                                value_t.deinit(self.allocator);
                                newline_t.deinit(self.allocator);
                                continue;
                            }
                        }
                        if (uses_zls and std.mem.eql(u8, k, Keys.ZlsSymlink.str())) {
                            if (std.mem.eql(u8, value_t.value.get_str(), zls_symlink_name)) {
                                t.deinit(self.allocator);
                                value_t.deinit(self.allocator);
                                newline_t.deinit(self.allocator);
                                continue;
                            }
                        }
                        if (alt_zig_symlink != null and std.mem.eql(u8, k, Keys.AltZigSymlink.str())) {
                            if (std.mem.eql(u8, value_t.value.get_str(), alt_zig_symlink.?)) {
                                t.deinit(self.allocator);
                                value_t.deinit(self.allocator);
                                newline_t.deinit(self.allocator);
                                continue;
                            }
                        }
                        if (uses_zls and alt_zls_symlink != null and std.mem.eql(u8, k, Keys.AltZlsSymlink.str())) {
                            if (std.mem.eql(u8, value_t.value.get_str(), alt_zls_symlink.?)) {
                                t.deinit(self.allocator);
                                value_t.deinit(self.allocator);
                                newline_t.deinit(self.allocator);
                                continue;
                            }
                        }
                        try ini_save.tokens.append(self.allocator, t);
                        try ini_save.tokens.append(self.allocator, value_t);
                        try ini_save.tokens.append(self.allocator, newline_t);
                    } else { //Also all instances of zig/zls symlinks of the same version to be readded
                        t.deinit(self.allocator);
                        value_t.deinit(self.allocator);
                        newline_t.deinit(self.allocator);
                    }
                },
                .value => unreachable,
                else => {
                    try ini_save.tokens.append(self.allocator, t);
                },
            }
            //
        } else break;
    } else |e| return e;
    if (op == .replace) {
        //Add possible tokens to symlinks file
        try ini_save.tokens.ensureUnusedCapacity(self.allocator, 14);
        ini_save.tokens.appendAssumeCapacity(.{
            .alloc = false,
            .value = .{ .section = to_version },
        });
        ini_save.tokens.appendAssumeCapacity(.{ .alloc = false, .value = .newline });
        ini_save.tokens.appendAssumeCapacity(.{
            .alloc = false,
            .value = .{ .key = Keys.ZigSymlink.str() },
        });
        ini_save.tokens.appendAssumeCapacity(.{
            .alloc = false,
            .value = .{ .value = .{ .str = zig_symlink_name } },
        });
        ini_save.tokens.appendAssumeCapacity(.{ .alloc = false, .value = .newline });
        if (uses_zls) {
            ini_save.tokens.appendAssumeCapacity(.{
                .alloc = false,
                .value = .{ .key = Keys.ZlsSymlink.str() },
            });
            ini_save.tokens.appendAssumeCapacity(.{
                .alloc = false,
                .value = .{ .value = .{ .str = zls_symlink_name } },
            });
            ini_save.tokens.appendAssumeCapacity(.{ .alloc = false, .value = .newline });
        }
        if (alt_zig_symlink) |alt_zig_sym| {
            ini_save.tokens.appendAssumeCapacity(.{
                .alloc = false,
                .value = .{ .key = Keys.AltZigSymlink.str() },
            });
            ini_save.tokens.appendAssumeCapacity(.{
                .alloc = false,
                .value = .{ .value = .{ .str = alt_zig_sym } },
            });
            ini_save.tokens.appendAssumeCapacity(.{ .alloc = false, .value = .newline });
        }
        if (uses_zls and alt_zls_symlink != null) {
            ini_save.tokens.appendAssumeCapacity(.{
                .alloc = false,
                .value = .{ .key = Keys.AltZlsSymlink.str() },
            });
            ini_save.tokens.appendAssumeCapacity(.{
                .alloc = false,
                .value = .{ .value = .{ .str = alt_zls_symlink.? } },
            });
            ini_save.tokens.appendAssumeCapacity(.{ .alloc = false, .value = .newline });
        }
    }
    const symlinks_ini_create = try symlinks_dir.createFile(symlinks_ini, .{ .truncate = true });
    defer symlinks_ini_create.close();
    const status = try ini_save.save(symlinks_ini_create.writer(), .{});
    if (status != .ok) return error.CorruptedSymlinkFile;
}
