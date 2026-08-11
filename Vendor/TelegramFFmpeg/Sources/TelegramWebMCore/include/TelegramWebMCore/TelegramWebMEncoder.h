#ifndef TelegramWebMEncoder_h
#define TelegramWebMEncoder_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TelegramWebMEncoder TelegramWebMEncoder;

TelegramWebMEncoder *TelegramWebMEncoderCreate(
    const char *path,
    int32_t width,
    int32_t height,
    int32_t frameRate,
    int64_t bitRate
);

void TelegramWebMEncoderDestroy(TelegramWebMEncoder *encoder);

bool TelegramWebMEncoderAppendBGRAFrame(
    TelegramWebMEncoder *encoder,
    const uint8_t *bgra,
    size_t bytesPerRow
);

bool TelegramWebMEncoderFinish(TelegramWebMEncoder *encoder);

#ifdef __cplusplus
}
#endif

#endif
