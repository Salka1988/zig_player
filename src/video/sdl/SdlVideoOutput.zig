const Yuv420pFrame = @import("../../domain/Yuv420pFrame.zig");
const sdl = @import("../../sdl/bindings.zig");

window: *sdl.SDL_Window,
renderer: *sdl.SDL_Renderer,
texture: *sdl.SDL_Texture,

pub fn init(width: u32, height: u32) !@This() {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) < 0) return error.Sdl;
    errdefer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow(
        "zig_player",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        @intCast(width),
        @intCast(height),
        sdl.SDL_WINDOW_SHOWN,
    ) orelse return error.Sdl;
    errdefer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED) orelse return error.Sdl;
    errdefer sdl.SDL_DestroyRenderer(renderer);

    const texture = sdl.SDL_CreateTexture(
        renderer,
        sdl.SDL_PIXELFORMAT_IYUV,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        @intCast(width),
        @intCast(height),
    ) orelse return error.Sdl;
    errdefer sdl.SDL_DestroyTexture(texture);

    return .{
        .window = window,
        .renderer = renderer,
        .texture = texture,
    };
}

pub fn deinit(self: *@This()) void {
    sdl.SDL_DestroyTexture(self.texture);
    sdl.SDL_DestroyRenderer(self.renderer);
    sdl.SDL_DestroyWindow(self.window);
    sdl.SDL_Quit();
}

pub fn present(self: *@This(), frame: Yuv420pFrame) !bool {
    if (sdl.SDL_UpdateYUVTexture(
        self.texture,
        null,
        frame.y,
        @intCast(frame.y_stride),
        frame.u,
        @intCast(frame.u_stride),
        frame.v,
        @intCast(frame.v_stride),
    ) < 0) return error.Sdl;

    if (sdl.SDL_RenderClear(self.renderer) < 0) return error.Sdl;
    if (sdl.SDL_RenderCopy(self.renderer, self.texture, null, null) < 0) return error.Sdl;
    sdl.SDL_RenderPresent(self.renderer);
    sdl.SDL_PumpEvents();

    sdl.SDL_Delay(33);
    return true;
}
