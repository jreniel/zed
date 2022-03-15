const std = @import("std");

pub const Tag = enum {
    float,
    ident,
    int,
    string,
    uint,

    kw_and,
    kw_break,
    kw_continue,
    kw_do,
    kw_else,
    kw_if,
    kw_or,
    kw_return,
    kw_select,
    kw_while,

    pd_false,
    pd_nil,
    pd_true,

    pd_atan2,
    pd_chars,
    pd_contains,
    pd_cos,
    pd_each,
    pd_endsWith,
    pd_exp,
    pd_filter,
    pd_int,
    pd_indexOf,
    pd_join,
    pd_keys,
    pd_keysByValueAsc,
    pd_keysByValueDesc,
    pd_lastIndexOf,
    pd_len,
    pd_log,
    pd_map,
    pd_max,
    pd_mean,
    pd_median,
    pd_min,
    pd_mode,
    pd_print,
    pd_pop,
    pd_push,
    pd_rand,
    pd_reduce,
    pd_reverse,
    pd_sin,
    pd_sortAsc,
    pd_sortDesc,
    pd_split,
    pd_sqrt,
    pd_startsWith,
    pd_stdev,
    pd_toLower,
    pd_toUpper,
    pd_values,

    pd_onInit,
    pd_onFile,
    pd_onRec,
    pd_onExit,

    at_cols,
    at_file,
    at_frnum,
    at_ics,
    at_irs,
    at_ocs,
    at_ors,
    at_rec,
    at_rnum,

    op_add_eq,
    op_concat,
    op_define,
    op_div_eq,
    op_elvis,
    op_elvis_eq,
    op_eq,
    op_gte,
    op_lte,
    op_mod_eq,
    op_mul_eq,
    op_neg,
    op_neq,
    op_nomatch,
    op_range_ex,
    op_range_in,
    op_repeat,
    op_sub_eq,
    op_redir_append,
    op_redir_clobber,
    op_xmatch,

    punct_at,
    punct_bang,
    punct_colon,
    punct_comma,
    punct_dollar,
    punct_dot,
    punct_equals,
    punct_fat_rarrow,
    punct_gt,
    punct_lbrace,
    punct_lbracket,
    punct_lparen,
    punct_lt,
    punct_minus,
    punct_newline,
    punct_percent,
    punct_pipe,
    punct_plus,
    punct_question,
    punct_rbrace,
    punct_rbracket,
    punct_rparen,
    punct_semicolon,
    punct_slash,
    punct_star,
    punct_tilde,
};

pub const predef = std.ComptimeStringMap(Tag, .{
    .{ "and", .kw_and },
    .{ "break", .kw_break },
    .{ "continue", .kw_continue },
    .{ "do", .kw_do },
    .{ "else", .kw_else },
    .{ "if", .kw_if },
    .{ "or", .kw_or },
    .{ "false", .pd_false },
    .{ "nil", .pd_nil },
    .{ "return", .kw_return },
    .{ "select", .kw_select },
    .{ "true", .pd_true },
    .{ "while", .kw_while },

    .{ "atan2", .pd_atan2 },
    .{ "chars", .pd_chars },
    .{ "contains", .pd_contains },
    .{ "cos", .pd_cos },
    .{ "each", .pd_each },
    .{ "endsWith", .pd_endsWith },
    .{ "exp", .pd_exp },
    .{ "filter", .pd_filter },
    .{ "int", .pd_int },
    .{ "indexOf", .pd_indexOf },
    .{ "join", .pd_join },
    .{ "keys", .pd_keys },
    .{ "keysByValueAsc", .pd_keysByValueAsc },
    .{ "keysByValueDesc", .pd_keysByValueDesc },
    .{ "lastIndexOf", .pd_lastIndexOf },
    .{ "len", .pd_len },
    .{ "log", .pd_log },
    .{ "map", .pd_map },
    .{ "max", .pd_max },
    .{ "mean", .pd_mean },
    .{ "median", .pd_median },
    .{ "min", .pd_min },
    .{ "mode", .pd_mode },
    .{ "print", .pd_print },
    .{ "pop", .pd_pop },
    .{ "push", .pd_push },
    .{ "rand", .pd_rand },
    .{ "reduce", .pd_reduce },
    .{ "reverse", .pd_reverse },
    .{ "sin", .pd_sin },
    .{ "sortAsc", .pd_sortAsc },
    .{ "sortDesc", .pd_sortDesc },
    .{ "split", .pd_split },
    .{ "sqrt", .pd_sqrt },
    .{ "startsWith", .pd_startsWith },
    .{ "stdev", .pd_stdev },
    .{ "toLower", .pd_toLower },
    .{ "toUpper", .pd_toUpper },
    .{ "values", .pd_values },

    .{ "onInit", .pd_onInit },
    .{ "onFile", .pd_onFile },
    .{ "onRec", .pd_onRec },
    .{ "onExit", .pd_onExit },

    .{ "@cols", .at_cols },
    .{ "@file", .at_file },
    .{ "@frnum", .at_frnum },
    .{ "@ics", .at_ics },
    .{ "@irs", .at_irs },
    .{ "@ocs", .at_ocs },
    .{ "@ors", .at_ors },
    .{ "@rec", .at_rec },
    .{ "@rnum", .at_rnum },
});

len: u16,
offset: u16,
tag: Tag,

const Token = @This();

pub fn new(tag: Tag, offset: u16, len: usize) Token {
    return Token{
        .len = @intCast(u16, len),
        .offset = offset,
        .tag = tag,
    };
}

pub fn is(self: Token, tag: Tag) bool {
    return self.tag == tag;
}
