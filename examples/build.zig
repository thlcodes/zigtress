const std = @import("std");

const examples = .{"simple"};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const opts = .{ .target = target, .optimize = optimize };
    const zigtress_dep = b.dependency("zigtress", opts).module("zigtress");

    inline for (examples) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(example ++ "/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("zigtress", zigtress_dep);

        const exe = b.addExecutable(.{
            .name = "example-" ++ example,
            .root_module = exe_mod,
        });

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run-" ++ example, "Run the " ++ example ++ " example");
        run_step.dependOn(&run_cmd.step);
    }
}
