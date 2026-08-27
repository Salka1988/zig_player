const std = @import("std");

const F32PlanarAudioFrame = @import("../../domain/F32PlanarAudioFrame.zig");
const sdl = @import("../../sdl/bindings.zig");

device: sdl.SDL_AudioDeviceID,
sample_rate: u32,
channel_count: u32,
queued_byte_count: u64 = 0,
first_frame_seconds: ?f64 = null,

pub fn init(sample_rate: u32, channel_count: u32) !@This() {
    if (channel_count == 0 or channel_count > 2) return error.UnsupportedAudioChannelCount;
    if (sdl.SDL_InitSubSystem(sdl.SDL_INIT_AUDIO) < 0) return error.Sdl;
    errdefer sdl.SDL_QuitSubSystem(sdl.SDL_INIT_AUDIO);

    const desired: sdl.SDL_AudioSpec = .{
        .freq = @intCast(sample_rate),
        .format = sdl.AUDIO_F32SYS,
        .channels = @intCast(channel_count),
        .silence = 0,
        .samples = 4096,
        .padding = 0,
        .size = 0,
        .callback = null,
        .userdata = null,
    };

    const device = sdl.SDL_OpenAudioDevice(null, 0, &desired, null, 0);
    if (device == 0) return error.Sdl;
    errdefer sdl.SDL_CloseAudioDevice(device);

    sdl.SDL_PauseAudioDevice(device, 0);

    return .{
        .device = device,
        .sample_rate = sample_rate,
        .channel_count = channel_count,
    };
}

pub fn deinit(self: *@This()) void {
    sdl.SDL_CloseAudioDevice(self.device);
    sdl.SDL_QuitSubSystem(sdl.SDL_INIT_AUDIO);
}

pub fn queueF32Planar(
    self: *@This(),
    allocator: std.mem.Allocator,
    frame: F32PlanarAudioFrame,
) !void {
    if (frame.channel_count != self.channel_count) return error.UnsupportedAudioChannelCount;
    if (self.queued_byte_count == 0 and frame.pts != null) {
        self.first_frame_seconds = frame.pts.?.seconds;
    }

    const sample_count: usize = frame.sample_count;
    const channel_count: usize = frame.channel_count;
    const interleaved = try allocator.alloc(f32, sample_count * channel_count);
    defer allocator.free(interleaved);

    for (0..sample_count) |sample_index| {
        for (0..channel_count) |channel_index| {
            interleaved[sample_index * channel_count + channel_index] =
                frame.channels[channel_index][sample_index];
        }
    }

    const bytes = std.mem.sliceAsBytes(interleaved);
    if (sdl.SDL_QueueAudio(self.device, bytes.ptr, @intCast(bytes.len)) < 0) return error.Sdl;
    self.queued_byte_count += bytes.len;
}

pub fn drain(self: *@This()) void {
    while (sdl.SDL_GetQueuedAudioSize(self.device) > 0) {
        sdl.SDL_Delay(10);
    }
}

pub fn waitUntil(self: *@This(), seconds: f64) bool {
    const queued_end_seconds = self.queuedEndSeconds() orelse return false;
    if (seconds > queued_end_seconds) return false;

    while (true) {
        const current_seconds = self.currentSeconds() orelse return false;
        if (current_seconds >= seconds) return true;
        sdl.SDL_Delay(1);
    }
}

fn currentSeconds(self: *const @This()) ?f64 {
    const first_frame_seconds = self.first_frame_seconds orelse return null;
    const queued_byte_count = sdl.SDL_GetQueuedAudioSize(self.device);
    const played_byte_count = self.queued_byte_count - @min(self.queued_byte_count, queued_byte_count);
    return first_frame_seconds + (@as(f64, @floatFromInt(played_byte_count)) / self.bytesPerSecond());
}

fn queuedEndSeconds(self: *const @This()) ?f64 {
    const first_frame_seconds = self.first_frame_seconds orelse return null;
    return first_frame_seconds + (@as(f64, @floatFromInt(self.queued_byte_count)) / self.bytesPerSecond());
}

fn bytesPerSecond(self: *const @This()) f64 {
    return @floatFromInt(self.sample_rate * self.channel_count * @sizeOf(f32));
}
