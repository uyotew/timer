pub const SampleSpec = extern struct {
    format: Sample,
    rate: u32,
    channels: u8,
};

pub const Sample = enum(c_int) {
    float32le = 5,
};

pub const Simple = opaque {};

pub const StreamDirection = enum(c_uint) {
    playback = 1,
};

pub const ChannelMap = extern struct {
    channels: u8 = 0,
    map: [32]c_int = .{0} ** 32,
};

pub const BufferAttr = extern struct {
    maxlength: u32 = 0,
    tlength: u32 = 0,
    prebuf: u32 = 0,
    minreq: u32 = 0,
    fragsize: u32 = 0,
};

extern fn pa_simple_new(
    server: [*c]const u8,
    name: [*c]const u8,
    dir: StreamDirection,
    dev: [*c]const u8,
    stream_name: [*c]const u8,
    ss: [*c]const SampleSpec,
    map: [*c]const ChannelMap,
    attr: [*c]const BufferAttr,
    @"error": [*c]c_int,
) ?*Simple;
pub const simple_new = pa_simple_new;

extern fn pa_simple_write(s: ?*Simple, data: ?*const anyopaque, bytes: usize, @"error": [*c]c_int) c_int;
pub const simple_write = pa_simple_write;

pub extern fn pa_simple_drain(s: ?*Simple, @"error": [*c]c_int) c_int;
pub const simple_drain = pa_simple_drain;
