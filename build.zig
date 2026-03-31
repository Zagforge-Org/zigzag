const std = @import("std");

// Pull the version string directly from the ZON file at compile-time
const version_string = @import("build.zig.zon").version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    _ = bundle.captureStdOut();
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
            "alloc.c", "get_changed_ranges.c", "language.c", "lexer.c",
            "node.c",  "parser.c",             "query.c",   "stack.c",
            "subtree.c", "tree_cursor.c", "tree.c", "wasm_store.c",
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
            "alloc.c", "get_changed_ranges.c", "language.c", "lexer.c",
            "node.c",  "parser.c",             "query.c",   "stack.c",
            "subtree.c", "tree_cursor.c", "tree.c", "wasm_store.c",
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

    const mod_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);
}
