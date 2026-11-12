/* SDL owns its ABI. This adapter is compiled against the platform SDL2 headers. */
#define SDL_MAIN_HANDLED
#include <SDL2/SDL.h>
#include <stdlib.h>
#include <stddef.h>
#include "sdl_adapter.h"
_Static_assert(sizeof(N16Input) == 8, "N16Input ABI size");
_Static_assert(offsetof(N16Input, commands) == 4, "N16Input ABI offset");
_Static_assert(SDL_NUM_SCANCODES > SDL_SCANCODE_RSHIFT, "SDL2 scancode range");
struct N16Host {
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;
    uint8_t held;
};
static const SDL_Scancode keys[] = {
    SDL_SCANCODE_UP, SDL_SCANCODE_DOWN, SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT,
    SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_RETURN, SDL_SCANCODE_RSHIFT,
    SDL_SCANCODE_SPACE, SDL_SCANCODE_R, SDL_SCANCODE_ESCAPE
};
const char *n16_sdl_error(void) { return SDL_GetError(); }
void n16_sdl_close(N16Host *host) {
    if (!host) return;
    if (host->texture) SDL_DestroyTexture(host->texture);
    if (host->renderer) SDL_DestroyRenderer(host->renderer);
    if (host->window) SDL_DestroyWindow(host->window);
    free(host);
    SDL_Quit();
}
N16Host *n16_sdl_open(int scale) {
    if (scale < 1 || scale > 32) { SDL_SetError("scale must be 1..32"); return NULL; }
    SDL_SetMainReady();
    if (SDL_Init(SDL_INIT_VIDEO) < 0) return NULL;
    N16Host *host = calloc(1, sizeof(*host));
    if (!host) { SDL_SetError("host allocation failed"); SDL_Quit(); return NULL; }
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
    host->window = SDL_CreateWindow("NOVA-16 | arrows Z X Enter RShift | Space pause | R reset",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 128 * scale, 96 * scale,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    if (!host->window) goto fail;
    SDL_SetWindowMinimumSize(host->window, 128, 96);
    host->renderer = SDL_CreateRenderer(host->window, -1, 0);
    if (!host->renderer) goto fail;
    if (SDL_RenderSetLogicalSize(host->renderer, 128, 96) < 0 ||
        SDL_RenderSetIntegerScale(host->renderer, SDL_TRUE) < 0) goto fail;
    if (SDL_SetRenderDrawColor(host->renderer, 0, 0, 0, 255) < 0) goto fail;
    host->texture = SDL_CreateTexture(host->renderer, SDL_PIXELFORMAT_RGB24,
        SDL_TEXTUREACCESS_STREAMING, 128, 96);
    if (!host->texture) goto fail;
    Uint32 format; int width, height;
    if (SDL_QueryTexture(host->texture, &format, NULL, &width, &height) < 0 ||
        format != SDL_PIXELFORMAT_RGB24 || width != 128 || height != 96) {
        SDL_SetError("unexpected SDL texture format"); goto fail;
    }
    return host;
fail: {
    char message[256]; SDL_strlcpy(message, SDL_GetError(), sizeof(message));
    n16_sdl_close(host); SDL_SetError("%s", message); return NULL;
    }
}
void n16_sdl_poll(N16Host *host, N16Input *input) {
    SDL_Event event;
    input->commands = 0;
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_QUIT) input->commands |= 4;
        if (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_FOCUS_LOST)
            host->held = 0;
        if (event.type != SDL_KEYDOWN && event.type != SDL_KEYUP) continue;
        for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
            if (event.key.keysym.scancode != keys[i]) continue;
            if (i < 8) {
                if (event.type == SDL_KEYDOWN) host->held |= (uint8_t)(1u << i);
                else host->held &= (uint8_t)~(1u << i);
            } else if (event.type == SDL_KEYDOWN && !event.key.repeat) {
                if (i == 8) input->commands ^= 1;
                if (i == 9) input->commands |= 2;
                if (i == 10) input->commands |= 4;
            }
        }
    }
    input->held = host->held;
}
/* Read back the actual renderer output, checking scaling and letterboxing. */
static int verify_pixels(N16Host *host, const uint8_t *pixels) {
    int width, height;
    if (SDL_GetRendererOutputSize(host->renderer, &width, &height) < 0) return -1;
    if (width < 128 || height < 96 || width > 8192 || height > 8192)
        return SDL_SetError("invalid output dimensions");
    size_t size = (size_t)width * (size_t)height * 3;
    uint8_t *actual = malloc(size);
    if (!actual) return SDL_SetError("readback allocation failed");
    /* ReadPixels is clipped to the current viewport. Temporarily expose the
       full target so letterbox bytes are read too, then restore logical size. */
    int result = SDL_RenderSetLogicalSize(host->renderer, 0, 0);
    if (result == 0)
        result = SDL_RenderReadPixels(host->renderer, &(SDL_Rect){0, 0, width, height}, SDL_PIXELFORMAT_RGB24, actual, width * 3);
    if (SDL_RenderSetLogicalSize(host->renderer, 128, 96) < 0) result = -1;
    int scale = width / 128 < height / 96 ? width / 128 : height / 96;
    int left = (width - 128 * scale) / 2, top = (height - 96 * scale) / 2;
    for (int y = 0; result == 0 && y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const uint8_t black[3] = {0, 0, 0};
            const uint8_t *expected = black;
            if (x >= left && x < left + 128 * scale && y >= top && y < top + 96 * scale)
                expected = pixels + (((y - top) / scale) * 128 + (x - left) / scale) * 3;
            if (SDL_memcmp(actual + ((size_t)y * width + x) * 3, expected, 3) != 0) {
                result = SDL_SetError("renderer pixel mismatch at %d,%d (output %dx%d): actual=%u,%u,%u expected=%u,%u,%u", x, y, width, height, actual[((size_t)y*width+x)*3], actual[((size_t)y*width+x)*3+1], actual[((size_t)y*width+x)*3+2], expected[0], expected[1], expected[2]); break;
            }
        }
    }
    free(actual); return result;
}
int n16_sdl_present(N16Host *host, const uint8_t *pixels, int verify) {
    if (SDL_UpdateTexture(host->texture, NULL, pixels, 128 * 3) < 0 ||
        SDL_RenderClear(host->renderer) < 0 ||
        SDL_RenderCopy(host->renderer, host->texture, NULL, NULL) < 0) return -1;
    if (verify && verify_pixels(host, pixels) < 0) return -1;
    SDL_RenderPresent(host->renderer); return 0;
}
uint64_t n16_sdl_clock(void) { return SDL_GetPerformanceCounter(); }
void n16_sdl_pace(uint64_t start) {
    const uint64_t frequency = SDL_GetPerformanceFrequency();
    const uint64_t deadline = start + frequency / 60;
    uint64_t now;
    while ((now = SDL_GetPerformanceCounter()) < deadline) {
        const uint64_t ms = (deadline - now) * 1000 / frequency;
        SDL_Delay(ms > 1 ? (Uint32)(ms - 1) : 0);
    }
}
int n16_sdl_test_event(N16Host *host, int key, int up) {
    SDL_Event event; SDL_zero(event);
    if (key == -1) event.type = SDL_QUIT;
    else if (key == -2) { event.type = SDL_WINDOWEVENT; event.window.event = SDL_WINDOWEVENT_FOCUS_LOST; }
    else {
        if (key < 0 || key > 10) return -1;
        event.type = up ? SDL_KEYUP : SDL_KEYDOWN;
        event.key.windowID = SDL_GetWindowID(host->window);
        event.key.keysym.scancode = keys[key];
        event.key.state = up ? SDL_RELEASED : SDL_PRESSED;
    }
    return SDL_PushEvent(&event) == 1 ? 0 : -1;
}
void n16_sdl_resize(N16Host *host, int width, int height) {
    SDL_SetWindowSize(host->window, width, height); SDL_PumpEvents();
}
