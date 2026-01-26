const std = @import("std");

pub fn build(b: *std.Build) void {
    // 1. Setup standard options (target and optimization)
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 2. Define the core module (the library part of your code)
    // This allows you to @import("zig_zag") in your main.zig or tests.
    const mod = b.addModule("zig_zag", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 3. Define the executable
    const exe = b.addExecutable(.{
        .name = "zig_zag",
        // We create a root module for the executable itself
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_zag", .module = mod },
            },
        }),
    });

    // Install the executable to zig-out/bin
    b.installArtifact(exe);

    // 4. Create the 'run' step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // 5. Setup Testing
    const test_step = b.step("test", "Run library and executable tests");

    // Test the library module (src/root.zig)
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    // Test the executable module (src/main.zig)
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_exe_tests.step);

    // Test the specific config file logic
    const config_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            // By using src/root.zig as the source, the module path is "src/"
            // This allows all relative imports like "../options.zig" to work.
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        // Optional: Only run tests that have "config" in their name
        // .filters = &.{ "config" },
    });

    // You still need to make sure the module itself is available if
    // root.zig or config.zig imports "zig_zag"
    config_unit_tests.root_module.addImport("zig_zag", mod);

    const run_config_unit_tests = b.addRunArtifact(config_unit_tests);
    test_step.dependOn(&run_config_unit_tests.step);
}
