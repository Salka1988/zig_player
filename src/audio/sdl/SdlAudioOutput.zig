const std = @import("std");

const F32PlanarAudioFrame = @import("../../domain/F32PlanarAudioFrame.zig");
const sdl = @import("../../sdl/bindings.zig");

device: sdl.SDL_AudioDeviceID,
sample_rate: u32,
channel_count: u32,
bytes_per_sample: u32,
started: bool = false,

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

    var obtained: sdl.SDL_AudioSpec = undefined;
    const device = sdl.SDL_OpenAudioDevice(null, 0, &desired, &obtained, 0);
    if (device == 0) return error.Sdl;
    errdefer sdl.SDL_CloseAudioDevice(device);
    if (obtained.format != sdl.AUDIO_F32SYS) return error.UnsupportedAudioSampleFormat;
    if (obtained.channels != channel_count) return error.UnsupportedAudioChannelCount;

    return .{
        .device = device,
        .sample_rate = @intCast(obtained.freq),
        .channel_count = obtained.channels,
        .bytes_per_sample = @sizeOf(f32),
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
}

pub fn drain(self: *@This()) void {
    self.start();
    while (sdl.SDL_GetQueuedAudioSize(self.device) > 0) {
        sdl.SDL_Delay(10);
    }
}

pub fn start(self: *@This()) void {
    if (!self.started) {
        sdl.SDL_PauseAudioDevice(self.device, 0);
        self.started = true;
    }
}

pub fn queuedSeconds(self: *const @This()) f64 {
    return @as(f64, @floatFromInt(sdl.SDL_GetQueuedAudioSize(self.device))) / self.bytesPerSecond();
}

fn bytesPerSecond(self: *const @This()) f64 {
    return @floatFromInt(self.sample_rate * self.channel_count * self.bytes_per_sample);
}
