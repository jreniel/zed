const std = @import("std");

const Context = @import("Context.zig");
const Node = @import("Node.zig");
const Parser = @import("Parser.zig");
const Scope = @import("Scope.zig");

pub const Opcode = enum {
    // Stack operations
    pop,
    // Predefined constant values
    bool_true,
    bool_false,
    nil,
    // Numbers
    float,
    int,
    uint,
    // Strings
    format,
    plain,
    string,
    // Scopes
    scope_in,
    scope_out,
    // Functions
    builtin,
    call,
    func,
    func_return,
    // Variables
    define,
    load,
    set,
    store,
    global,
    gstore,
    // Infix
    add,
    sub,
    mul,
    div,
    mod,
    lt,
    lte,
    gt,
    gte,
    eq,
    neq,
    concat,
    repeat,
    // Prefix
    neg,
    not,
    // Data structures
    list,
    map,
    range,
    subscript,
    // Stack ops
    jump,
    jump_true,
    jump_false,
    // Record Range
    rec_range,
    // Output redirection
    redir,
    // Printing
    sprint,
};

const Index = struct {
    index: u16,
    prev: ?*Index = null,
};

const JumpUpdates = struct {
    prev: ?*JumpUpdates = null,
    updates: std.ArrayList(usize),
};

allocator: std.mem.Allocator,
ctx: Context,
ctx_stack: std.ArrayList(std.ArrayList(u8)),
current_loop_start: ?*Index = null, // Index of instruction at current loop start; if applicable.
bytecode: *std.ArrayList(u8) = undefined,
jump_updates: ?*JumpUpdates = null, // Indexes of jump instruciton operands that need updating.

const Compiler = @This();

pub fn init(allocator: std.mem.Allocator, ctx: Context) !Compiler {
    var self = Compiler{
        .allocator = allocator,
        .ctx = ctx,
        .ctx_stack = std.ArrayList(std.ArrayList(u8)).init(allocator),
    };
    try self.pushContext();
    return self;
}

pub fn compileProgram(self: *Compiler, allocator: std.mem.Allocator, program: Parser.Program) ![5][]const u8 {
    var compiled: [5][]const u8 = undefined;
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var compiler = try init(arena_allocator, self.ctx);
    for (compiled) |_, i| {
        try compiler.pushContext();
        const event = switch (i) {
            0 => program.inits,
            1 => program.files,
            2 => program.recs,
            3 => program.rules,
            4 => program.exits,
            else => unreachable,
        };
        for (event) |n| try compiler.compile(n);
        compiled[i] = try allocator.dupe(u8, compiler.popContext());
    }

    return compiled;
}

pub fn compile(self: *Compiler, node: Node) anyerror!void {
    switch (node.ty) {
        // Stack operations
        .stmt_end => try self.pushInstruction(.pop),
        // Predefined constant values
        .boolean => try self.compileBoolean(node),
        .nil => try self.compileNil(node),
        // Numbers
        .float => try self.compileFloat(node),
        .int => try self.compileInt(node),
        .uint => try self.compileUint(node),
        // Strings
        .string => try self.compileString(node),
        // Functions
        .call => try self.compileCall(node),
        .func => try self.compileFunc(node),
        .func_return => try self.compileReturn(node),
        // Variables
        .define => try self.compileDefine(node),
        .ident => try self.compileLoad(node),
        .assign => try self.compileStore(node),
        .global => try self.compileGlobal(node),
        // Operators
        .infix => try self.compileInfix(node),
        .prefix => try self.compilePrefix(node),
        // Data structures
        .list => try self.compileList(node),
        .map => try self.compileMap(node),
        .range => try self.compileRange(node),
        .subscript => try self.compileSubscript(node),
        // Conditionals
        .conditional => try self.compileConditional(node),
        // Loops
        .loop => try self.compileLoop(node),
        .loop_break => try self.compileBreak(),
        .loop_continue => try self.compileContinue(),
        // Record Range
        .rec_range => try self.compileRecRange(node),
        // Output redirection
        .redir => try self.compileRedir(node),

        else => unreachable,
    }
}

// Compile functions
fn compileBoolean(self: *Compiler, node: Node) !void {
    try self.pushInstruction(if (node.ty.boolean) .bool_true else .bool_false);
    try self.pushOffset(node.offset);
}

fn compileNil(self: *Compiler, node: Node) !void {
    try self.pushInstruction(.nil);
    try self.pushOffset(node.offset);
}

fn compileFloat(self: *Compiler, node: Node) !void {
    var slice = std.mem.asBytes(&node.ty.float);
    try self.pushInstruction(.float);
    try self.pushSlice(slice);
}

fn compileInt(self: *Compiler, node: Node) !void {
    var slice = std.mem.asBytes(&node.ty.int);
    try self.pushInstruction(.int);
    try self.pushSlice(slice);
}

fn compileUint(self: *Compiler, node: Node) !void {
    var slice = std.mem.asBytes(&node.ty.uint);
    try self.pushInstruction(.uint);
    try self.pushSlice(slice);
}

fn compileString(self: *Compiler, node: Node) anyerror!void {
    const len = node.ty.string.len;
    var i: usize = 1;
    while (i <= len) : (i += 1) {
        const segment = node.ty.string[len - i];

        switch (segment) {
            .plain => |plain| {
                try self.pushInstruction(.plain);
                try self.pushSlice(plain);
                try self.pushByte(0);
            },
            .ipol => |ipol| {
                try self.pushInstruction(.scope_in);
                try self.pushEnum(Scope.Type.block);
                for (ipol.nodes) |n| try self.compile(n);
                try self.pushInstruction(.scope_out);
                try self.pushEnum(Scope.Type.block);

                if (ipol.spec) |spec| {
                    try self.pushInstruction(.format);
                    try self.pushOffset(ipol.offset);
                    try self.pushSlice(spec);
                    try self.pushByte(0);
                }
            },
        }
    }

    try self.pushInstruction(.string);
    try self.pushLen(len);
}

fn compileFunc(self: *Compiler, node: Node) anyerror!void {
    // Compile function body to bytecode.
    try self.pushContext();
    for (node.ty.func.body) |n| try self.compile(n);
    const func_bytecode = self.popContext();

    // Serialize function to bytes.
    try self.pushInstruction(.func);

    // Skip bytes for cached functions
    const skip_bytes_index = try self.pushZeroes();
    var skip_bytes: usize = 0;

    // Function unique hash
    var buf = std.ArrayList(u8).init(self.allocator);
    defer buf.deinit();
    _ = try buf.writer().print("{}", .{node.ty.func});
    const func_hash = std.hash.Wyhash.hash(Context.seed, buf.items);
    try self.pushSlice(std.mem.asBytes(&func_hash));

    // Function name
    if (node.ty.func.name.len != 0) try self.pushSlice(node.ty.func.name);
    try self.pushByte(0);
    skip_bytes += node.ty.func.name.len + 1;

    // Function params
    try self.pushLen(node.ty.func.params.len);
    skip_bytes += 2;

    if (node.ty.func.params.len != 0) {
        for (node.ty.func.params) |param| {
            try self.pushSlice(param);
            try self.pushByte(0);
            skip_bytes += param.len + 1;
        }
    }

    // Function bytecode
    try self.pushLen(func_bytecode.len);
    skip_bytes += 2;

    if (func_bytecode.len != 0) try self.pushSlice(func_bytecode);
    skip_bytes += func_bytecode.len;

    const skip_bytes_bytes = std.mem.asBytes(&@intCast(u16, skip_bytes));
    self.bytecode.items[skip_bytes_index] = skip_bytes_bytes[0];
    self.bytecode.items[skip_bytes_index + 1] = skip_bytes_bytes[1];
}

fn compileReturn(self: *Compiler, node: Node) anyerror!void {
    try self.compile(node.ty.func_return.*);
    try self.pushInstruction(.func_return);
}

fn compileCall(self: *Compiler, node: Node) anyerror!void {
    if (node.ty.call.callee.ty == .builtin) return self.compileBuiltin(node);

    var i: usize = 1;
    const num_args = node.ty.call.args.len;
    while (i <= num_args) : (i += 1) try self.compile(node.ty.call.args[num_args - i]);
    try self.compile(node.ty.call.callee.*);
    try self.pushInstruction(.call);
    try self.pushOffset(node.offset);
    try self.pushByte(num_args);
}

fn compileBuiltin(self: *Compiler, node: Node) anyerror!void {
    var i: usize = 1;
    const num_args = node.ty.call.args.len;
    while (i <= num_args) : (i += 1) try self.compile(node.ty.call.args[num_args - i]);
    try self.pushInstruction(.builtin);
    try self.pushEnum(node.ty.call.callee.ty.builtin);
    try self.pushOffset(node.offset);
    try self.pushByte(num_args);
}

fn compileDefine(self: *Compiler, node: Node) anyerror!void {
    try self.compile(node.ty.define.rvalue.*);
    try self.pushInstruction(.define);
    try self.pushOffset(node.offset);
    try self.pushSlice(node.ty.define.lvalue.ty.ident);
    try self.pushByte(0);
}

fn compileLoad(self: *Compiler, node: Node) anyerror!void {
    try self.pushInstruction(.load);
    try self.pushOffset(node.offset);
    try self.pushSlice(node.ty.ident);
    try self.pushByte(0);
}

fn compileStore(self: *Compiler, node: Node) anyerror!void {
    try self.compile(node.ty.assign.rvalue.*);

    if (node.ty.assign.lvalue.ty == .ident) {
        try self.pushInstruction(.store);
        try self.pushOffset(node.offset);
        try self.pushEnum(node.ty.assign.combo);
        try self.pushSlice(node.ty.assign.lvalue.ty.ident);
        try self.pushByte(0);
    } else if (node.ty.assign.lvalue.ty == .global) {
        const global = node.ty.assign.lvalue.ty.global;
        if (global == .at_file or global == .at_frnum or global == .at_rnum) return self.ctx.err(
            "{s} is a read-only global.",
            .{@tagName(global)},
            error.ReadOnlyGlobal,
            node.offset,
        );

        try self.pushInstruction(.gstore);
        try self.pushOffset(node.offset);
        try self.pushEnum(node.ty.assign.lvalue.ty.global);
    } else {
        try self.compile(node.ty.assign.lvalue.ty.subscript.index.*);
        try self.compile(node.ty.assign.lvalue.ty.subscript.container.*);
        try self.pushInstruction(.set);
        try self.pushOffset(node.offset);
        try self.pushEnum(node.ty.assign.combo);
    }
}

fn compileGlobal(self: *Compiler, node: Node) !void {
    try self.pushInstruction(.global);
    try self.pushEnum(node.ty.global);
}

fn compileInfix(self: *Compiler, node: Node) anyerror!void {
    if (node.ty.infix.op == .kw_and) return self.compileLogicAnd(node);
    if (node.ty.infix.op == .kw_or) return self.compileLogicOr(node);

    try self.compile(node.ty.infix.left.*);
    try self.compile(node.ty.infix.right.*);

    switch (node.ty.infix.op) {
        .punct_plus => try self.pushInstruction(.add),
        .punct_minus => try self.pushInstruction(.sub),
        .punct_star => try self.pushInstruction(.mul),
        .punct_slash => try self.pushInstruction(.div),
        .punct_percent => try self.pushInstruction(.mod),
        .punct_lt => try self.pushInstruction(.lt),
        .op_lte => try self.pushInstruction(.lte),
        .punct_gt => try self.pushInstruction(.gt),
        .op_gte => try self.pushInstruction(.gte),
        .op_eq => try self.pushInstruction(.eq),
        .op_neq => try self.pushInstruction(.neq),
        .op_concat => try self.pushInstruction(.concat),
        .op_repeat => try self.pushInstruction(.repeat),
        else => unreachable,
    }

    try self.pushOffset(node.offset);
}

fn compileLogicAnd(self: *Compiler, node: Node) anyerror!void {
    // Left
    try self.compile(node.ty.infix.left.*);
    // Jump if false
    try self.pushInstruction(.jump_false);
    const jump_false_operand_index = try self.pushZeroes();
    // Right
    try self.compile(node.ty.infix.right.*);
    // Update jump_false index.
    self.updateJumpIndex(jump_false_operand_index);
}

fn compileLogicOr(self: *Compiler, node: Node) anyerror!void {
    // Left
    try self.compile(node.ty.infix.left.*);
    // Jump if true
    try self.pushInstruction(.jump_true);
    const jump_true_operand_index = try self.pushZeroes();
    // Right
    try self.compile(node.ty.infix.right.*);
    // Update jump_false index.
    self.updateJumpIndex(jump_true_operand_index);
}

fn compilePrefix(self: *Compiler, node: Node) !void {
    try self.compile(node.ty.prefix.operand.*);

    switch (node.ty.prefix.op) {
        .op_neg => try self.pushInstruction(.neg),
        .punct_bang => try self.pushInstruction(.not),
        else => unreachable,
    }

    try self.pushOffset(node.offset);
}

fn compileList(self: *Compiler, node: Node) anyerror!void {
    const len = node.ty.list.len;
    var i: usize = 1;
    while (i <= len) : (i += 1) try self.compile(node.ty.list[len - i]);
    try self.pushInstruction(.list);
    try self.pushLen(len);
}
fn compileMap(self: *Compiler, node: Node) anyerror!void {
    for (node.ty.map) |entry| {
        try self.compile(entry.key);
        try self.compile(entry.value);
    }
    try self.pushInstruction(.map);
    try self.pushOffset(node.offset);
    try self.pushLen(node.ty.map.len);
}

fn compileSubscript(self: *Compiler, node: Node) anyerror!void {
    try self.compile(node.ty.subscript.index.*);
    try self.compile(node.ty.subscript.container.*);
    try self.pushInstruction(.subscript);
    try self.pushOffset(node.offset);
}

fn compileConditional(self: *Compiler, node: Node) anyerror!void {
    // Condition
    try self.compile(node.ty.conditional.condition.*);
    // Jump if false
    try self.pushInstruction(.jump_false);
    const jump_false_operand_index = try self.pushZeroes();
    // Then branch
    try self.pushInstruction(.scope_in);
    try self.pushEnum(Scope.Type.block);
    for (node.ty.conditional.then_branch) |n| try self.compile(n);
    try self.pushInstruction(.scope_out);
    try self.pushEnum(Scope.Type.block);
    // Unconditional jump
    try self.pushInstruction(.jump);
    const jump_operand_index = try self.pushZeroes();
    self.updateJumpIndex(jump_false_operand_index);
    // Else branch
    try self.pushInstruction(.scope_in);
    try self.pushEnum(Scope.Type.block);
    for (node.ty.conditional.else_branch) |n| try self.compile(n);
    try self.pushInstruction(.scope_out);
    try self.pushEnum(Scope.Type.block);

    self.updateJumpIndex(jump_operand_index);
}

fn compileLoop(self: *Compiler, node: Node) anyerror!void {
    if (node.ty.loop.is_do) return self.compileDoWhile(node);

    // Breaks
    try self.pushJumpUpdates();
    defer self.popJumpUpdates();

    // Iterate / Continues
    try self.pushCurrentLoopIndex();
    defer self.popCurrentLoopIndex();

    // Condition
    try self.compile(node.ty.loop.condition.*);

    // Jump if false
    try self.pushInstruction(.jump_false);
    try self.jump_updates.?.updates.append(try self.pushZeroes());

    // Body
    try self.pushInstruction(.scope_in);
    try self.pushEnum(Scope.Type.loop);
    for (node.ty.loop.body) |n| try self.compile(n);
    try self.pushInstruction(.scope_out);
    try self.pushEnum(Scope.Type.loop);

    // Unconditional jump
    try self.pushInstruction(.jump);
    try self.pushLen(self.current_loop_start.?.index);

    // Update break out jumps.
    while (self.jump_updates.?.updates.popOrNull()) |index| self.updateJumpIndex(index);

    // while loops always return nul.
    try self.pushInstruction(.nil);
    try self.pushOffset(node.offset);
}

fn compileDoWhile(self: *Compiler, node: Node) anyerror!void {
    // Breaks
    try self.pushJumpUpdates();
    defer self.popJumpUpdates();

    // Iterate / Continues
    try self.pushCurrentLoopIndex();
    defer self.popCurrentLoopIndex();

    // Body
    try self.pushInstruction(.scope_in);
    try self.pushEnum(Scope.Type.loop);
    for (node.ty.loop.body) |n| try self.compile(n);
    try self.pushInstruction(.scope_out);
    try self.pushEnum(Scope.Type.loop);

    // Condition
    try self.compile(node.ty.loop.condition.*);

    // Jump true
    try self.pushInstruction(.jump_true);
    try self.pushLen(self.current_loop_start.?.index);

    // while loops always return nul.
    try self.pushInstruction(.nil);
    try self.pushOffset(node.offset);
}

fn compileBreak(self: *Compiler) anyerror!void {
    try self.pushInstruction(.scope_out);
    try self.pushEnum(Scope.Type.loop);
    try self.pushInstruction(.jump);
    try self.jump_updates.?.updates.append(try self.pushZeroes());
}

fn compileContinue(self: *Compiler) anyerror!void {
    try self.pushInstruction(.scope_out);
    try self.pushEnum(Scope.Type.loop);
    try self.pushInstruction(.jump);
    try self.pushLen(self.current_loop_start.?.index);
}

fn compileRange(self: *Compiler, node: Node) anyerror!void {
    try self.compile(node.ty.range.from.*);
    try self.compile(node.ty.range.to.*);
    try self.pushInstruction(.range);
    try self.pushOffset(node.offset);
    try self.pushByte(@boolToInt(node.ty.range.inclusive));
}

fn compileRecRange(self: *Compiler, node: Node) anyerror!void {
    // Action
    var action_bytecode: []const u8 = "";

    if (node.ty.rec_range.action.len > 0) {
        try self.pushContext();
        for (node.ty.rec_range.action) |n| try self.compile(n);
        action_bytecode = self.popContext();
    }

    if (node.ty.rec_range.to) |to| {
        try self.compile(to.*);
    }
    if (node.ty.rec_range.from) |from| {
        try self.compile(from.*);
    }

    try self.pushInstruction(.rec_range);
    try self.pushByte(node.ty.rec_range.id);
    try self.pushByte(@boolToInt(node.ty.rec_range.exclusive));
    try self.pushLen(action_bytecode.len);
    if (action_bytecode.len != 0) try self.pushSlice(action_bytecode);
    try self.pushByte(@boolToInt(node.ty.rec_range.from != null));
    try self.pushByte(@boolToInt(node.ty.rec_range.to != null));
}

fn compileRedir(self: *Compiler, node: Node) anyerror!void {
    if (node.ty.redir.expr.ty == .call and
        node.ty.redir.expr.ty.call.callee.ty == .ident and
        std.mem.eql(u8, node.ty.redir.expr.ty.call.callee.ty.ident, "print"))
    {
        const num_args = node.ty.redir.expr.ty.call.args.len;
        var i: usize = 1;
        while (i <= num_args) : (i += 1) try self.compile(node.ty.redir.expr.ty.call.args[num_args - i]);
        try self.pushInstruction(.sprint);
        try self.pushOffset(node.offset);
        try self.pushByte(num_args);
    } else {
        try self.compile(node.ty.redir.expr.*);
    }

    try self.compile(node.ty.redir.file.*);

    try self.pushInstruction(.redir);
    try self.pushOffset(node.offset);
    try self.pushByte(@boolToInt(node.ty.redir.clobber));
}

// Helpers

fn head(self: Compiler) *std.ArrayList(u8) {
    std.debug.assert(self.ctx_stack.items.len != 0);
    return &self.ctx_stack.items[self.ctx_stack.items.len - 1];
}

fn pushContext(self: *Compiler) !void {
    try self.ctx_stack.append(std.ArrayList(u8).init(self.allocator));
    self.bytecode = self.head();
}

fn popContext(self: *Compiler) []const u8 {
    std.debug.assert(self.ctx_stack.items.len > 1);
    var popped_bytecode = self.ctx_stack.pop();
    self.bytecode = self.head();
    return popped_bytecode.toOwnedSlice();
}

fn pushInstruction(self: *Compiler, opcode: Opcode) !void {
    try self.bytecode.append(@enumToInt(opcode));
}

fn pushOffset(self: *Compiler, offset: u16) !void {
    try self.bytecode.appendSlice(std.mem.sliceAsBytes(&[1]u16{offset}));
}

fn pushLen(self: *Compiler, len: usize) !void {
    try self.bytecode.appendSlice(std.mem.sliceAsBytes(&[1]u16{@intCast(u16, len)}));
}

fn pushSlice(self: *Compiler, slice: []const u8) !void {
    try self.bytecode.appendSlice(slice);
}

fn pushEnum(self: *Compiler, v: anytype) !void {
    try self.bytecode.append(@enumToInt(v));
}

fn pushByte(self: *Compiler, n: anytype) !void {
    try self.bytecode.append(@intCast(u8, n));
}

// Returns index of first byte pushed.
fn pushZeroes(self: *Compiler) !usize {
    try self.bytecode.append(0);
    try self.bytecode.append(0);
    return self.bytecode.items.len - 2;
}

fn updateJumpIndex(self: *Compiler, index: usize) void {
    std.debug.assert(index < self.bytecode.items.len);
    var jump_index_bytes = std.mem.sliceAsBytes(&[_]u16{@intCast(u16, self.bytecode.items.len)});
    self.bytecode.items[index] = jump_index_bytes[0];
    self.bytecode.items[index + 1] = jump_index_bytes[1];
}

fn pushJumpUpdates(self: *Compiler) anyerror!void {
    var jump_updates_ptr = try self.allocator.create(JumpUpdates);
    jump_updates_ptr.* = .{ .prev = self.jump_updates, .updates = std.ArrayList(usize).init(self.allocator) };
    self.jump_updates = jump_updates_ptr;
}

fn popJumpUpdates(self: *Compiler) void {
    std.debug.assert(self.jump_updates != null);
    self.jump_updates = self.jump_updates.?.prev;
}

fn pushCurrentLoopIndex(self: *Compiler) anyerror!void {
    var current_loop_start_ptr = try self.allocator.create(Index);
    current_loop_start_ptr.* = .{ .index = @intCast(u16, self.bytecode.items.len), .prev = self.current_loop_start };
    self.current_loop_start = current_loop_start_ptr;
}

fn popCurrentLoopIndex(self: *Compiler) void {
    std.debug.assert(self.current_loop_start != null);
    self.current_loop_start = self.current_loop_start.?.prev;
}

// Tests

test "Compiler predefined constant values" {
    const Lexer = @import("Lexer.zig");

    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ctx = Context{ .filename = "inline", .src = "true false nil" };

    var lexer = Lexer{
        .allocator = arena.allocator(),
        .ctx = ctx,
    };
    var tokens = try lexer.lex();

    var parser = Parser{
        .allocator = arena.allocator(),
        .ctx = ctx,
        .tokens = tokens,
    };
    const program = try parser.parse();

    var compiler = try init(arena.allocator(), ctx);
    for (program.rules) |n| try compiler.compile(n);

    try std.testing.expectEqual(@as(usize, 12), compiler.bytecode.items.len);
    try std.testing.expectEqual(Opcode.bool_true, @intToEnum(Opcode, compiler.bytecode.items[0]));
    try std.testing.expectEqual(@as(u16, 0), std.mem.bytesAsSlice(u16, compiler.bytecode.items[1..3])[0]);
    try std.testing.expectEqual(Opcode.pop, @intToEnum(Opcode, compiler.bytecode.items[3]));
    try std.testing.expectEqual(Opcode.bool_false, @intToEnum(Opcode, compiler.bytecode.items[4]));
    try std.testing.expectEqual(@as(u16, 5), std.mem.bytesAsSlice(u16, compiler.bytecode.items[5..7])[0]);
    try std.testing.expectEqual(Opcode.pop, @intToEnum(Opcode, compiler.bytecode.items[7]));
    try std.testing.expectEqual(Opcode.nil, @intToEnum(Opcode, compiler.bytecode.items[8]));
    try std.testing.expectEqual(@as(u16, 11), std.mem.bytesAsSlice(u16, compiler.bytecode.items[9..11])[0]);
    try std.testing.expectEqual(Opcode.pop, @intToEnum(Opcode, compiler.bytecode.items[11]));
}
