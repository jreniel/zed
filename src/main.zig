//const std = @import("std");
//
//const Compiler = @import("Compiler.zig");
//const Context = @import("Context.zig");
//const Lexer = @import("Lexer.zig");
//const Node = @import("Node.zig");
//const Parser = @import("Parser.zig");
//const Scope = @import("Scope.zig");
//const ScopeStack = @import("ScopeStack.zig");
//const Value = @import("Value.zig");
//const Vm = @import("Vm.zig");
//
//fn printUsage() !void {
//    std.log.err("Usage: zed <your_program_file.zed> <data_file_1> <data_file_2> ... <data_file_n>\n", .{});
//    return error.InvalidUsage;
//}
//
//pub fn main() anyerror!void {
//    // Allocation
//    //var allocator = std.testing.allocator;
//    const allocator = std.heap.page_allocator;
//
//    var static_arena = std.heap.ArenaAllocator.init(allocator);
//    defer static_arena.deinit();
//    const static_allocator = static_arena.allocator();
//
//    var tmp_arena = std.heap.ArenaAllocator.init(allocator);
//    var need_tmp_deinit = true;
//    defer if (need_tmp_deinit) tmp_arena.deinit();
//
//    // Command line args.
//    var args = try std.process.argsWithAllocator(allocator);
//    _ = args.skip(); // skip program name.
//
//    // Program file.
//    const program_filename = args.next() orelse return printUsage();
//    var program_file = try std.fs.cwd().openFile(program_filename, .{});
//    defer program_file.close();
//
//    // Context
//    var ctx = Context{ .filename = program_filename, .src = undefined };
//
//    // Frontend
//    var compiled: [5][]const u8 = undefined;
//
//    if (std.mem.endsWith(u8, program_filename, ".zbc")) {
//        var i: usize = 0;
//        while (i < 5) : (i += 1) {
//            var bytes_len_buf: [2]u8 = undefined;
//            _ = try program_file.readAll(&bytes_len_buf);
//            const bytes_len = std.mem.bytesAsValue(u16, &bytes_len_buf);
//            var bytes_buf = try static_allocator.alloc(u8, bytes_len.*);
//            _ = try program_file.readAll(bytes_buf);
//            compiled[i] = bytes_buf;
//        }
//    } else {
//        const program_src = try program_file.readToEndAlloc(static_allocator, 1024 * 64); // 64K
//        ctx.src = program_src;
//
//        // Lex
//        var lexer = Lexer{ .allocator = tmp_arena.allocator(), .ctx = ctx };
//        const tokens = try lexer.lex();
//        // Parse
//        var parser = Parser{
//            .allocator = tmp_arena.allocator(),
//            .ctx = ctx,
//            .tokens = tokens,
//        };
//        const program = try parser.parse();
//
//        // Backend / Compile to bytecode
//        var compiler = try Compiler.init(tmp_arena.allocator(), ctx);
//        compiled = try compiler.compileProgram(static_allocator, program);
//        tmp_arena.deinit();
//        need_tmp_deinit = false;
//    }
//
//    // Program scope stack with global scope
//    var scope_stack = ScopeStack.init(static_allocator);
//
//    // Output change check
//    var output = std.ArrayList(u8).init(static_allocator);
//    var prev_output_len: usize = 0;
//
//    // onInit
//    tmp_arena = std.heap.ArenaAllocator.init(allocator);
//    need_tmp_deinit = true;
//    var inits_vm = try Vm.init(
//        tmp_arena.allocator(),
//        compiled[0],
//        &scope_stack,
//        ctx,
//        &output,
//    );
//    try inits_vm.run();
//    tmp_arena.deinit();
//    need_tmp_deinit = false;
//
//    // Loop over input files.
//    while (args.next()) |filename| {
//        // Filename
//        scope_stack.file = filename;
//
//        // onFile
//        tmp_arena = std.heap.ArenaAllocator.init(allocator);
//        need_tmp_deinit = true;
//        var files_vm = try Vm.init(
//            tmp_arena.allocator(),
//            compiled[1],
//            &scope_stack,
//            ctx,
//            &output,
//        );
//        try files_vm.run();
//        tmp_arena.deinit();
//        need_tmp_deinit = false;
//
//        // Data file
//        var data_file: std.fs.File = undefined;
//
//        if (std.mem.eql(u8, filename, "-")) {
//            data_file = std.io.getStdIn();
//        } else {
//            data_file = try std.fs.cwd().openFile(filename, .{});
//        }
//        defer data_file.close();
//        var data_reader = std.io.bufferedReader(data_file.reader()).reader();
//
//        // File record numbering
//        scope_stack.frnum = 1;
//
//        // Loop over records.
//        while (try data_reader.readUntilDelimiterOrEof(&scope_stack.rec_buf, scope_stack.irs[0])) |record| : ({
//            scope_stack.rnum += 1;
//            scope_stack.frnum += 1;
//        }) {
//            // onRec
//            tmp_arena = std.heap.ArenaAllocator.init(allocator);
//            need_tmp_deinit = true;
//            const tmp_allocator = tmp_arena.allocator();
//
//            scope_stack.record = try tmp_allocator.dupeZ(u8, record);
//
//            var recs_vm = try Vm.init(
//                tmp_allocator,
//                compiled[2],
//                &scope_stack,
//                ctx,
//                &output,
//            );
//            try recs_vm.run();
//
//            // New record, new fileds.
//            scope_stack.columns = std.ArrayList(Value).init(tmp_allocator);
//
//            // Loop over fields
//            const str_rec = std.mem.sliceTo(scope_stack.record, 0);
//            const str_ifs = std.mem.sliceTo(scope_stack.ifs, 0);
//            var field_iter = std.mem.split(u8, str_rec, str_ifs);
//
//            while (field_iter.next()) |field| {
//                try scope_stack.columns.append(try Value.newString(tmp_allocator, field));
//            }
//
//            // For each record, exec the rules.
//            var rules_vm = try Vm.init(
//                tmp_allocator,
//                compiled[3],
//                &scope_stack,
//                ctx,
//                &output,
//            );
//            try rules_vm.run();
//            tmp_arena.deinit();
//            need_tmp_deinit = false;
//
//            // Output
//            if (output.items.len != 0 and output.items.len != prev_output_len) {
//                try output.appendSlice(std.mem.sliceTo(scope_stack.ors, 0));
//            }
//
//            // To know if we have new output.
//            prev_output_len = output.items.len;
//        }
//    }
//
//    // onExit
//    tmp_arena = std.heap.ArenaAllocator.init(allocator);
//    need_tmp_deinit = true;
//    var exits_vm = try Vm.init(
//        tmp_arena.allocator(),
//        compiled[4],
//        &scope_stack,
//        ctx,
//        &output,
//    );
//    try exits_vm.run();
//    tmp_arena.deinit();
//    need_tmp_deinit = false;
//
//    // Print hte output.
//    _ = try std.io.getStdOut().writer().print("{s}", .{output.items});
//
//    //std.debug.print("\n***{} * {} = {}***\n", .{ Value.S.i, @sizeOf(Value), Value.S.i * @sizeOf(Value) });
//}

test {
    _ = @import("Lexer.zig");
    _ = @import("Parser.zig");
    _ = @import("Compiler.zig");
    //_ = @import("Value.zig");
    _ = @import("Vm.zig");
}
