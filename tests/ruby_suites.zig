const std = @import("std");
const zruby = @import("zruby");
const common = @import("common.zig");

fn runSuite(name: [:0]const u8, source: []const u8) !void {
    var vm = try common.newVM();
    defer vm.deinit();

    _ = vm.evalWithOptions(source, .{ .filename = name }) catch |err| {
        std.debug.print(
            "Ruby suite {s} failed: {s}: {s}\n",
            .{
                name,
                vm.lastErrorClass() orelse "unknown",
                vm.lastError() orelse @errorName(err),
            },
        );
        return err;
    };
}

test "Ruby core language suite" {
    try runSuite("tests/ruby/core_language.rb", @embedFile("ruby/core_language.rb"));
}

test "Ruby numerics suite" {
    try runSuite("tests/ruby/numerics.rb", @embedFile("ruby/numerics.rb"));
}

test "Ruby collections suite" {
    try runSuite("tests/ruby/collections.rb", @embedFile("ruby/collections.rb"));
}

test "Ruby exceptions suite" {
    try runSuite("tests/ruby/exceptions.rb", @embedFile("ruby/exceptions.rb"));
}

test "Ruby stdlib smoke suite" {
    try runSuite("tests/ruby/stdlib.rb", @embedFile("ruby/stdlib.rb"));
}
