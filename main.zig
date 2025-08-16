const std = @import("std");
const pa = @import("pulseaudio.zig");

fn parseNum(str: []const u8) !u64 {
    return if (str.len == 0) 0 else std.fmt.parseUnsigned(u64, str, 10);
}

pub fn main() !void {
    const max_time_s = blk: {
        var arg_it = std.process.args();
        const prog_name = arg_it.next().?;
        errdefer usage(prog_name);
        const time_str = arg_it.next() orelse return usage(prog_name);
        var time_str_it = std.mem.splitBackwardsScalar(u8, time_str, ':');
        var time = try parseNum(time_str_it.first());
        time += 60 * (try parseNum(time_str_it.next() orelse break :blk time));
        time += 3600 * (try parseNum(time_str_it.next() orelse break :blk time));
        if (time_str_it.next() != null) return error.MaxTwoColons;
        break :blk time;
    };

    const stdout = std.io.getStdOut();
    const w = stdout.writer();
    var timer = try std.time.Timer.start();
    var current_time_ns: u64 = 0;
    if (stdout.isTty()) {
        try printTime(max_time_s * std.time.ns_per_s);
        try w.writeByte('\n');
        while (current_time_ns < std.time.ns_per_s * max_time_s) : (current_time_ns = timer.read()) {
            try w.writeAll("\x1b[J");
            try printTime(current_time_ns);
            try w.writeAll("\n\x1b[F");
            std.time.sleep(std.time.ns_per_s);
        }
        try w.writeAll("\x1b[J\x1b[5m");
        try printTime(current_time_ns);
        try w.writeAll("\n\x1b[0m");

        _ = try std.Thread.spawn(.{}, startAlarm, .{});
        //make noise until cancelled
        const r = std.io.getStdOut().reader();
        const old_termios = try initTerm();
        _ = try r.readByte();
        try w.writeAll("\x1b[F\x1b[J");
        try std.posix.tcsetattr(0, .FLUSH, old_termios);
    } else {
        while (current_time_ns < std.time.ns_per_s * max_time_s) : (current_time_ns = timer.read()) {
            try printTime(current_time_ns);
            try w.writeAll(" / ");
            try printTime(max_time_s * std.time.ns_per_s);
            try w.writeByte('\n');
            std.time.sleep(std.time.ns_per_s);
        }
        try w.writeAll("YER DONE!!!\n");
        try startAlarm();
    }
}

fn printTime(time_in_ns: u64) !void {
    const w = std.io.getStdOut().writer();
    var time_ns = time_in_ns;
    const h = time_ns / std.time.ns_per_hour;
    time_ns %= std.time.ns_per_hour;
    const m = time_ns / std.time.ns_per_min;
    time_ns %= std.time.ns_per_min;
    const s = time_ns / std.time.ns_per_s;
    try w.print("{:0>2}:{:0>2}:{:0>2}", .{ h, m, s });
}

fn usage(prog_name: []const u8) void {
    std.log.info(
        \\usage:
        \\  {s} [h:][m:][s]
        \\  h m and s defaults to 0
    , .{prog_name});
}

fn startAlarm() !void {
    const specs: pa.SampleSpec = .{
        .format = .float32le,
        .rate = 44100,
        .channels = 2,
    };
    if (pa.simple_new(
        null,
        "Timer",
        .playback,
        null,
        "Music",
        &specs,
        null,
        null,
        null,
    )) |stream| {
        const buf = try std.heap.page_allocator.alloc(f32, 44100 * 2);
        var acc: f64 = 0;
        const freqs = [_]f64{ 440, 340, 440, 440, 603 };
        var i: usize = 0;
        while (true) : (i = (i + 1) % 5) {
            fillSine(&acc, buf, freqs[i]);
            addNoise(buf, 0.04);
            addFades(buf, 2000, 2000);
            for (buf) |*b| b.* *= 0.6;
            std.time.sleep(100 * std.time.ns_per_ms);
            _ = pa.simple_write(stream, buf.ptr, @sizeOf(f32) * buf.len, null);
            _ = pa.simple_drain(stream, null);
        }
    } else std.log.err("could not connect to pulse audio daemon", .{});
}

fn addNoise(buf: []f32, mix: f32) void {
    var r = std.Random.DefaultPrng.init(834);
    var rnd = r.random();
    for (buf) |*b| {
        b.* += rnd.float(f32) * mix;
    }
}
fn addFades(buf: []f32, start: usize, end: usize) void {
    std.debug.assert(start < buf.len / 2 and start > 0);
    std.debug.assert(end < buf.len / 2 and end > 0);
    const fs: f32 = @floatFromInt(start);
    const es: f32 = @floatFromInt(end);
    for (0..start) |i| {
        const fi: f32 = @floatFromInt(i);
        buf[i * 2] *= fi / fs;
        buf[i * 2 + 1] *= fi / fs;
    }
    for (0..end) |i| {
        const fi: f32 = @floatFromInt(i);
        buf[(buf.len - 1) - i * 2 - 1] *= fi / es;
        buf[(buf.len - 1) - i * 2] *= fi / es;
    }
}

fn fillSine(acc: *f64, buf: []f32, freq: f64) void {
    const pi2 = std.math.pi * 2;
    for (0..buf.len / 2) |i| {
        acc.* += pi2 * freq / 44100.0;
        if (acc.* >= pi2) acc.* -= pi2;
        const val: f32 = @floatCast(@sin(acc.*));
        buf[i * 2] = val;
        buf[i * 2 + 1] = val;
    }
}

fn initTerm() !std.posix.termios {
    const fd = 0;
    const original_termios = try std.posix.tcgetattr(fd);
    var termios = original_termios;
    termios.lflag.ECHO = false;
    termios.lflag.ICANON = false;
    termios.lflag.ISIG = false;
    termios.cc[@intFromEnum(std.os.linux.V.TIME)] = 0;
    termios.cc[@intFromEnum(std.os.linux.V.MIN)] = 1;
    try std.posix.tcsetattr(fd, .FLUSH, termios);
    return original_termios;
}
