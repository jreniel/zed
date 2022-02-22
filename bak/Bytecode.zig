pub const Opcode = enum(u8) {
    add,
    call,
    constant,
    define,
    div,
    eq,
    format,
    func_return,
    gt,
    gte,
    jump,
    jump_false,
    jump_true,
    list,
    load,
    logic_not,
    lt,
    lte,
    map,
    mod,
    mul,
    negative,
    neq,
    pop,
    range,
    rec_range,
    scope_in,
    scope_out,
    set,
    store,
    string,
    sub,
    subscript,

    pub const Def = struct {
        opcode: Opcode,
        bytes: u2,
    };

    pub fn fromInt(int: u8) ?Def {
        return switch (int) {
            0 => .{ .opcode = .add, .bytes = 1 },
            1 => .{ .opcode = .call, .bytes = 2 },
            2 => .{ .opcode = .constant, .bytes = 3 },
            3 => .{ .opcode = .define, .bytes = 1 },
            4 => .{ .opcode = .div, .bytes = 1 },
            5 => .{ .opcode = .eq, .bytes = 1 },
            6 => .{ .opcode = .format, .bytes = 1 },
            7 => .{ .opcode = .func_return, .bytes = 1 },
            8 => .{ .opcode = .gt, .bytes = 1 },
            9 => .{ .opcode = .gte, .bytes = 1 },
            10 => .{ .opcode = .jump, .bytes = 3 },
            11 => .{ .opcode = .jump_false, .bytes = 3 },
            12 => .{ .opcode = .jump_true, .bytes = 3 },
            13 => .{ .opcode = .list, .bytes = 3 },
            14 => .{ .opcode = .load, .bytes = 1 },
            15 => .{ .opcode = .logic_not, .bytes = 1 },
            16 => .{ .opcode = .lt, .bytes = 1 },
            17 => .{ .opcode = .lte, .bytes = 1 },
            18 => .{ .opcode = .map, .bytes = 1 },
            19 => .{ .opcode = .mod, .bytes = 1 },
            20 => .{ .opcode = .mul, .bytes = 1 },
            21 => .{ .opcode = .negative, .bytes = 1 },
            22 => .{ .opcode = .neq, .bytes = 1 },
            23 => .{ .opcode = .pop, .bytes = 1 },
            24 => .{ .opcode = .range, .bytes = 2 },
            25 => .{ .opcode = .rec_range, .bytes = 3 },
            26 => .{ .opcode = .scope_in, .bytes = 2 },
            27 => .{ .opcode = .scope_out, .bytes = 2 },
            28 => .{ .opcode = .set, .bytes = 2 },
            29 => .{ .opcode = .store, .bytes = 2 },
            30 => .{ .opcode = .string, .bytes = 3 },
            31 => .{ .opcode = .sub, .bytes = 1 },
            32 => .{ .opcode = .subscript, .bytes = 1 },
            else => null,
        };
    }
};

const Bytecode = @This();