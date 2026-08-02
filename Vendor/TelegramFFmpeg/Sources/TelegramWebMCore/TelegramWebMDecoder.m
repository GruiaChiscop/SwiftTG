#include "TelegramWebMCore/TelegramWebMDecoder.h"

#include <Accelerate/Accelerate.h>
#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>

#include <TelegramFFmpegBinary.h>

enum {
    TelegramWebMMaximumDimension = 4096,
};

struct TelegramWebMDecoder {
    AVFormatContext *formatContext;
    AVCodecContext *codecContext;
    AVPacket *packet;
    AVFrame *frame;
    int videoStreamIndex;
    int32_t width;
    int32_t height;
    double frameRate;
    double duration;
    bool inputEnded;
    bool sentDrainPacket;
};

typedef struct TelegramWebMConversionInfo {
    vImage_YpCbCrToARGB limited601;
    vImage_YpCbCrToARGB limited709;
    vImage_YpCbCrToARGB full601;
    vImage_YpCbCrToARGB full709;
    bool valid;
} TelegramWebMConversionInfo;

static TelegramWebMConversionInfo TelegramWebMGetConversionInfo(void) {
    static TelegramWebMConversionInfo result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const vImage_YpCbCrPixelRange limitedRange = {16, 128, 235, 240, 255, 0, 255, 0};
        const vImage_YpCbCrPixelRange fullRange = {0, 128, 255, 255, 255, 1, 255, 0};

        vImage_Error errors[] = {
            vImageConvert_YpCbCrToARGB_GenerateConversion(
                kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,
                &limitedRange,
                &result.limited601,
                kvImage420Yp8_Cb8_Cr8,
                kvImageARGB8888,
                kvImageNoFlags
            ),
            vImageConvert_YpCbCrToARGB_GenerateConversion(
                kvImage_YpCbCrToARGBMatrix_ITU_R_709_2,
                &limitedRange,
                &result.limited709,
                kvImage420Yp8_Cb8_Cr8,
                kvImageARGB8888,
                kvImageNoFlags
            ),
            vImageConvert_YpCbCrToARGB_GenerateConversion(
                kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,
                &fullRange,
                &result.full601,
                kvImage420Yp8_Cb8_Cr8,
                kvImageARGB8888,
                kvImageNoFlags
            ),
            vImageConvert_YpCbCrToARGB_GenerateConversion(
                kvImage_YpCbCrToARGBMatrix_ITU_R_709_2,
                &fullRange,
                &result.full709,
                kvImage420Yp8_Cb8_Cr8,
                kvImageARGB8888,
                kvImageNoFlags
            ),
        };

        result.valid = true;
        for (size_t index = 0; index < sizeof(errors) / sizeof(errors[0]); index++) {
            if (errors[index] != kvImageNoError) {
                result.valid = false;
                break;
            }
        }
    });
    return result;
}

static void TelegramWebMDecoderFree(TelegramWebMDecoder *decoder) {
    if (decoder == NULL) {
        return;
    }

    av_frame_free(&decoder->frame);
    av_packet_free(&decoder->packet);
    avcodec_free_context(&decoder->codecContext);
    avformat_close_input(&decoder->formatContext);
    free(decoder);
}

static double TelegramWebMStreamFrameRate(const AVStream *stream) {
    AVRational rate = stream->avg_frame_rate;
    if (rate.num <= 0 || rate.den <= 0) {
        rate = stream->r_frame_rate;
    }

    const double value = rate.num > 0 && rate.den > 0 ? av_q2d(rate) : 30.0;
    if (!isfinite(value) || value <= 0.0) {
        return 30.0;
    }
    return fmin(60.0, fmax(1.0, value));
}

static double TelegramWebMStreamDuration(
    const AVFormatContext *formatContext,
    const AVStream *stream
) {
    if (stream->duration != AV_NOPTS_VALUE) {
        const double value = stream->duration * av_q2d(stream->time_base);
        if (isfinite(value) && value > 0.0) {
            return value;
        }
    }

    if (formatContext->duration != AV_NOPTS_VALUE) {
        const double value = (double)formatContext->duration / AV_TIME_BASE;
        if (isfinite(value) && value > 0.0) {
            return value;
        }
    }

    return 0.0;
}

TelegramWebMDecoder *TelegramWebMDecoderCreate(const char *path) {
    if (path == NULL || path[0] == '\0') {
        return NULL;
    }

    TelegramWebMDecoder *decoder = calloc(1, sizeof(TelegramWebMDecoder));
    if (decoder == NULL) {
        return NULL;
    }
    decoder->videoStreamIndex = -1;

    if (avformat_open_input(&decoder->formatContext, path, NULL, NULL) < 0 ||
        avformat_find_stream_info(decoder->formatContext, NULL) < 0) {
        TelegramWebMDecoderFree(decoder);
        return NULL;
    }

    decoder->videoStreamIndex = av_find_best_stream(
        decoder->formatContext,
        AVMEDIA_TYPE_VIDEO,
        -1,
        -1,
        NULL,
        0
    );
    if (decoder->videoStreamIndex < 0) {
        TelegramWebMDecoderFree(decoder);
        return NULL;
    }

    AVStream *stream = decoder->formatContext->streams[decoder->videoStreamIndex];
    if (stream->codecpar->codec_id != AV_CODEC_ID_VP9) {
        TelegramWebMDecoderFree(decoder);
        return NULL;
    }

    const AVCodec *codec = avcodec_find_decoder_by_name("libvpx-vp9");
    decoder->codecContext = avcodec_alloc_context3(codec);
    if (codec == NULL || decoder->codecContext == NULL ||
        avcodec_parameters_to_context(decoder->codecContext, stream->codecpar) < 0 ||
        avcodec_open2(decoder->codecContext, codec, NULL) < 0) {
        TelegramWebMDecoderFree(decoder);
        return NULL;
    }

    decoder->width = decoder->codecContext->width;
    decoder->height = decoder->codecContext->height;
    if (decoder->width <= 0 || decoder->height <= 0 ||
        decoder->width > TelegramWebMMaximumDimension ||
        decoder->height > TelegramWebMMaximumDimension) {
        TelegramWebMDecoderFree(decoder);
        return NULL;
    }

    decoder->packet = av_packet_alloc();
    decoder->frame = av_frame_alloc();
    if (decoder->packet == NULL || decoder->frame == NULL) {
        TelegramWebMDecoderFree(decoder);
        return NULL;
    }

    decoder->frameRate = TelegramWebMStreamFrameRate(stream);
    decoder->duration = TelegramWebMStreamDuration(decoder->formatContext, stream);
    return decoder;
}

void TelegramWebMDecoderDestroy(TelegramWebMDecoder *decoder) {
    TelegramWebMDecoderFree(decoder);
}

int32_t TelegramWebMDecoderGetWidth(const TelegramWebMDecoder *decoder) {
    return decoder != NULL ? decoder->width : 0;
}

int32_t TelegramWebMDecoderGetHeight(const TelegramWebMDecoder *decoder) {
    return decoder != NULL ? decoder->height : 0;
}

double TelegramWebMDecoderGetFrameRate(const TelegramWebMDecoder *decoder) {
    return decoder != NULL ? decoder->frameRate : 0.0;
}

double TelegramWebMDecoderGetDuration(const TelegramWebMDecoder *decoder) {
    return decoder != NULL ? decoder->duration : 0.0;
}

static const vImage_YpCbCrToARGB *TelegramWebMFrameConversion(
    const AVFrame *frame,
    const TelegramWebMConversionInfo *info
) {
    const bool fullRange = frame->color_range == AVCOL_RANGE_JPEG ||
        frame->format == AV_PIX_FMT_YUVJ420P;
    const bool bt709 = frame->colorspace == AVCOL_SPC_BT709;

    if (fullRange) {
        return bt709 ? &info->full709 : &info->full601;
    }
    return bt709 ? &info->limited709 : &info->limited601;
}

static bool TelegramWebMRenderFrame(
    const AVFrame *frame,
    uint8_t *bgra,
    size_t bytesPerRow
) {
    if (frame == NULL || bgra == NULL || frame->width <= 0 || frame->height <= 0 ||
        bytesPerRow < (size_t)frame->width * 4 ||
        frame->data[0] == NULL || frame->data[1] == NULL || frame->data[2] == NULL ||
        frame->linesize[0] <= 0 || frame->linesize[1] <= 0 || frame->linesize[2] <= 0) {
        return false;
    }

    const bool hasAlpha = frame->format == AV_PIX_FMT_YUVA420P;
    if (frame->format != AV_PIX_FMT_YUV420P &&
        frame->format != AV_PIX_FMT_YUVJ420P &&
        !hasAlpha) {
        return false;
    }
    if (hasAlpha && (frame->data[3] == NULL || frame->linesize[3] <= 0)) {
        return false;
    }

    const TelegramWebMConversionInfo info = TelegramWebMGetConversionInfo();
    if (!info.valid) {
        return false;
    }

    vImage_Buffer sourceY = {
        .data = frame->data[0],
        .height = (vImagePixelCount)frame->height,
        .width = (vImagePixelCount)frame->width,
        .rowBytes = (size_t)frame->linesize[0],
    };
    vImage_Buffer sourceCb = {
        .data = frame->data[1],
        .height = (vImagePixelCount)frame->height,
        .width = (vImagePixelCount)((frame->width + 1) / 2),
        .rowBytes = (size_t)frame->linesize[1],
    };
    vImage_Buffer sourceCr = {
        .data = frame->data[2],
        .height = (vImagePixelCount)frame->height,
        .width = (vImagePixelCount)((frame->width + 1) / 2),
        .rowBytes = (size_t)frame->linesize[2],
    };
    vImage_Buffer destination = {
        .data = bgra,
        .height = (vImagePixelCount)frame->height,
        .width = (vImagePixelCount)frame->width,
        .rowBytes = bytesPerRow,
    };

    const vImage_Error conversionError = vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(
        &sourceY,
        &sourceCb,
        &sourceCr,
        &destination,
        TelegramWebMFrameConversion(frame, &info),
        NULL,
        0xff,
        kvImageDoNotTile
    );
    if (conversionError != kvImageNoError) {
        return false;
    }

    if (hasAlpha) {
        for (int32_t y = 0; y < frame->height; y++) {
            uint8_t *outputRow = bgra + (size_t)y * bytesPerRow;
            const uint8_t *alphaRow = frame->data[3] + (size_t)y * frame->linesize[3];
            for (int32_t x = 0; x < frame->width; x++) {
                outputRow[(size_t)x * 4] = alphaRow[x];
            }
        }
    }

    if (vImagePremultiplyData_ARGB8888(
            &destination,
            &destination,
            kvImageDoNotTile
        ) != kvImageNoError) {
        return false;
    }

    const uint8_t permutation[4] = {3, 2, 1, 0};
    return vImagePermuteChannels_ARGB8888(
        &destination,
        &destination,
        permutation,
        kvImageDoNotTile
    ) == kvImageNoError;
}

TelegramWebMFrameStatus TelegramWebMDecoderRenderNextFrame(
    TelegramWebMDecoder *decoder,
    uint8_t *bgra,
    size_t bytesPerRow,
    double *seconds
) {
    if (decoder == NULL || bgra == NULL ||
        bytesPerRow < (size_t)decoder->width * 4) {
        return TelegramWebMFrameStatusError;
    }

    AVStream *stream = decoder->formatContext->streams[decoder->videoStreamIndex];
    while (true) {
        const int receiveResult = avcodec_receive_frame(decoder->codecContext, decoder->frame);
        if (receiveResult >= 0) {
            const int64_t timestamp = decoder->frame->best_effort_timestamp;
            if (seconds != NULL) {
                *seconds = timestamp == AV_NOPTS_VALUE
                    ? 0.0
                    : fmax(0.0, timestamp * av_q2d(stream->time_base));
            }

            const bool rendered = TelegramWebMRenderFrame(decoder->frame, bgra, bytesPerRow);
            av_frame_unref(decoder->frame);
            return rendered ? TelegramWebMFrameStatusFrame : TelegramWebMFrameStatusError;
        }
        if (receiveResult == AVERROR_EOF) {
            return TelegramWebMFrameStatusEnd;
        }
        if (receiveResult != AVERROR(EAGAIN)) {
            return TelegramWebMFrameStatusError;
        }

        if (decoder->inputEnded) {
            if (!decoder->sentDrainPacket) {
                const int sendResult = avcodec_send_packet(decoder->codecContext, NULL);
                if (sendResult < 0 && sendResult != AVERROR_EOF) {
                    return TelegramWebMFrameStatusError;
                }
                decoder->sentDrainPacket = true;
                continue;
            }
            return TelegramWebMFrameStatusEnd;
        }

        int readResult;
        do {
            av_packet_unref(decoder->packet);
            readResult = av_read_frame(decoder->formatContext, decoder->packet);
        } while (readResult >= 0 && decoder->packet->stream_index != decoder->videoStreamIndex);

        if (readResult == AVERROR_EOF) {
            decoder->inputEnded = true;
            continue;
        }
        if (readResult < 0) {
            return TelegramWebMFrameStatusError;
        }

        const int sendResult = avcodec_send_packet(decoder->codecContext, decoder->packet);
        av_packet_unref(decoder->packet);
        if (sendResult < 0) {
            return TelegramWebMFrameStatusError;
        }
    }
}

bool TelegramWebMDecoderRestart(TelegramWebMDecoder *decoder) {
    if (decoder == NULL) {
        return false;
    }

    const int seekResult = av_seek_frame(
        decoder->formatContext,
        decoder->videoStreamIndex,
        0,
        AVSEEK_FLAG_BACKWARD
    );
    if (seekResult < 0) {
        return false;
    }

    avcodec_flush_buffers(decoder->codecContext);
    av_packet_unref(decoder->packet);
    av_frame_unref(decoder->frame);
    decoder->inputEnded = false;
    decoder->sentDrainPacket = false;
    return true;
}
