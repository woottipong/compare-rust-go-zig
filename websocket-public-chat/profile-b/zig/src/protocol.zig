const std = @import("std");

pub const msg_join = "join";
pub const msg_chat = "chat";
pub const msg_ping = "ping";
pub const msg_pong = "pong";
pub const msg_leave = "leave";

pub const chat_payload_size: usize = 128;
pub const room = "public";
pub const rate_limit_msg_per_sec: usize = 10;
pub const ping_interval_sec: u64 = 30;

pub const Message = struct {
    type: []const u8,
    room: ?[]const u8 = null,
    user: ?[]const u8 = null,
    text: ?[]const u8 = null,
    ts: ?i64 = null,
};

test "test_parse_json_message" {
    const allocator = std.testing.allocator;
    const payload =
        \\{"type":"chat","room":"public","user":"client-01","text":"hello","ts":1700000000}
    ;

    var parsed = try std.json.parseFromSlice(Message, allocator, payload, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings(msg_chat, parsed.value.type);
    try std.testing.expect(parsed.value.user != null);
    try std.testing.expectEqualStrings("client-01", parsed.value.user.?);
}
