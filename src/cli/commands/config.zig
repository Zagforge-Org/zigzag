const std = @import("std");
const options = @import("../options.zig").options;

pub const VERSION = "0.9.0";

/// ConfigParseResult represents the result of parsing a configuration.
pub const ConfigParseResult = union(enum) {
    Success: Config,
    MissingValue: []const u8,
    UnknownOption: []const u8,
    Other: []const u8,
};

/// Config represents the configuration for the application.
pub const Config = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList([]const u8),
    small_threshold: usize,
    mmap_threshold: usize,
    skip_git: bool,
    skip_cache: bool,
    ignore_patterns: []const u8,
    n_threads: usize,
    timezone_offset: ?i64, // Offset in seconds from UTC (e.g., 3600 for UTC+1)
    version: []const u8 = VERSION,

    const Self = @This();

    /// Initializes a default configuration.
    pub fn initDefault(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .paths = .empty,
            .small_threshold = 1 << 20,
            .mmap_threshold = 16 << 20,
            .skip_git = false,
            .skip_cache = false,
            .ignore_patterns = "",
            .n_threads = std.Thread.getCpuCount() catch 1,
            .timezone_offset = null, // Default to UTC
        };
    }

    /// Parses command-line arguments and returns a ConfigParseResult.
    pub fn parse(args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
        var cfg = Self.initDefault(allocator);
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

    pub fn deinit(self: *Self) void {
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }
        self.paths.deinit(self.allocator);
    }
};
