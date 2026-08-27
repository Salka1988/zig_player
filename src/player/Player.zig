const std = @import("std");

const FfmpegAudioDecoder = @import("../codec/audio/FfmpegAudioDecoder.zig");
const FfmpegDemuxer = @import("../demux/FfmpegDemuxer.zig");
const FfmpegVideoDecoder = @import("../codec/video/FfmpegVideoDecoder.zig");
const MediaProbe = @import("MediaProbe.zig");
const Packet = @import("../ffmpeg/Packet.zig");
const PacketQueue = @import("../pipeline/PacketQueue.zig");
const SdlAudioOutput = @import("../audio/sdl/SdlAudioOutput.zig");
const SdlVideoOutput = @import("../video/sdl/SdlVideoOutput.zig");
const State = @import("State.zig").State;
const VideoProbe = @import("VideoProbe.zig");
const sdl = @import("../sdl/bindings.zig");

const no_audio_start = std.math.maxInt(u64);
const max_audio_queue_seconds = 0.5;
// ponytail: fixed late-frame threshold; tune from profiling if real files show jitter.
const drop_late_video_after_seconds = 0.100;
const packet_queue_capacity = 128;

pub const VideoDecodeStats = struct {
    frame_count: usize = 0,
    dropped_frame_count: usize = 0,
    last_time_seconds: ?f64 = null,
    max_late_seconds: f64 = 0,
    max_early_seconds: f64 = 0,
    audio_max_queued_seconds: f64 = 0,
};

const VideoPlaybackClock = struct {
    start_ms: ?u64 = null,
    first_frame_seconds: ?f64 = null,
};

const AudioClock = struct {
    start_ms: u64 = no_audio_start,
    first_ms: i64 = 0,
    done: u8 = 0,

    fn start(self: *AudioClock, timestamp_seconds: f64) void {
        @atomicStore(i64, &self.first_ms, @intFromFloat(timestamp_seconds * std.time.ms_per_s), .release);
        @atomicStore(u64, &self.start_ms, sdl.SDL_GetTicks64(), .release);
    }

    fn seconds(self: *AudioClock) ?f64 {
        const start_ms = @atomicLoad(u64, &self.start_ms, .acquire);
        if (start_ms == no_audio_start) return null;

        const first_ms = @atomicLoad(i64, &self.first_ms, .acquire);
        const elapsed_ms = sdl.SDL_GetTicks64() - start_ms;
        return (@as(f64, @floatFromInt(first_ms)) + @as(f64, @floatFromInt(elapsed_ms))) / std.time.ms_per_s;
    }

    fn markDone(self: *AudioClock) void {
        @atomicStore(u8, &self.done, 1, .release);
    }
};

const PlaybackControl = struct {
    stop: u8 = 0,

    fn requestStop(self: *PlaybackControl) void {
        @atomicStore(u8, &self.stop, 1, .release);
    }

    fn shouldStop(self: *PlaybackControl) bool {
        return @atomicLoad(u8, &self.stop, .acquire) != 0;
    }
};

const AudioThreadContext = struct {
    allocator: std.mem.Allocator,
    queue: *PacketQueue,
    decoder: *FfmpegAudioDecoder,
    clock: *AudioClock,
    control: *PlaybackControl,
    err: ?anyerror = null,
    max_queued_seconds: f64 = 0,
};

const DemuxThreadContext = struct {
    demuxer: *FfmpegDemuxer,
    video_queue: *PacketQueue,
    audio_queue: ?*PacketQueue,
    video_stream_index: u32,
    audio_stream_index: ?u32,
    control: *PlaybackControl,
    err: ?anyerror = null,
};

allocator: std.mem.Allocator,
state: State = .idle,
path: ?[]const u8 = null,

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *@This()) void {
    self.clearPath();
}

pub fn open(self: *@This(), path: []const u8) !void {
    self.clearPath();
    self.path = try self.allocator.dupe(u8, path);
    self.state = .opening;
}

pub fn stop(self: *@This()) void {
    self.clearPath();
    self.state = .idle;
}

pub fn probeLoaded(
    self: *@This(),
    video_frames: []VideoProbe.FrameSummary,
) !MediaProbe.Result {
    return MediaProbe.run(self.allocator, self.path orelse return error.NoMediaLoaded, video_frames);
}

pub fn playLoadedVideoWindow(self: *@This()) !VideoDecodeStats {
    const path = self.path orelse return error.NoMediaLoaded;

    var demuxer = try FfmpegDemuxer.open(self.allocator, path);
    defer demuxer.deinit();

    const video_stream = (try demuxer.firstSupportedVideoStream()) orelse return .{};
    const audio_stream = try demuxer.firstSupportedAudioStream();
    const has_audio = audio_stream != null;

    var video_decoder = try FfmpegVideoDecoder.openFromDemuxer(&demuxer, video_stream);
    defer video_decoder.deinit();

    var audio_decoder: ?FfmpegAudioDecoder = if (audio_stream) |stream|
        try FfmpegAudioDecoder.openFromDemuxer(&demuxer, stream)
    else
        null;
    defer if (audio_decoder) |*decoder| decoder.deinit();

    var video_queue = try PacketQueue.init(self.allocator, packet_queue_capacity);
    defer video_queue.deinit(self.allocator);

    var audio_queue: ?PacketQueue = if (has_audio)
        try PacketQueue.init(self.allocator, packet_queue_capacity)
    else
        null;
    defer if (audio_queue) |*queue| queue.deinit(self.allocator);

    var audio_clock: AudioClock = .{};
    var control: PlaybackControl = .{};
    var audio_context: ?AudioThreadContext = if (has_audio) .{
        .allocator = self.allocator,
        .queue = &audio_queue.?,
        .decoder = &audio_decoder.?,
        .clock = &audio_clock,
        .control = &control,
    } else null;
    const audio_thread: ?std.Thread = if (audio_context) |*context|
        try std.Thread.spawn(.{}, audioThreadMain, .{context})
    else
        null;
    errdefer {
        control.requestStop();
        video_queue.close();
        if (audio_queue) |*queue| queue.close();
        if (audio_thread) |thread| thread.join();
    }

    var demux_context: DemuxThreadContext = .{
        .demuxer = &demuxer,
        .video_queue = &video_queue,
        .audio_queue = if (audio_queue) |*queue| queue else null,
        .video_stream_index = video_stream.index,
        .audio_stream_index = if (audio_stream) |stream| stream.index else null,
        .control = &control,
    };
    const demux_thread = try std.Thread.spawn(.{}, demuxThreadMain, .{&demux_context});
    errdefer {
        control.requestStop();
        video_queue.close();
        if (audio_queue) |*queue| queue.close();
        demux_thread.join();
    }

    var video_output: ?SdlVideoOutput = null;
    defer if (video_output) |*output| output.deinit();

    var video_clock: VideoPlaybackClock = .{};
    var stats: VideoDecodeStats = .{};
    var keep_playing = true;
    while (keep_playing) {
        var packet = video_queue.pop() orelse break;
        defer packet.deinit();

        try video_decoder.sendPacket(&packet);
        keep_playing = try receiveAndPresentVideo(
            &video_decoder,
            &video_output,
            if (has_audio) &audio_clock else null,
            &video_clock,
            &stats,
        );
    }

    if (keep_playing) {
        try video_decoder.sendEndOfStream();
        _ = try receiveAndPresentVideo(
            &video_decoder,
            &video_output,
            if (has_audio) &audio_clock else null,
            &video_clock,
            &stats,
        );
    } else {
        control.requestStop();
        video_queue.close();
        if (audio_queue) |*queue| queue.close();
    }

    demux_thread.join();
    if (audio_thread) |thread| thread.join();
    if (audio_context) |context| {
        stats.audio_max_queued_seconds = context.max_queued_seconds;
    }
    if (demux_context.err) |err| return err;
    if (audio_context) |context| if (context.err) |err| return err;

    return stats;
}

fn clearPath(self: *@This()) void {
    if (self.path) |path| {
        self.allocator.free(path);
        self.path = null;
    }
}

fn audioThreadMain(context: *AudioThreadContext) void {
    runAudioThread(context) catch |err| {
        context.err = err;
    };
    context.clock.markDone();
}

fn demuxThreadMain(context: *DemuxThreadContext) void {
    runDemuxThread(context) catch |err| {
        context.err = err;
    };
    context.video_queue.close();
    if (context.audio_queue) |queue| queue.close();
}

fn runDemuxThread(context: *DemuxThreadContext) !void {
    while (!context.control.shouldStop()) {
        const stream_index = (try context.demuxer.readPacket()) orelse return;
        if (stream_index == context.video_stream_index) {
            try pushPacket(context.video_queue, context.demuxer.packet);
        } else if (context.audio_stream_index != null and stream_index == context.audio_stream_index.?) {
            if (context.audio_queue) |queue| {
                try pushPacket(queue, context.demuxer.packet);
            }
        }
    }
}

fn pushPacket(queue: *PacketQueue, packet: *const @import("../ffmpeg/bindings.zig").c.AVPacket) !void {
    queue.push(try Packet.clone(packet)) catch |err| switch (err) {
        error.QueueClosed => return,
    };
}

fn runAudioThread(context: *AudioThreadContext) !void {
    var output: ?SdlAudioOutput = null;
    defer if (output) |*audio_output| audio_output.deinit();

    while (!context.control.shouldStop()) {
        var packet = context.queue.pop() orelse break;
        defer packet.deinit();

        try context.decoder.sendPacket(&packet);
        try receiveAndQueueAudio(&output, context);
    }

    if (!context.control.shouldStop()) {
        try context.decoder.sendEndOfStream();
        try receiveAndQueueAudio(&output, context);
        if (output) |*audio_output| audio_output.drain();
    }
}

fn receiveAndPresentVideo(
    decoder: *FfmpegVideoDecoder,
    output: *?SdlVideoOutput,
    audio_clock: ?*AudioClock,
    video_clock: *VideoPlaybackClock,
    stats: *VideoDecodeStats,
) !bool {
    while (try decoder.receive()) |frame| {
        stats.last_time_seconds = if (frame.pts) |pts| pts.seconds else null;
        if (observeVideoSync(stats, audio_clock, stats.last_time_seconds)) {
            stats.dropped_frame_count += 1;
            continue;
        }

        if (output.* == null) {
            output.* = try SdlVideoOutput.init(frame.width, frame.height);
        }

        waitForVideoTime(video_clock, audio_clock, stats.last_time_seconds);
        if (!try output.*.?.present(try decoder.currentYuv420p())) return false;
        stats.frame_count += 1;
    }
    return true;
}

fn observeVideoSync(stats: *VideoDecodeStats, audio_clock: ?*AudioClock, frame_seconds: ?f64) bool {
    const video_seconds = frame_seconds orelse return false;
    const clock = audio_clock orelse return false;
    const audio_seconds = clock.seconds() orelse return false;
    const delta = audio_seconds - video_seconds;

    if (delta > 0) {
        stats.max_late_seconds = @max(stats.max_late_seconds, delta);
    } else {
        stats.max_early_seconds = @max(stats.max_early_seconds, -delta);
    }

    return delta > drop_late_video_after_seconds;
}

fn receiveAndQueueAudio(
    output: *?SdlAudioOutput,
    context: *AudioThreadContext,
) !void {
    while (try context.decoder.receive()) |_| {
        const frame = try context.decoder.currentF32Planar();
        if (output.* == null) {
            output.* = try SdlAudioOutput.init(frame.sample_rate, frame.channel_count);
        }

        try output.*.?.queueF32Planar(context.allocator, frame);
        context.max_queued_seconds = @max(context.max_queued_seconds, output.*.?.queuedSeconds());
        if (context.clock.seconds() == null) {
            context.clock.start(if (frame.pts) |pts| pts.seconds else 0);
            output.*.?.start();
        }

        while (output.*.?.queuedSeconds() > max_audio_queue_seconds and !context.control.shouldStop()) {
            sdl.SDL_Delay(5);
        }
    }
}

fn waitForVideoTime(
    video_clock: *VideoPlaybackClock,
    audio_clock: ?*AudioClock,
    frame_seconds: ?f64,
) void {
    const seconds = frame_seconds orelse return;

    if (audio_clock) |clock| {
        if (clock.seconds() != null) {
            while (clock.seconds()) |audio_seconds| {
                if (audio_seconds >= seconds) return;
                sdl.SDL_Delay(1);
            }
        }
    }

    if (video_clock.first_frame_seconds == null) {
        video_clock.first_frame_seconds = seconds;
        video_clock.start_ms = sdl.SDL_GetTicks64();
        return;
    }

    const elapsed_seconds = seconds - video_clock.first_frame_seconds.?;
    if (elapsed_seconds <= 0) return;

    const target_ms = video_clock.start_ms.? + @as(u64, @intFromFloat(elapsed_seconds * std.time.ms_per_s));
    const now_ms = sdl.SDL_GetTicks64();
    if (target_ms > now_ms) {
        sdl.SDL_Delay(@intCast(target_ms - now_ms));
    }
}

test "load owns path and stop clears it" {
    var player = init(std.testing.allocator);
    defer player.deinit();

    try player.open("first.mp4");
    try std.testing.expectEqual(State.opening, player.state);
    try std.testing.expectEqualStrings("first.mp4", player.path.?);

    try player.open("second.mp4");
    try std.testing.expectEqual(State.opening, player.state);
    try std.testing.expectEqualStrings("second.mp4", player.path.?);

    player.stop();
    try std.testing.expectEqual(State.idle, player.state);
    try std.testing.expectEqual(@as(?[]const u8, null), player.path);
}
