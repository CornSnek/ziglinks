const std = @import("std");
pub const BooleanMap = std.StaticStringMap(bool).initComptime(.{
    .{ "true", true }, .{ "false", false }, .{ "y", true }, .{ "n", false }, .{ "yes", true }, .{ "no", false }, .{ "1", true }, .{ "0", false },
});
const Check = struct {
    fn none(_: []const u8) bool {
        return true;
    }
    fn in_true_false_map(version: []const u8) bool {
        return BooleanMap.get(version) != null;
    }
    fn is_os_type(os: []const u8) bool {
        const ValidOS = [_][]const u8{ "Windows", "Linux", "MacOS" };
        for (ValidOS) |check_os| {
            if (std.mem.eql(u8, os, check_os)) return true;
        }
        return false;
    }
};
pub const Keys = enum {
    RequiresDownload,
    ZigFolder,
    ZlsFolder,
    ZigDownload,
    ZlsDownload,
    DownloadManager,
    DownloadManagerFlags,
    DownloadManagerOutputFlag,
    ZigSymlink,
    ZlsSymlink,
    AltZigSymlink,
    AltZlsSymlink,
    UsesZls,
    OSType,
    const Count = std.meta.fields(Keys).len;
    pub const InfoStruct = struct {
        e: Keys,
        k: []const u8,
        check: *const fn ([]const u8) bool,
        description: []const u8,
        default: ?[]const u8 = null,
    };
    pub const Info: [Count]InfoStruct = .{
        .{
            .e = .RequiresDownload,
            .k = "requires_download",
            .check = Check.in_true_false_map,
            .description = "zig_download_link and download_manager should be set if this is true. Otherwise, tries to find the path of zig and zls (if 'uses_zls' is enabled) in the versions/ folder.",
            .default = "false",
        },
        .{
            .e = .ZigFolder,
            .k = "zig_folder_name",
            .check = Check.none,
            .description = "Folder name that contains the zig binary and directories. If not set, the default directory is zig",
            .default = "zig",
        },
        .{
            .e = .ZlsFolder,
            .k = "zls_folder_name",
            .check = Check.none,
            .description = "Folder name that contains the zls binary and directories. If not set, the default directory is zls",
            .default = "zls",
        },
        .{
            .e = .ZigDownload,
            .k = "zig_download_link",
            .check = Check.none,
            .description = "Download link for zig. Required if requires_download is true.",
        },
        .{
            .e = .ZlsDownload,
            .k = "zls_download_link",
            .check = Check.none,
            .description = "Download link for zls. Optional.",
        },
        .{
            .e = .DownloadManager,
            .k = "download_manager",
            .check = Check.none,
            .description = "If requires_download is set, this is required. This calls a shell command line program in order to download the file.",
        },
        .{
            .e = .DownloadManagerFlags,
            .k = "download_manager_flags",
            .check = Check.none,
            .description = "If requires_download is set, this is optional. This uses the flags required from the download_mangaer. Use download_manager_output_flag for the output flag only.",
        },
        .{
            .e = .DownloadManagerOutputFlag,
            .k = "download_manager_output_flag",
            .check = Check.none,
            .description = "If requires_download is set, this is required. This is the output flag from the download_manager.",
        },
        .{
            .e = .ZigSymlink,
            .k = "zig_symlink_name",
            .check = Check.none,
            .description = "Symlink name of the zig executable. If not set, the binary symlink name is 'zig' or 'zig.exe' (Windows).",
            .default = if (@import("builtin").os.tag == .windows) "zig.exe" else "zig",
        },
        .{
            .e = .ZlsSymlink,
            .k = "zls_symlink_name",
            .check = Check.none,
            .description = "Symlink name of the zls executable. If not set, the binary symlink name is 'zls' or 'zls.exe' (Windows).",
            .default = if (@import("builtin").os.tag == .windows) "zls.exe" else "zls",
        },
        .{
            .e = .AltZigSymlink,
            .k = "alt_zig_symlink_name",
            .check = Check.none,
            .description = "Alternative Symlink name of the zig executable. Optional.",
        },
        .{
            .e = .AltZlsSymlink,
            .k = "alt_zls_symlink_name",
            .check = Check.none,
            .description = "Alternative Symlink name of the zls executable. Optional.",
        },
        .{
            .e = .UsesZls,
            .k = "uses_zls",
            .check = Check.in_true_false_map,
            .description = "zls_download_link is used. However, if false, you can still link the zls binary to the zig_folder_name folder. Default is false.",
            .default = "false",
        },
        .{
            .e = .OSType,
            .k = "os_type",
            .check = Check.is_os_type,
            .description = "OS type that this version should use (required). Valid options: Windows, Linux, MacOS.",
        },
    };
    comptime {
        var int_enum_i: comptime_int = -1;
        var out_of_order: bool = false;
        for (Info) |info| {
            int_enum_i += 1;
            if (@intFromEnum(info.e) != int_enum_i) {
                @compileLog(info.e);
                out_of_order = true;
            }
        }
        if (out_of_order) @compileError("The following Keys.Info enum ordering is out of order.");
    }
    pub const StrToEnum = std.StaticStringMap(Keys).initComptime(v: {
        var espr: [Count]struct { []const u8, Keys } = undefined;
        for (0..Info.len) |i| espr[i] = .{ Info[i].k, Info[i].e };
        break :v espr;
    });
    /// String representation of enum.
    pub fn str(comptime self: Keys) []const u8 {
        return Info[@intFromEnum(self)].k;
    }
    /// If the string is a valid key.
    pub fn has(s: []const u8) bool {
        return StrToEnum.has(s);
    }
    pub fn check(comptime self: Keys) *const fn ([]const u8) bool {
        return Info[@intFromEnum(self)].check;
    }
};
