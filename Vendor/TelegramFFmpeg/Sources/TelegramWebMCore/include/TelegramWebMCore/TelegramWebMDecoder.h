#ifndef TelegramWebMDecoder_h
#define TelegramWebMDecoder_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "TelegramWebMEncoder.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TelegramWebMDecoder TelegramWebMDecoder;

typedef enum TelegramWebMFrameStatus {
    TelegramWebMFrameStatusError = -1,
    TelegramWebMFrameStatusEnd = 0,
    TelegramWebMFrameStatusFrame = 1,
} TelegramWebMFrameStatus;

TelegramWebMDecoder *TelegramWebMDecoderCreate(const char *path);
void TelegramWebMDecoderDestroy(TelegramWebMDecoder *decoder);

int32_t TelegramWebMDecoderGetWidth(const TelegramWebMDecoder *decoder);
int32_t TelegramWebMDecoderGetHeight(const TelegramWebMDecoder *decoder);
double TelegramWebMDecoderGetFrameRate(const TelegramWebMDecoder *decoder);
double TelegramWebMDecoderGetDuration(const TelegramWebMDecoder *decoder);

TelegramWebMFrameStatus TelegramWebMDecoderRenderNextFrame(
    TelegramWebMDecoder *decoder,
    uint8_t *bgra,
    size_t bytesPerRow,
    double *seconds
);

bool TelegramWebMDecoderRestart(TelegramWebMDecoder *decoder);

#ifdef __cplusplus
}
#endif

#endif
