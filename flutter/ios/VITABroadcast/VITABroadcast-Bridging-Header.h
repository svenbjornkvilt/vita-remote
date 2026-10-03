#include <stdint.h>

int32_t vita_broadcast_start(const char *app_dir);
void vita_broadcast_frame(const uint8_t *data, uintptr_t len, uint32_t width, uint32_t height, uint32_t stride);
void vita_broadcast_stop(void);
