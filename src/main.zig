const std = @import("std");
const utilities = @import("utilities.zig");
const Options = @import("Options.zig");
const ANSI = utilities.ANSI;
const endl = utilities.endl;
/// ?u8 is used to exit the program immediately with a u8 status.
const OptionsHashMapV = *const fn (*Options, []const u8) anyerror!?u8;
const OptionsHashMap = std.StringHashMap(OptionsHashMapV);
const make_bin_paths = [_][]const u8{ "versions", "symlinks", "downloads" };
fn init_program(bin_path_str: []const u8) !void {
    var bin_path = try std.fs.openDirAbsolute(bin_path_str, .{});
    defer bin_path.close();
    for (make_bin_paths) |path| {
        bin_path.makeDir(path) catch |e| {
            if (e == error.PathAlreadyExists) {
                continue;
            } else return e;
        };
    }
}
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var options_hashmap: OptionsHashMap = OptionsHashMap.init(allocator);
    defer options_hashmap.deinit(); //Puts Options.functions_as_public functions using their name as the key including '--'.
    inline for (Options.functions_as_public) |str_name| {
        try options_hashmap.put("--" ++ str_name, @field(Options, str_name));
        try options_hashmap.put(str_name, Options.requires_dash);
    }
    var args_it = try utilities.ArgsIterator.init(allocator);
    defer args_it.deinit(allocator);
    //Remove any path of binary.
    _ = args_it.next().?;
    //This is used to have the cwd "always point" inside the ziglinks binary, even if the binary is called from a $PATH variable in linux.
    const bin_path_str: []const u8 = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(bin_path_str);
    var bin_path_dir = try std.fs.openDirAbsolute(bin_path_str, .{});
    defer bin_path_dir.close();
    try bin_path_dir.setAsCwd();
    try init_program(bin_path_str);
    var options: Options = .{
        .allocator = allocator,
        .bin_path_str = bin_path_str,
        .args_it = &args_it,
        .ov = .{},
    };
    std.debug.print("{s}\n", .{args_it.it_arr});
    if (args_it.peek() == null) {
        _ = try Options.usage(&options, args_it.it_arr[0]);
        std.process.exit(0);
    }
    while (args_it.next()) |str| {
        const options_fn = options_hashmap.get(str) orelse Options.invalid;
        if (try options_fn(&options, str)) |code| std.process.exit(code);
    }
}
