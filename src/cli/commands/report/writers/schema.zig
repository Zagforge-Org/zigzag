//! Shared JSON section writers for the report dashboard schema. The HTML dashboard
//! embeds this as __ZIGZAG_DATA__ and the SSE writer streams the same shape, so both
//! draw from these builders.

const std = @import("std");
const Config = @import("../../config/Config.zig");
const JobEntry = @import("../../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../../jobs/entries.zig").BinaryEntry;
const LanguageStat = @import("aggregator.zig").LanguageStat;

/// version + watch_mode + (in watch mode) the SSE url.
fn writeBuildInfo(ws: *std.json.Stringify, allocator: std.mem.Allocator, cfg: *const Config) !void {
    try ws.objectField("version");
    try ws.write(cfg.version);
    try ws.objectField("watch_mode");
    try ws.write(cfg.watch);
    if (cfg.watch and cfg.html_output) {
        const sse_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/__events", .{cfg.serve_port});
        defer allocator.free(sse_url);
        try ws.objectField("sse_url");
        try ws.write(sse_url);
    }
}

pub const Meta = struct {
    ws: *std.json.Stringify,
    allocator: std.mem.Allocator,
    cfg: *const Config,
    root_path: []const u8,
    generated_at: []const u8,

    pub fn write(self: Meta) !void {
        const ws = self.ws;
        try ws.objectField("meta");
        try ws.beginObject();
        try ws.objectField("root_path");
        try ws.write(self.root_path);
        try ws.objectField("generated_at");
        try ws.write(self.generated_at);
        try writeBuildInfo(ws, self.allocator, self.cfg);
        try ws.endObject();
    }
};

pub const CombinedMeta = struct {
    ws: *std.json.Stringify,
    allocator: std.mem.Allocator,
    cfg: *const Config,
    path_count: usize,
    failed_paths: usize,
    file_count: usize,
    generated_at: []const u8,

    pub fn write(self: CombinedMeta) !void {
        const ws = self.ws;
        try ws.objectField("meta");
        try ws.beginObject();
        try ws.objectField("combined");
        try ws.write(true);
        try ws.objectField("path_count");
        try ws.write(self.path_count);
        try ws.objectField("successful_paths");
        try ws.write(self.path_count);
        try ws.objectField("failed_paths");
        try ws.write(self.failed_paths);
        try ws.objectField("file_count");
        try ws.write(self.file_count);
        try ws.objectField("generated_at");
        try ws.write(self.generated_at);
        try writeBuildInfo(ws, self.allocator, self.cfg);
        try ws.endObject();
    }
};

pub const Summary = struct {
    ws: *std.json.Stringify,
    source_files: usize,
    binary_files: usize,
    total_lines: usize,
    total_size: u64,
    langs: ?[]const LanguageStat = null,

    pub fn write(self: Summary) !void {
        const ws = self.ws;
        try ws.objectField("summary");
        try ws.beginObject();
        try ws.objectField("source_files");
        try ws.write(self.source_files);
        try ws.objectField("binary_files");
        try ws.write(self.binary_files);
        try ws.objectField("total_lines");
        try ws.write(self.total_lines);
        try ws.objectField("total_size_bytes");
        try ws.write(self.total_size);
        if (self.langs) |langs| {
            try ws.objectField("languages");
            try ws.beginArray();
            for (langs) |ls| {
                try ws.beginObject();
                try ws.objectField("name");
                try ws.write(ls.name);
                try ws.objectField("files");
                try ws.write(ls.files);
                try ws.objectField("lines");
                try ws.write(ls.lines);
                try ws.objectField("size_bytes");
                try ws.write(ls.size_bytes);
                try ws.endObject();
            }
            try ws.endArray();
        }
        try ws.endObject();
    }
};

pub const Files = struct {
    ws: *std.json.Stringify,
    items: []const JobEntry,
    root_path: ?[]const u8 = null,

    pub fn write(self: Files) !void {
        const ws = self.ws;
        try ws.objectField("files");
        try ws.beginArray();
        for (self.items) |e| {
            try ws.beginObject();
            try ws.objectField("path");
            try ws.write(e.path);
            if (self.root_path) |rp| {
                try ws.objectField("root_path");
                try ws.write(rp);
            }
            try ws.objectField("size");
            try ws.write(e.size);
            try ws.objectField("lines");
            try ws.write(e.line_count);
            try ws.objectField("language");
            try ws.write(e.getLanguage());
            try ws.endObject();
        }
        try ws.endArray();
    }
};

pub const Binaries = struct {
    ws: *std.json.Stringify,
    items: []const BinaryEntry,

    pub fn write(self: Binaries) !void {
        const ws = self.ws;
        try ws.objectField("binaries");
        try ws.beginArray();
        for (self.items) |b| {
            try ws.beginObject();
            try ws.objectField("path");
            try ws.write(b.path);
            try ws.objectField("size");
            try ws.write(b.size);
            try ws.endObject();
        }
        try ws.endArray();
    }
};
