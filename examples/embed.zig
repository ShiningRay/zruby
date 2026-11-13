const std = @import("std");
const zruby = @import("zruby");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const script_path = if (args.len > 1) args[1] else "examples/hello.rb";

    const source = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        script_path,
        init.gpa,
        .limited(1 << 20),
    ) catch |err| {
        std.debug.print("cannot read {s}: {s}\n", .{ script_path, @errorName(err) });
        return err;
    };
    defer init.gpa.free(source);

    var vm = try zruby.VM.init(init.gpa);
    defer vm.deinit();

    const zig_module = try vm.defineModule("Zig");
    try vm.defineModuleFunction(zig_module, "square", &zigSquare, zruby.args.req(1));

    const file_result = vm.evalWithOptions(source, .{ .filename = "examples/hello.rb" }) catch {
        std.debug.print(
            "Ruby error [{s}]: {s}\n",
            .{ vm.lastErrorClass() orelse "unknown", vm.lastError() orelse "no message" },
        );
        return error.RubyFailed;
    };

    const version = try vm.eval("RUBY_VERSION");
    const version_text = try version.toString(init.gpa);
    defer init.gpa.free(version_text);
    std.debug.print("embedded mruby {s}\n", .{version_text});

    const script_value = try file_result.asInt();
    std.debug.print("script returned Zig.square(7) = {d}\n", .{script_value});

    const main_object = try vm.eval("self");
    const greeting = try main_object.call("greet", &.{try zruby.Value.fromString(&vm, "Zig")});
    const greeting_text = try greeting.toString(init.gpa);
    defer init.gpa.free(greeting_text);
    std.debug.print("{s}\n", .{greeting_text});

    const sum = try main_object.call("ruby_sum", &.{
        try zruby.Value.fromInt(&vm, 20),
        try zruby.Value.fromInt(&vm, 22),
    });
    std.debug.print("ruby_sum(20, 22) = {d}\n", .{try sum.asInt()});
}

fn zigSquare(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = mrb orelse unreachable;
    var n: zruby.c.mrb_int = 0;
    _ = zruby.c.mrb_get_args(state, "i", &n);
    return zruby.c.zruby_int_value(state, n * n);
}
