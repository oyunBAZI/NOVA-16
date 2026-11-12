//! Optional host-only SDL2 C ABI. The deterministic core never imports SDL.
const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
const video = @import("../devices/video.zig");
const Window = opaque {};
const Renderer = opaque {};
const Texture = opaque {};
extern "SDL2" fn SDL_Init(u32) c_int;
extern "SDL2" fn SDL_Quit() void;
extern "SDL2" fn SDL_GetError() [*:0]const u8;
extern "SDL2" fn SDL_CreateWindow([*:0]const u8, c_int, c_int, c_int, c_int, u32) ?*Window;
extern "SDL2" fn SDL_DestroyWindow(*Window) void;
extern "SDL2" fn SDL_CreateRenderer(*Window, c_int, u32) ?*Renderer;
extern "SDL2" fn SDL_DestroyRenderer(*Renderer) void;
extern "SDL2" fn SDL_CreateTexture(*Renderer, u32, c_int, c_int, c_int) ?*Texture;
extern "SDL2" fn SDL_DestroyTexture(*Texture) void;
extern "SDL2" fn SDL_UpdateTexture(*Texture, ?*const anyopaque, *const anyopaque, c_int) c_int;
extern "SDL2" fn SDL_RenderClear(*Renderer) c_int;
extern "SDL2" fn SDL_RenderCopy(*Renderer, *Texture, ?*const anyopaque, ?*const anyopaque) c_int;
extern "SDL2" fn SDL_RenderPresent(*Renderer) void;
extern "SDL2" fn SDL_RenderSetLogicalSize(*Renderer, c_int, c_int) c_int;
extern "SDL2" fn SDL_SetHint([*:0]const u8, [*:0]const u8) c_int;
extern "SDL2" fn SDL_PollEvent(*Event) c_int;
extern "SDL2" fn SDL_GetKeyboardState(?*c_int) [*]const u8;
extern "SDL2" fn SDL_GetTicks64() u64;
extern "SDL2" fn SDL_Delay(u32) void;
// SDL_Event is 56 bytes on supported desktop ABIs. Keyboard scancode is at 16.
const Event = extern struct { kind: u32, padding: [52]u8 };
fn check(code: c_int) !void {
    if (code < 0) {
        std.debug.print("SDL2: {s}\n", .{SDL_GetError()});
        return error.SdlFailure;
    }
}
pub fn run(m: *Machine, scale: u32, max_frames: u64, cap: u64) !void {
    try check(SDL_Init(0x20));
    defer SDL_Quit();
    _ = SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0");
    const window = SDL_CreateWindow("NOVA-16 | arrows Z X Enter RShift | Space pause | R reset", 0x2fff0000, 0x2fff0000, @intCast(128 * scale), @intCast(96 * scale), 4) orelse return error.SdlWindow;
    defer SDL_DestroyWindow(window);
    const renderer = SDL_CreateRenderer(window, -1, 0) orelse return error.SdlRenderer;
    defer SDL_DestroyRenderer(renderer);
    try check(SDL_RenderSetLogicalSize(renderer, 128, 96));
    // SDL_PIXELFORMAT_RGB24 = SDL_DEFINE_PIXELFORMAT(7,1,0,24,3).
    const texture = SDL_CreateTexture(renderer, 0x17101803, 1, 128, 96) orelse return error.SdlTexture;
    defer SDL_DestroyTexture(texture);
    var pixels: [128 * 96 * 3]u8 = undefined;
    var paused = false;
    var frame: u64 = 0;
    while (frame < max_frames and m.cpu.retired < cap) : (frame += 1) {
        const start = SDL_GetTicks64();
        var event: Event align(8) = undefined;
        while (SDL_PollEvent(&event) != 0) {
            if (event.kind == 0x100) return;
            if (event.kind == 0x300 and event.padding[9] == 0) {
                const scancode = std.mem.readInt(u32, event.padding[12..16], .native);
                switch (scancode) {
                    41 => return,
                    44 => paused = !paused,
                    21 => {
                        m.reset();
                        paused = false;
                    },
                    else => {},
                }
            }
        }
        const keys = SDL_GetKeyboardState(null);
        var bits: u8 = 0;
        const scans = [_]usize{ 82, 81, 80, 79, 29, 27, 40, 229 };
        for (scans, 0..) |sc, k| {
            if (keys[sc] != 0) bits |= @as(u8, 1) << @as(u3, @intCast(k));
        }
        if (!paused and !m.cpu.halted and !m.cpu.paused and m.cpu.trap == null) m.frame(bits, cap);
        video.render(m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled, &pixels);
        try check(SDL_UpdateTexture(texture, null, &pixels, 128 * 3));
        try check(SDL_RenderClear(renderer));
        try check(SDL_RenderCopy(renderer, texture, null, null));
        SDL_RenderPresent(renderer);
        const elapsed = SDL_GetTicks64() - start;
        if (elapsed < 16) SDL_Delay(@intCast(16 - elapsed));
    }
}
