const std = @import("std");
const options = @import("options.zig").options;

pub const VERSION = "0.1.0"; // Bump accordingly

pub const ConfigParseResult = union(enum) {
    Success: Config,
    MissingValue: []const u8,
    UnknownOption: []const u8,
    Other: []const u8,
};

pub const Config = struct {
    path: []const u8,
    small_threshold: usize,
    mmap_threshold: usize,
    skip_git: bool,
    skip_cache: bool,
    ignore_patterns: []const u8,
    n_threads: usize,
    version: []const u8 = VERSION,

    const Self = @This();

    fn initDefault() Self {
        return Self{
            .path = ".",
            .small_threshold = 1 << 20,
            .mmap_threshold = 16 << 20,
            .skip_git = false,
            .skip_cache = false,
            .ignore_patterns = "",
            .n_threads = std.Thread.getCpuCount() catch 1,
        };
    }

    pub fn parse(args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
        var cfg = Self.initDefault();

        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            var handled = false;

            for (options) |opt| {
                if (std.mem.eql(u8, arg, opt.name)) {
                    var value: ?[]const u8 = null;

                    if (opt.takes_value) {
                        i += 1;
                        if (i < args.len) {
                            value = args[i];
                        } else {
                            return ConfigParseResult{ .MissingValue = opt.name };
                        }
                    }

                    opt.handler(&cfg, allocator, value) catch |err| {
                        const err_name = @errorName(err);
                        return ConfigParseResult{ .Other = err_name };
                    };

                    handled = true;
                    break;
                }
            }

            if (!handled) {
                return ConfigParseResult{ .UnknownOption = arg };
            }
        }

        return ConfigParseResult{ .Success = cfg };
    }
};
