const std = @import("std");

// Pull the version string directly from the ZON file at compile-time
const version_string = @import("build.zig.zon").version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Regenerate src/test_manifest.zig from every *_test.zig on disk, so a new
    // test file is picked up automatically instead of being silently forgotten.
    generateTestManifest(b);

    // Parse Version
    const version = std.SemanticVersion.parse(version_string) catch |err| {
        std.debug.print("Failed to parse version '{s}': {}\n", .{ version_string, err });
        @panic("Bad version string");
    };

    // Setup Options Module
    const opts = b.addOptions();
    opts.addOption(std.SemanticVersion, "version", version);
    opts.addOption([]const u8, "version_string", @as([]const u8, version_string));
    const opts_mod = opts.createModule();

    // Setup Python bundle (esbuild + injection pass)
    // npm install only runs when node_modules is absent (bundle.py handles the check).
    const bundle = b.addSystemCommand(&.{ "python3", "src/templates/bundle.py" });
    bundle.addArgs(&.{});
    // _ = bundle.captureStdOut();
    const bundle_step = b.step("bundle", "Regenerate src/templates/dashboard.html");
    bundle_step.dependOn(&bundle.step);

    // Define the Library Module ("zigzag")
    const mod = b.addModule("zigzag", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Inject options into the library module
    mod.addImport("options", opts_mod);
    mod.link_libc = true;

    // AST chunker — tree-sitter C sources
    mod.addCSourceFiles(.{
        .root = b.path("ast/vendor/tree-sitter/lib/src"),
        .files = &.{
            "alloc.c",   "get_changed_ranges.c", "language.c", "lexer.c",
            "node.c",    "parser.c",             "query.c",    "stack.c",
            "subtree.c", "tree_cursor.c",        "tree.c",     "wasm_store.c",
        },
        .flags = &.{"-std=gnu99"},
    });
    mod.addCSourceFiles(.{
        .root = b.path("ast"),
        .files = &.{
            "grammars/tree-sitter-python/src/parser.c",
            "grammars/tree-sitter-python/src/scanner.c",
            "grammars/tree-sitter-javascript/src/parser.c",
            "grammars/tree-sitter-javascript/src/scanner.c",
            "grammars/tree-sitter-zig/src/parser.c",
            "grammars/tree-sitter-typescript/typescript/src/parser.c",
            "grammars/tree-sitter-typescript/typescript/src/scanner.c",
            "grammars/tree-sitter-typescript/tsx/src/parser.c",
            "grammars/tree-sitter-typescript/tsx/src/scanner.c",
            "grammars/tree-sitter-rust/src/parser.c",
            "grammars/tree-sitter-rust/src/scanner.c",
            "grammars/tree-sitter-go/src/parser.c",
            "grammars/tree-sitter-c/src/parser.c",
            "grammars/tree-sitter-cpp/src/parser.c",
            "grammars/tree-sitter-cpp/src/scanner.c",
            "grammars/tree-sitter-java/src/parser.c",
            "grammars/tree-sitter-c-sharp/src/parser.c",
            "grammars/tree-sitter-c-sharp/src/scanner.c",
            "grammars/tree-sitter-ruby/src/parser.c",
            "grammars/tree-sitter-ruby/src/scanner.c",
            "grammars/tree-sitter-elixir/src/parser.c",
            "grammars/tree-sitter-elixir/src/scanner.c",
            "grammars/tree-sitter-kotlin/src/parser.c",
            "grammars/tree-sitter-kotlin/src/scanner.c",
            "grammars/tree-sitter-swift/src/parser.c",
            "grammars/tree-sitter-swift/src/scanner.c",
            "grammars/tree-sitter-lua/src/parser.c",
            "grammars/tree-sitter-lua/src/scanner.c",
            "grammars/tree-sitter-bash/src/parser.c",
            "grammars/tree-sitter-bash/src/scanner.c",
            "grammars/tree-sitter-php/php/src/parser.c",
            "grammars/tree-sitter-php/php/src/scanner.c",
            "src/chunker.c",
        },
        .flags = &.{"-std=gnu11"},
    });
    mod.addIncludePath(b.path("ast/vendor/tree-sitter/lib/include"));
    mod.addIncludePath(b.path("ast/vendor/tree-sitter/lib/src"));
    mod.addIncludePath(b.path("ast/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-python/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-javascript/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-zig/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-typescript/typescript/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-typescript/tsx/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-rust/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-go/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-c/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-cpp/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-java/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-c-sharp/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-ruby/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-elixir/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-kotlin/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-swift/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-lua/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-bash/src"));
    mod.addIncludePath(b.path("ast/grammars/tree-sitter-php/php/src"));

    // Define the Executable
    const exe = b.addExecutable(.{
        .name = "zigzag",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigzag", .module = mod },
                .{ .name = "options", .module = opts_mod },
            },
        }),
        // The Zig 0.16.0 self-hosted x86 backend/linker cannot yet emit some
        // relocations used here (R_X86_64_PC64), so build through LLVM.
        .use_llvm = true,
    });
    exe.root_module.link_libc = true;

    // Ensure the binary is built after the bundle is ready
    exe.step.dependOn(&bundle.step);
    b.installArtifact(exe);

    // Run Command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Testing — use fallback options (version 0.0.0) so isRuntime() = true and runtime tests run
    const fallback_opts_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/version/fallback.zig"),
    });

    const test_step = b.step("test", "Run library and executable tests");

    // Module Tests (Unit tests in src/root.zig and its children)
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("options", fallback_opts_mod);
    test_mod.link_libc = true;
    test_mod.addCSourceFiles(.{
        .root = b.path("ast/vendor/tree-sitter/lib/src"),
        .files = &.{
            "alloc.c",   "get_changed_ranges.c", "language.c", "lexer.c",
            "node.c",    "parser.c",             "query.c",    "stack.c",
            "subtree.c", "tree_cursor.c",        "tree.c",     "wasm_store.c",
        },
        .flags = &.{"-std=gnu99"},
    });
    test_mod.addCSourceFiles(.{
        .root = b.path("ast"),
        .files = &.{
            "grammars/tree-sitter-python/src/parser.c",
            "grammars/tree-sitter-python/src/scanner.c",
            "grammars/tree-sitter-javascript/src/parser.c",
            "grammars/tree-sitter-javascript/src/scanner.c",
            "grammars/tree-sitter-zig/src/parser.c",
            "grammars/tree-sitter-typescript/typescript/src/parser.c",
            "grammars/tree-sitter-typescript/typescript/src/scanner.c",
            "grammars/tree-sitter-typescript/tsx/src/parser.c",
            "grammars/tree-sitter-typescript/tsx/src/scanner.c",
            "grammars/tree-sitter-rust/src/parser.c",
            "grammars/tree-sitter-rust/src/scanner.c",
            "grammars/tree-sitter-go/src/parser.c",
            "grammars/tree-sitter-c/src/parser.c",
            "grammars/tree-sitter-cpp/src/parser.c",
            "grammars/tree-sitter-cpp/src/scanner.c",
            "grammars/tree-sitter-java/src/parser.c",
            "grammars/tree-sitter-c-sharp/src/parser.c",
            "grammars/tree-sitter-c-sharp/src/scanner.c",
            "grammars/tree-sitter-ruby/src/parser.c",
            "grammars/tree-sitter-ruby/src/scanner.c",
            "grammars/tree-sitter-elixir/src/parser.c",
            "grammars/tree-sitter-elixir/src/scanner.c",
            "grammars/tree-sitter-kotlin/src/parser.c",
            "grammars/tree-sitter-kotlin/src/scanner.c",
            "grammars/tree-sitter-swift/src/parser.c",
            "grammars/tree-sitter-swift/src/scanner.c",
            "grammars/tree-sitter-lua/src/parser.c",
            "grammars/tree-sitter-lua/src/scanner.c",
            "grammars/tree-sitter-bash/src/parser.c",
            "grammars/tree-sitter-bash/src/scanner.c",
            "grammars/tree-sitter-php/php/src/parser.c",
            "grammars/tree-sitter-php/php/src/scanner.c",
            "src/chunker.c",
        },
        .flags = &.{"-std=gnu11"},
    });
    test_mod.addIncludePath(b.path("ast/vendor/tree-sitter/lib/include"));
    test_mod.addIncludePath(b.path("ast/vendor/tree-sitter/lib/src"));
    test_mod.addIncludePath(b.path("ast/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-python/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-javascript/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-zig/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-typescript/typescript/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-typescript/tsx/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-rust/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-go/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-c/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-cpp/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-java/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-c-sharp/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-ruby/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-elixir/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-kotlin/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-swift/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-lua/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-bash/src"));
    test_mod.addIncludePath(b.path("ast/grammars/tree-sitter-php/php/src"));

    const mod_tests = b.addTest(.{
        .root_module = test_mod,
        // build via LLVM (temporary).
        .use_llvm = true,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);
}

/// Walks src/ for `*_test.zig` and (re)writes `src/test_manifest.zig` a single
/// `test {}` block importing each one only when the content changes. Platform-gated
/// tests under platform/{linux,macos,windows}/ are excluded; root.zig imports those
/// behind `switch (builtin.os.tag)`. Best-effort: on any IO error it logs and skips,
/// leaving the previously generated manifest in place.
fn generateTestManifest(b: *std.Build) void {
    const io = b.graph.io;
    const gpa = b.allocator;

    var src_dir = b.build_root.handle.openDir(io, "src", .{ .iterate = true }) catch |err| {
        std.debug.print("test-manifest: cannot open src/: {s}\n", .{@errorName(err)});
        return;
    };
    defer src_dir.close(io);

    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);

    var walker = src_dir.walk(gpa) catch return;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, "_test.zig")) continue;

        const rel = gpa.dupe(u8, entry.path) catch continue;
        std.mem.replaceScalar(u8, rel, '\\', '/'); // normalize Windows separators
        // Platform-specific tests stay behind the os.tag switch in root.zig.
        if (std.mem.indexOf(u8, rel, "platform/linux/") != null or
            std.mem.indexOf(u8, rel, "platform/macos/") != null or
            std.mem.indexOf(u8, rel, "platform/windows/") != null) continue;
        paths.append(gpa, rel) catch continue;
    }

    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lessThan);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    const w = &out.writer;
    w.writeAll(
        \\// GENERATED by build.zig: do not edit, not checked in.
        \\// Auto-discovers every `*_test.zig` under src/ so a new test file is never forgotten.
        \\test {
        \\
    ) catch return;
    for (paths.items) |p| w.print("    _ = @import(\"{s}\");\n", .{p}) catch return;
    w.writeAll("}\n") catch return;
    const contents = out.written();

    // Only write when changed, so the build cache isn't invalidated every invocation.
    const existing = src_dir.readFileAlloc(io, "test_manifest.zig", gpa, .limited(1 << 20)) catch null;
    if (existing) |e| if (std.mem.eql(u8, e, contents)) return;

    src_dir.writeFile(io, .{ .sub_path = "test_manifest.zig", .data = contents }) catch |err| {
        std.debug.print("test-manifest: cannot write src/test_manifest.zig: {s}\n", .{@errorName(err)});
    };
}
