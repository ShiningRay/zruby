const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const allow_untested_zig = b.option(
        bool,
        "allow-untested-zig",
        "Attempt a build with a Zig version other than the pinned 0.16.x",
    ) orelse false;
    if (!allow_untested_zig and
        (builtin.zig_version.major != 0 or builtin.zig_version.minor != 16))
    {
        @panic("zruby is pinned to Zig 0.16.x; see docs/compatibility.md or pass -Dallow-untested-zig");
    }

    const allow_untested_mruby = b.option(
        bool,
        "allow-untested-mruby",
        "Attempt a build with an mruby 4.x minor other than 4.0",
    ) orelse false;

    // Point this at an mruby install prefix containing include/ and lib/.
    // Defaults to the output of `scripts/build-mruby.sh`.
    const mruby_prefix = b.option(
        []const u8,
        "mruby-prefix",
        "mruby install prefix containing include/ and lib/ (default: vendor/mruby/build/host)",
    ) orelse "vendor/mruby/build/host";

    const mruby_boxing = b.option(
        []const u8,
        "mruby-boxing",
        "mruby value layout: word (default), nan, or none",
    ) orelse "word";
    if (!std.mem.eql(u8, mruby_boxing, "word") and
        !std.mem.eql(u8, mruby_boxing, "nan") and
        !std.mem.eql(u8, mruby_boxing, "none"))
    {
        @panic("mruby-boxing must be word, nan, or none");
    }
    const mruby_bigint = b.option(
        bool,
        "mruby-bigint",
        "mruby build has MRB_USE_BIGINT (default true)",
    ) orelse true;

    const mruby_include = lazyPath(b, b.fmt("{s}/include", .{mruby_prefix}));
    const mruby_lib = lazyPath(b, b.fmt("{s}/lib", .{mruby_prefix}));

    const zruby_mod = b.addModule("zruby", .{
        .root_source_file = b.path("src/zruby.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const options = b.addOptions();
    options.addOption([]const u8, "mruby_boxing", mruby_boxing);
    zruby_mod.addOptions("zruby_options", options);

    zruby_mod.addIncludePath(mruby_include);
    zruby_mod.addLibraryPath(mruby_lib);
    zruby_mod.linkSystemLibrary("mruby", .{});
    if (target.result.os.tag == .linux) {
        zruby_mod.linkSystemLibrary("m", .{});
    }
    if (target.result.os.tag == .windows) {
        zruby_mod.linkSystemLibrary("ws2_32", .{});
        zruby_mod.linkSystemLibrary("wsock32", .{});
    }

    // Keep the bridge in sync with mruby's default build configuration.
    zruby_mod.addCMacro("MRB_USE_SET", "1");
    zruby_mod.addCMacro("HAVE_MRUBY_IO_GEM", "1");
    zruby_mod.addCMacro("MRB_USE_RATIONAL", "1");
    zruby_mod.addCMacro("MRB_USE_COMPLEX", "1");
    if (mruby_bigint) zruby_mod.addCMacro("MRB_USE_BIGINT", "1");
    zruby_mod.addCMacro("MRB_USE_DEBUG_HOOK", "1");
    zruby_mod.addCMacro("MRB_NO_DEFAULT_RO_DATA_P", "1");
    if (std.mem.eql(u8, mruby_boxing, "nan")) {
        zruby_mod.addCMacro("MRB_NAN_BOXING", "1");
        zruby_mod.addCMacro("MRB_INT64", "1");
    } else if (std.mem.eql(u8, mruby_boxing, "none")) {
        zruby_mod.addCMacro("MRB_NO_BOXING", "1");
        zruby_mod.addCMacro("MRB_INT64", "1");
    }
    if (allow_untested_mruby) {
        zruby_mod.addCMacro("ZRUBY_ALLOW_ANY_MRUBY_4", "1");
    }
    zruby_mod.addCSourceFile(.{
        .file = b.path("src/shim.c"),
        .flags = &.{"-std=c99"},
    });

    // Static library artifact for C/Zig consumers that link mruby themselves.
    const lib = b.addLibrary(.{
        .name = "zruby",
        .root_module = zruby_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/all.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zruby", .module = zruby_mod }},
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the test suite");
    test_step.dependOn(&run_tests.step);

    const nonbigint_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/nonbigint.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zruby", .module = zruby_mod }},
        }),
    });
    const run_nonbigint_tests = b.addRunArtifact(nonbigint_tests);
    const nonbigint_step = b.step("test-nonbigint", "Run the non-BigInt hash regression test");
    nonbigint_step.dependOn(&run_nonbigint_tests.step);

    const example = b.addExecutable(.{
        .name = "zruby-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/embed.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zruby", .module = zruby_mod }},
        }),
    });
    b.installArtifact(example);
    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);
    run_example.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the embedding example");
    run_step.dependOn(&run_example.step);
}

fn lazyPath(b: *std.Build, p: []const u8) std.Build.LazyPath {
    if (std.fs.path.isAbsolute(p)) return .{ .cwd_relative = p };
    return b.path(p);
}
