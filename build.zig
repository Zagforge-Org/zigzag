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

    // Testing
    const test_step = b.step("test", "Run library and executable tests");

    // Module Tests (Unit tests in src/root.zig and its children)
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    // Executable Tests (Unit tests in src/main.zig)
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    exe_tests.root_module.addImport("options", opts_mod);

    const run_exe_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_exe_tests.step);
}
