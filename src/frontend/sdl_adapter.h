#ifndef NOVA16_SDL_ADAPTER_H
#define NOVA16_SDL_ADAPTER_H
#include <stdint.h>
typedef struct N16Host N16Host;
typedef struct { uint32_t held; uint32_t commands; } N16Input;
N16Host *n16_sdl_open(int scale);
void n16_sdl_close(N16Host *host);
const char *n16_sdl_error(void);
void n16_sdl_poll(N16Host *host, N16Input *input);
int n16_sdl_present(N16Host *host, const uint8_t *pixels, int verify);
void n16_sdl_pace(uint64_t start);
uint64_t n16_sdl_clock(void);
int n16_sdl_test_event(N16Host *host, int key, int up);
void n16_sdl_resize(N16Host *host, int width, int height);
#endif
