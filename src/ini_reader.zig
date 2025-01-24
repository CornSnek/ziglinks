const std = @import("std");
pub const IniLexerOptions = struct {
    kv_delimiter: u8 = '=',
    comment_delimiter: u8 = ';',
    newline_delimiter: u8 = '\n',
    ///Every Token.Value string not newline or a value with escaped characters are allocated.
    alloc_strings: bool = false,
};
pub const Token = struct {
    ///If value strings are allocated, set .alloc to allow memory ownership of the string.
    alloc: bool,
    value: Value,
    pub const ValueStr = struct {
        str: []const u8,
        /// Helper function that only allocates strings that have `\`. It removes the first '\' but not the character after it.
        /// Example: `a\\b\cd` becomes `a\bcd`. `abcd` becomes null because there are no backslashes.
        pub fn repr(self: ValueStr, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 {
            var list: std.ArrayListUnmanaged(u8) = .{};
            defer list.deinit(allocator);
            const EscapedReadState = enum { no_backslash, backslash_false, backslash_true };
            var read_state: EscapedReadState = .no_backslash;
            for (0..self.str.len) |i| {
                const c = self.str[i];
                switch (read_state) {
                    .no_backslash => {
                        if (c == '\\') {
                            try list.appendSlice(allocator, self.str[0..i]);
                            read_state = .backslash_true;
                        }
                    },
                    .backslash_false => {
                        if (c != '\\') {
                            try list.append(allocator, c);
                        } else read_state = .backslash_true;
                    },
                    .backslash_true => {
                        try list.append(allocator, c);
                        read_state = .backslash_false;
                    },
                }
            }
            if (read_state == .no_backslash) {
                return null;
            } else {
                return try list.toOwnedSlice(allocator);
            }
        }
    };
    pub const Value = union(enum) {
        newline: void,
        comment: []const u8,
        section: []const u8,
        key: []const u8,
        value: ValueStr,
        rest: []const u8,
        pub fn format(self: Value, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print(@typeName(Value) ++ "{{ .{s}", .{@tagName(self)});
            switch (self) {
                .newline => {},
                inline else => |v, T| {
                    try writer.writeAll(" = \"");
                    if (T != .value) {
                        try std.fmt.formatBuf(v, options, writer);
                    } else {
                        try std.fmt.formatBuf(v.str, options, writer);
                    }
                    try writer.writeByte('"');
                },
            }
            try writer.print(" }}", .{});
        }
        pub fn get_str(self: Value) []const u8 {
            return switch (self) {
                .newline => "\n",
                inline else => |v, T| if (T != .value) v else v.str,
            };
        }
    };
    pub fn deinit(self: Token, allocator: std.mem.Allocator) void {
        if (self.alloc) {
            switch (self.value) {
                .newline => {},
                inline else => |v, T| allocator.free(if (T != .value) v else v.str),
            }
        }
    }
};
pub const ReadState = union(enum) {
    begin: void,
    get_new_line: usize, //Line number
    read: struct { line: usize, type: enum { key, value, done } },
};
pub const IniLexer = struct {
    begin_i: usize = 0,
    end_i: usize = 0,
    read_state: ReadState = .begin,
    kv_delimiter: u8,
    comment_delimiter: u8,
    newline_delimiter: u8,
    alloc_strings: bool,
    source: []const u8,
    pub fn init(ini_str: []const u8, options: IniLexerOptions) !IniLexer {
        return .{
            .source = ini_str,
            .kv_delimiter = options.kv_delimiter,
            .comment_delimiter = options.comment_delimiter,
            .newline_delimiter = options.newline_delimiter,
            .alloc_strings = options.alloc_strings,
        };
    }
    fn readjust_end_i(self: *IniLexer) bool {
        if (std.mem.indexOfScalar(u8, self.source[self.begin_i..], self.newline_delimiter)) |nl| {
            self.end_i = self.begin_i + nl;
            return false;
        } else {
            if (self.end_i != self.source.len) {
                self.end_i = self.source.len;
                return false;
            } else return true;
        }
    }
    pub const Error = error{
        UnexpectedToken,
        NoKeyValueDelimiterFound,
        NoClosingSquareBracket,
        NoClosingDoubleQuotes,
    } || std.mem.Allocator.Error;
    pub fn next(self: *IniLexer, allocator: std.mem.Allocator) Error!?Token {
        if (self.end_i == self.source.len and self.begin_i == self.source.len) return null;
        while (true) {
            switch (self.read_state) {
                .begin => {
                    _ = self.readjust_end_i(); //Adjust to first \n.
                    self.read_state = .{ .get_new_line = 0 };
                },
                .get_new_line => |lnum| {
                    while (std.ascii.isWhitespace(self.source[self.begin_i])) {
                        if (self.begin_i == self.end_i) {
                            self.begin_i += 1;
                            if (self.readjust_end_i()) return null;
                        } else self.begin_i += 1;
                        if (self.begin_i == self.source.len) return null;
                    }
                    self.read_state = .{ .read = .{ .line = lnum, .type = .key } };
                },
                .read => |*rl| {
                    if (self.begin_i == self.end_i) { //Edge case where begin_i is already at end_i
                        self.read_state = .{ .get_new_line = rl.line + 1 };
                        return .{
                            .value = .newline,
                            .alloc = false,
                        };
                    }
                    while (std.ascii.isWhitespace(self.source[self.begin_i])) {
                        self.begin_i += 1;
                        if (self.begin_i == self.end_i) {
                            self.read_state = .{ .get_new_line = rl.line + 1 };
                            return .{
                                .value = .newline,
                                .alloc = false,
                            };
                        }
                    }
                    switch (self.source[self.begin_i]) {
                        '[' => {
                            self.begin_i += 1;
                            while (std.ascii.isWhitespace(self.source[self.begin_i])) {
                                self.begin_i += 1;
                                if (self.begin_i == self.end_i)
                                    return Error.NoClosingSquareBracket;
                            }
                            const section_i = self.begin_i;
                            var bracket_i: usize = self.begin_i;
                            while (self.source[bracket_i] != ']') {
                                bracket_i += 1;
                                if (bracket_i == self.end_i)
                                    return Error.NoClosingSquareBracket;
                            }
                            const section_str = std.mem.trim(u8, self.source[section_i..bracket_i], &std.ascii.whitespace);
                            self.begin_i = bracket_i + 1;
                            rl.type = .done; //Prevent keys/value from parsing this line
                            return .{
                                .value = .{
                                    .section = if (self.alloc_strings) try allocator.dupe(u8, section_str) else section_str,
                                },
                                .alloc = self.alloc_strings,
                            };
                        },
                        else => |c| {
                            if (c == self.comment_delimiter) {
                                const start_comment_i: usize = self.begin_i + 1;
                                self.begin_i = self.end_i;
                                var return_str = self.source[start_comment_i..self.end_i];
                                if (return_str[return_str.len - 1] == '\r') return_str.len -= 1;
                                return .{
                                    .value = .{
                                        .comment = if (self.alloc_strings) try allocator.dupe(u8, return_str) else return_str,
                                    },
                                    .alloc = self.alloc_strings,
                                };
                            }
                            if (rl.type == .done) {
                                return Error.UnexpectedToken;
                            } else if (rl.type == .key) {
                                const old_begin_i = self.begin_i;
                                var delimiter_i: usize = self.begin_i;
                                while (self.source[delimiter_i] != self.kv_delimiter) {
                                    delimiter_i += 1;
                                    if (delimiter_i == self.end_i)
                                        return Error.NoKeyValueDelimiterFound;
                                }
                                var key_str = self.source[self.begin_i..delimiter_i];
                                const spaces_i: usize = key_str.len; //Spaces before delimiter sign if any.
                                key_str = std.mem.trim(u8, key_str, &std.ascii.whitespace);
                                rl.type = .value;
                                self.begin_i += spaces_i + 1;
                                const return_str = self.source[old_begin_i .. old_begin_i + key_str.len];
                                return .{
                                    .value = .{
                                        .key = if (self.alloc_strings) try allocator.dupe(u8, return_str) else return_str,
                                    },
                                    .alloc = self.alloc_strings,
                                };
                            } else {
                                const old_begin_i = self.begin_i;
                                if (self.source[self.begin_i] != '"') {
                                    var non_ws_i: usize = self.begin_i;
                                    var c2 = self.source[non_ws_i];
                                    while (!std.ascii.isWhitespace(c2) and c2 != self.comment_delimiter) : (c2 = self.source[non_ws_i]) {
                                        non_ws_i += 1;
                                        if (non_ws_i == self.end_i) break; //At end of file with no whitespaces.
                                    }
                                    rl.type = .done;
                                    self.begin_i = non_ws_i;
                                    const return_str = self.source[old_begin_i..non_ws_i];
                                    return .{
                                        .value = .{
                                            .value = .{ .str = if (self.alloc_strings) try allocator.dupe(u8, return_str) else return_str },
                                        },
                                        .alloc = self.alloc_strings,
                                    };
                                } else {
                                    var quote_i: usize = self.begin_i + 1;
                                    var using_escaped: bool = false;
                                    while (true) {
                                        if (!using_escaped) {
                                            if (self.source[quote_i] == '"') break;
                                            if (self.source[quote_i] == '\\') using_escaped = true;
                                        } else {
                                            using_escaped = false;
                                        }
                                        quote_i += 1;
                                        if (quote_i == self.end_i) return Error.NoClosingDoubleQuotes;
                                    }
                                    rl.type = .done;
                                    self.begin_i = quote_i + 1;
                                    const return_str = self.source[old_begin_i + 1 .. quote_i];
                                    return .{
                                        .value = .{
                                            .value = .{ .str = if (self.alloc_strings) try allocator.dupe(u8, return_str) else return_str },
                                        },
                                        .alloc = self.alloc_strings,
                                    };
                                }
                            }
                        },
                    }
                },
            }
        }
    }
    ///The rest of the string.
    pub fn done(self: *IniLexer, allocator: std.mem.Allocator) Error!?Token {
        if (self.end_i == self.source.len and self.begin_i == self.source.len) return null;
        const old_begin_i = self.begin_i;
        self.begin_i = self.source.len;
        self.end_i = self.source.len;
        const return_str = self.source[old_begin_i..self.end_i];
        return .{
            .value = .{
                .value = if (self.alloc_strings) try allocator.dupe(u8, return_str) else return_str,
            },
            .alloc = self.alloc_strings,
        };
    }
};
test IniLexer {
    const allocator = std.testing.allocator;
    const ini_string =
        \\ ;ab=cd
        \\efg  =  hijk
        \\lm=nop;commentnospace
        \\[not global] ;comment again but space
        \\[     spaces are trimmed here   ]
        \\qr= stuv ;4th comment here
        \\qr = "  allow     spaces ";5th
        \\qr = ";not comment because inside double quotes"
        \\
    ;
    const token_value_arr = [_]Token.Value{
        .{ .comment = "ab=cd" },
        .newline,
        .{ .key = "efg" },
        .{ .value = .{ .str = "hijk" } },
        .newline,
        .{ .key = "lm" },
        .{ .value = .{ .str = "nop" } },
        .{ .comment = "commentnospace" },
        .newline,
        .{ .section = "not global" },
        .{ .comment = "comment again but space" },
        .newline,
        .{ .section = "spaces are trimmed here" },
        .newline,
        .{ .key = "qr" },
        .{ .value = .{ .str = "stuv" } },
        .{ .comment = "4th comment here" },
        .newline,
        .{ .key = "qr" },
        .{ .value = .{ .str = "  allow     spaces " } },
        .{ .comment = "5th" },
        .newline,
        .{ .key = "qr" },
        .{ .value = .{ .str = ";not comment because inside double quotes" } },
        .newline,
    };
    var token_value_i: usize = 0;
    var ini_lexer = try IniLexer.init(ini_string, .{});
    var ini_save: IniSave = .{};
    defer ini_save.deinit(allocator);
    while (ini_lexer.next(allocator)) |is_t| : (token_value_i += 1) {
        if (is_t) |t| {
            defer t.deinit(allocator);
            try ini_save.tokens.append(allocator, t);
            try std.testing.expect(std.meta.activeTag(t.value) == std.meta.activeTag(token_value_arr[token_value_i]));
            try std.testing.expect(std.mem.eql(u8, t.value.get_str(), token_value_arr[token_value_i].get_str()));
        } else break;
    } else |e| {
        std.debug.print("Error: {any}\n", .{e});
        return e;
    }
    var arraylist: std.ArrayListUnmanaged(u8) = .{};
    defer arraylist.deinit(allocator);
    try std.testing.expectEqual(IniSave.VerifyStatus.ok, ini_save.save(arraylist.writer(allocator), .{}));
    const expected_output =
        \\;ab=cd
        \\efg = hijk
        \\lm = nop ;commentnospace
        \\[not global] ;comment again but space
        \\[spaces are trimmed here]
        \\qr = stuv ;4th comment here
        \\qr = "  allow     spaces " ;5th
        \\qr = ";not comment because inside double quotes"
        \\
    ;
    try std.testing.expectEqualStrings(expected_output, arraylist.items);
}

pub const IniLexerFileOptions = struct {
    kv_delimiter: u8 = '=',
    comment_delimiter: u8 = ';',
    newline_delimiter: u8 = '\n',
    line_maximum_bytes: usize = 1024,
};

pub const IniLexerFile = struct {
    read_i: usize = 0,
    end_i: usize = 0,
    read_state: ReadState = .begin,
    kv_delimiter: u8,
    comment_delimiter: u8,
    newline_delimiter: u8,
    line_maximum_bytes: usize,
    line: []const u8 = &.{},
    source: std.fs.File,
    pub fn init(dir: std.fs.Dir, file_str: []const u8, options: IniLexerFileOptions) !IniLexerFile {
        return .{
            .kv_delimiter = options.kv_delimiter,
            .comment_delimiter = options.comment_delimiter,
            .newline_delimiter = options.newline_delimiter,
            .line_maximum_bytes = options.line_maximum_bytes,
            .source = try dir.openFile(file_str, .{}),
        };
    }
    fn parse_new_line(self: *IniLexerFile, allocator: std.mem.Allocator) !bool {
        allocator.free(self.line);
        const line = try self.source.reader().readUntilDelimiterOrEofAlloc(allocator, self.newline_delimiter, self.line_maximum_bytes);
        if (line) |l| {
            self.line = l;
            self.read_i = 0;
            self.end_i = self.line.len;
            return true;
        } else {
            self.line = &.{};
            return false;
        }
    }
    pub const Error = error{
        UnexpectedToken,
        NoKeyValueDelimiterFound,
        NoClosingSquareBracket,
        NoClosingDoubleQuotes,
    } || std.mem.Allocator.Error || std.fs.File.OpenError || std.posix.ReadError || error{StreamTooLong};
    pub fn next(self: *IniLexerFile, allocator: std.mem.Allocator) Error!?Token {
        while (true) {
            switch (self.read_state) {
                .begin => {
                    if (!try self.parse_new_line(allocator)) return null;
                    self.read_state = .{ .read = .{ .line = 0, .type = .key } };
                },
                .get_new_line => |lnum| {
                    if (!try self.parse_new_line(allocator)) return null;
                    self.read_state = .{ .read = .{ .line = lnum + 1, .type = .key } };
                },
                .read => |*rl| {
                    if (self.read_i == self.line.len) { //Edge case where read_i is already at end of self.line
                        self.read_state = .{ .get_new_line = rl.line + 1 };
                        return .{
                            .value = .newline,
                            .alloc = false,
                        };
                    }
                    while (std.ascii.isWhitespace(self.line[self.read_i])) {
                        self.read_i += 1;
                        if (self.read_i == self.line.len) {
                            self.read_state = .{ .get_new_line = rl.line + 1 };
                            return .{
                                .value = .newline,
                                .alloc = false,
                            };
                        }
                    }
                    switch (self.line[self.read_i]) {
                        '[' => {
                            self.read_i += 1;
                            while (std.ascii.isWhitespace(self.line[self.read_i])) {
                                self.read_i += 1;
                                if (self.read_i == self.end_i)
                                    return Error.NoClosingSquareBracket;
                            }
                            const section_i = self.read_i;
                            var bracket_i: usize = self.read_i;
                            while (self.line[bracket_i] != ']') {
                                bracket_i += 1;
                                if (bracket_i == self.end_i)
                                    return Error.NoClosingSquareBracket;
                            }
                            const section_str = std.mem.trim(u8, self.line[section_i..bracket_i], &std.ascii.whitespace);
                            self.read_i = bracket_i + 1;
                            rl.type = .done; //Prevent keys/value from parsing this line
                            return .{
                                .value = .{
                                    .section = try allocator.dupe(u8, section_str),
                                },
                                .alloc = true,
                            };
                        },
                        else => |c| {
                            if (c == self.comment_delimiter) {
                                const start_comment_i: usize = self.read_i + 1;
                                self.read_i = self.line.len;
                                var return_str = self.line[start_comment_i..self.line.len];
                                if (return_str[return_str.len - 1] == '\r') return_str.len -= 1;
                                return .{
                                    .value = .{
                                        .comment = try allocator.dupe(u8, return_str),
                                    },
                                    .alloc = true,
                                };
                            }
                            if (rl.type == .done) {
                                return Error.UnexpectedToken;
                            } else if (rl.type == .key) {
                                const old_begin_i = self.read_i;
                                var delimiter_i: usize = self.read_i;
                                while (self.line[delimiter_i] != self.kv_delimiter) {
                                    delimiter_i += 1;
                                    if (delimiter_i == self.end_i)
                                        return Error.NoKeyValueDelimiterFound;
                                }
                                var key_str = self.line[self.read_i..delimiter_i];
                                const spaces_i: usize = key_str.len; //Spaces before delimiter sign if any.
                                key_str = std.mem.trim(u8, key_str, &std.ascii.whitespace);
                                rl.type = .value;
                                self.read_i += spaces_i + 1;
                                const return_str = self.line[old_begin_i .. old_begin_i + key_str.len];
                                return .{
                                    .value = .{
                                        .key = try allocator.dupe(u8, return_str),
                                    },
                                    .alloc = true,
                                };
                            } else {
                                const old_begin_i = self.read_i;
                                if (self.line[self.read_i] != '"') {
                                    var non_ws_i: usize = self.read_i;
                                    var c2 = self.line[non_ws_i];
                                    while (!std.ascii.isWhitespace(c2) and c2 != self.comment_delimiter) : (c2 = self.line[non_ws_i]) {
                                        non_ws_i += 1;
                                        if (non_ws_i == self.line.len) break; //At end of file with no whitespaces.
                                    }
                                    rl.type = .done;
                                    self.read_i = non_ws_i;
                                    const return_str = self.line[old_begin_i..non_ws_i];
                                    return .{
                                        .value = .{
                                            .value = .{ .str = try allocator.dupe(u8, return_str) },
                                        },
                                        .alloc = true,
                                    };
                                } else {
                                    var quote_i: usize = self.read_i + 1;
                                    var using_escaped: bool = false;
                                    while (true) {
                                        if (!using_escaped) {
                                            if (self.line[quote_i] == '"') break;
                                            if (self.line[quote_i] == '\\') using_escaped = true;
                                        } else {
                                            using_escaped = false;
                                        }
                                        quote_i += 1;
                                        if (quote_i == self.line.len) return Error.NoClosingDoubleQuotes;
                                    }
                                    rl.type = .done;
                                    self.read_i = quote_i + 1;
                                    const return_str = self.line[old_begin_i + 1 .. quote_i];
                                    return .{
                                        .value = .{
                                            .value = .{ .str = try allocator.dupe(u8, return_str) },
                                        },
                                        .alloc = true,
                                    };
                                }
                            }
                        },
                    }
                },
            }
        }
    }

    pub fn deinit(self: IniLexerFile, allocator: std.mem.Allocator) void {
        allocator.free(self.line);
        self.source.close();
    }
};

test IniLexerFile {
    const allocator = std.testing.allocator;
    var ilf = try IniLexerFile.init(std.fs.cwd(), "testfile.ini", .{});
    defer ilf.deinit(allocator);
    const token_value_arr = [_]Token.Value{
        .{ .section = "A section" },
        .{ .comment = "A comment" },
        .newline,
        .{ .key = "key1" },
        .{ .value = .{ .str = "value1" } },
        .newline,
        .{ .key = "key2" },
        .{ .value = .{ .str = "  value 2  " } },
        .{ .comment = "With comment" },
        .newline,
        .{ .comment = "Newline comment ;This delimiter does nothing" },
        .newline,
        .{ .key = "key3" },
        .{ .value = .{ .str = "value3\\\" with escaped quote" } },
        .newline,
    };
    var token_value_i: usize = 0;
    while (ilf.next(allocator)) |t_op| : (token_value_i += 1) {
        if (t_op) |t| {
            defer t.deinit(allocator);
            try std.testing.expect(std.meta.activeTag(t.value) == std.meta.activeTag(token_value_arr[token_value_i]));
            try std.testing.expect(std.mem.eql(u8, t.value.get_str(), token_value_arr[token_value_i].get_str()));
        } else break;
    } else |e| {
        std.debug.print("Error: {!}\n", .{e});
        return e;
    }
}

pub const IniSave = struct {
    tokens: std.ArrayListUnmanaged(Token) = .{},
    ///Statuses with usize outputs the token index where the error occured.
    pub const VerifyStatus = union(enum) {
        ok: void,
        next_token_should_be_newline: usize,
        next_token_should_be_value: usize,
        next_token_should_be_newline_or_comment: usize,
        last_token_as_key_missing_value: void,
        rest_token_should_be_last: void,
    };
    pub fn verify(self: IniSave) VerifyStatus {
        for (0..self.tokens.items.len - 1) |w| {
            const this_token = self.tokens.items[w];
            const next_token = self.tokens.items[w + 1];
            switch (this_token.value) {
                .newline => {},
                .comment => {
                    if (next_token.value != .newline)
                        return .{ .next_token_should_be_newline = w + 1 };
                },
                .section => {
                    if (next_token.value != .newline and next_token.value != .comment)
                        return .{ .next_token_should_be_newline_or_comment = w + 1 };
                },
                .key => {
                    if (next_token.value != .value)
                        return .{ .next_token_should_be_value = w + 1 };
                },
                .value => {
                    if (next_token.value != .newline and next_token.value != .comment)
                        return .{ .next_token_should_be_newline_or_comment = w + 1 };
                },
                .rest => return .rest_token_should_be_last,
            }
        }
        if (self.tokens.getLast().value == .key)
            return .last_token_as_key_missing_value;
        return .ok;
    }
    pub const SaveStrOptions = struct {
        kv_delimiter: u8 = '=',
        comment_delimiter: u8 = ';',
        newline_delimiter: []const u8 = "\n",
    };
    pub fn save(self: IniSave, writer: anytype, options: SaveStrOptions) !VerifyStatus {
        const status = self.verify();
        if (status != .ok) return status;
        for (0..self.tokens.items.len) |i| {
            const token = self.tokens.items[i];
            switch (token.value) {
                .newline => try writer.writeAll(options.newline_delimiter),
                .comment => |s| {
                    if (i != 0 and self.tokens.items[i - 1].value != .newline) {
                        try writer.print(" {c}{s}", .{ options.comment_delimiter, s });
                    } else {
                        try writer.print("{c}{s}", .{ options.comment_delimiter, s });
                    }
                },
                .section => |s| try writer.print("[{s}]", .{s}),
                .key => |s| try writer.print("{s} {c} ", .{ s, options.kv_delimiter }),
                .value => |s| for (s.str) |ch| {
                    if (std.ascii.isWhitespace(ch)) {
                        try writer.print("\"{s}\"", .{s.str});
                        break;
                    }
                } else try writer.print("{s}", .{s.str}),
                .rest => |s| {
                    try writer.print("{s}", .{s});
                },
            }
        }
        return .ok;
    }
    pub fn deinit(self: *IniSave, allocator: std.mem.Allocator) void {
        self.tokens.deinit(allocator);
    }
};
