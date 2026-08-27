pub const SDL_INIT_VIDEO: u32 = 0x00000020;
pub const SDL_WINDOW_SHOWN: u32 = 0x00000004;
pub const SDL_WINDOWPOS_CENTERED: i32 = 0x2FFF0000;
pub const SDL_RENDERER_ACCELERATED: u32 = 0x00000002;
pub const SDL_TEXTUREACCESS_STREAMING: i32 = 1;
pub const SDL_PIXELFORMAT_IYUV: u32 = 1448433993;
pub const SDL_QUIT: u32 = 0x100;

pub const SDL_Window = opaque {};
pub const SDL_Renderer = opaque {};
pub const SDL_Texture = opaque {};

pub const SDL_Event = extern union {
    type: u32,
    padding: [56]u8,
};

pub extern fn SDL_Init(flags: u32) c_int;
pub extern fn SDL_Quit() void;

pub extern fn SDL_CreateWindow(
    title: [*:0]const u8,
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
    flags: u32,
) ?*SDL_Window;
pub extern fn SDL_DestroyWindow(window: *SDL_Window) void;

pub extern fn SDL_CreateRenderer(
    window: *SDL_Window,
    index: c_int,
    flags: u32,
) ?*SDL_Renderer;
pub extern fn SDL_DestroyRenderer(renderer: *SDL_Renderer) void;

pub extern fn SDL_CreateTexture(
    renderer: *SDL_Renderer,
    format: u32,
    access: c_int,
    w: c_int,
    h: c_int,
) ?*SDL_Texture;
pub extern fn SDL_DestroyTexture(texture: *SDL_Texture) void;

pub extern fn SDL_UpdateYUVTexture(
    texture: *SDL_Texture,
    rect: ?*const anyopaque,
    y_plane: [*c]const u8,
    y_pitch: c_int,
    u_plane: [*c]const u8,
    u_pitch: c_int,
    v_plane: [*c]const u8,
    v_pitch: c_int,
) c_int;

pub extern fn SDL_RenderClear(renderer: *SDL_Renderer) c_int;
pub extern fn SDL_RenderCopy(
    renderer: *SDL_Renderer,
    texture: *SDL_Texture,
    srcrect: ?*const anyopaque,
    dstrect: ?*const anyopaque,
) c_int;
pub extern fn SDL_RenderPresent(renderer: *SDL_Renderer) void;
pub extern fn SDL_PumpEvents() void;
pub extern fn SDL_PollEvent(event: *SDL_Event) c_int;
pub extern fn SDL_GetTicks64() u64;
pub extern fn SDL_Delay(ms: u32) void;
