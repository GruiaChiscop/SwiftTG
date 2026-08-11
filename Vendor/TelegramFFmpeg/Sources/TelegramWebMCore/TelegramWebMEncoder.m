#include "TelegramWebMCore/TelegramWebMEncoder.h"

#include <stdlib.h>

#include <TelegramFFmpegBinary.h>
#include <libavutil/opt.h>

struct TelegramWebMEncoder {
    AVFormatContext *formatContext;
    AVCodecContext *codecContext;
    AVStream *stream;
    AVFrame *frame;
    AVPacket *packet;
    int64_t frameIndex;
    bool headerWritten;
    bool finished;
};

static uint8_t TelegramWebMClampByte(int value) {
    return (uint8_t)(value < 0 ? 0 : (value > 255 ? 255 : value));
}

static void TelegramWebMUnpremultiplyBGRA(
    const uint8_t *pixel,
    int *red,
    int *green,
    int *blue,
    int *alpha
) {
    *alpha = pixel[3];
    if (*alpha == 0) {
        *red = 0;
        *green = 0;
        *blue = 0;
        return;
    }

    *red = (pixel[2] * 255 + *alpha / 2) / *alpha;
    *green = (pixel[1] * 255 + *alpha / 2) / *alpha;
    *blue = (pixel[0] * 255 + *alpha / 2) / *alpha;
    *red = *red > 255 ? 255 : *red;
    *green = *green > 255 ? 255 : *green;
    *blue = *blue > 255 ? 255 : *blue;
}

static int TelegramWebMWriteAvailablePackets(TelegramWebMEncoder *encoder) {
    while (true) {
        const int receiveResult = avcodec_receive_packet(encoder->codecContext, encoder->packet);
        if (receiveResult == AVERROR(EAGAIN) || receiveResult == AVERROR_EOF) {
            return 0;
        }
        if (receiveResult < 0) {
            return receiveResult;
        }

        av_packet_rescale_ts(
            encoder->packet,
            encoder->codecContext->time_base,
            encoder->stream->time_base
        );
        encoder->packet->stream_index = encoder->stream->index;
        const int writeResult = av_interleaved_write_frame(encoder->formatContext, encoder->packet);
        av_packet_unref(encoder->packet);
        if (writeResult < 0) {
            return writeResult;
        }
    }
}

static void TelegramWebMEncoderFree(TelegramWebMEncoder *encoder) {
    if (encoder == NULL) {
        return;
    }

    av_packet_free(&encoder->packet);
    av_frame_free(&encoder->frame);
    avcodec_free_context(&encoder->codecContext);
    if (encoder->formatContext != NULL) {
        if (encoder->formatContext->pb != NULL) {
            avio_closep(&encoder->formatContext->pb);
        }
        avformat_free_context(encoder->formatContext);
    }
    free(encoder);
}

TelegramWebMEncoder *TelegramWebMEncoderCreate(
    const char *path,
    int32_t width,
    int32_t height,
    int32_t frameRate,
    int64_t bitRate
) {
    if (path == NULL || path[0] == '\0' || width <= 0 || height <= 0 ||
        width % 2 != 0 || height % 2 != 0 || frameRate <= 0 || frameRate > 60 ||
        bitRate <= 0) {
        return NULL;
    }

    TelegramWebMEncoder *encoder = calloc(1, sizeof(TelegramWebMEncoder));
    if (encoder == NULL) {
        return NULL;
    }

    if (avformat_alloc_output_context2(&encoder->formatContext, NULL, "webm", path) < 0 ||
        encoder->formatContext == NULL) {
        TelegramWebMEncoderFree(encoder);
        return NULL;
    }

    const AVCodec *codec = avcodec_find_encoder_by_name("libvpx-vp9");
    if (codec == NULL) {
        TelegramWebMEncoderFree(encoder);
        return NULL;
    }

    encoder->stream = avformat_new_stream(encoder->formatContext, NULL);
    encoder->codecContext = avcodec_alloc_context3(codec);
    if (encoder->stream == NULL || encoder->codecContext == NULL) {
        TelegramWebMEncoderFree(encoder);
        return NULL;
    }

    encoder->codecContext->codec_id = AV_CODEC_ID_VP9;
    encoder->codecContext->codec_type = AVMEDIA_TYPE_VIDEO;
    encoder->codecContext->bit_rate = bitRate;
    encoder->codecContext->width = width;
    encoder->codecContext->height = height;
    encoder->codecContext->time_base = (AVRational){1, frameRate};
    encoder->codecContext->framerate = (AVRational){frameRate, 1};
    encoder->codecContext->gop_size = frameRate * 3;
    encoder->codecContext->max_b_frames = 0;
    encoder->codecContext->pix_fmt = AV_PIX_FMT_YUVA420P;
    encoder->codecContext->color_range = AVCOL_RANGE_MPEG;
    encoder->codecContext->colorspace = AVCOL_SPC_BT709;
    encoder->codecContext->thread_count = 2;
    if ((encoder->formatContext->oformat->flags & AVFMT_GLOBALHEADER) != 0) {
        encoder->codecContext->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }

    av_opt_set(encoder->codecContext->priv_data, "deadline", "realtime", 0);
    av_opt_set(encoder->codecContext->priv_data, "cpu-used", "5", 0);
    av_opt_set(encoder->codecContext->priv_data, "row-mt", "1", 0);
    av_opt_set(encoder->codecContext->priv_data, "auto-alt-ref", "0", 0);

    if (avcodec_open2(encoder->codecContext, codec, NULL) < 0 ||
        avcodec_parameters_from_context(encoder->stream->codecpar, encoder->codecContext) < 0) {
        TelegramWebMEncoderFree(encoder);
        return NULL;
    }
    encoder->stream->time_base = encoder->codecContext->time_base;
    encoder->stream->avg_frame_rate = encoder->codecContext->framerate;
    av_dict_set(&encoder->stream->metadata, "alpha_mode", "1", 0);

    if ((encoder->formatContext->oformat->flags & AVFMT_NOFILE) == 0 &&
        avio_open(&encoder->formatContext->pb, path, AVIO_FLAG_WRITE) < 0) {
        TelegramWebMEncoderFree(encoder);
        return NULL;
    }
    if (avformat_write_header(encoder->formatContext, NULL) < 0) {
        TelegramWebMEncoderFree(encoder);
        return NULL;
    }
    encoder->headerWritten = true;

    encoder->frame = av_frame_alloc();
    encoder->packet = av_packet_alloc();
    if (encoder->frame == NULL || encoder->packet == NULL) {
        TelegramWebMEncoderFree(encoder);
        return NULL;
    }
    encoder->frame->format = AV_PIX_FMT_YUVA420P;
    encoder->frame->width = width;
    encoder->frame->height = height;
    if (av_frame_get_buffer(encoder->frame, 32) < 0) {
        TelegramWebMEncoderFree(encoder);
        return NULL;
    }
    return encoder;
}

void TelegramWebMEncoderDestroy(TelegramWebMEncoder *encoder) {
    TelegramWebMEncoderFree(encoder);
}

bool TelegramWebMEncoderAppendBGRAFrame(
    TelegramWebMEncoder *encoder,
    const uint8_t *bgra,
    size_t bytesPerRow
) {
    if (encoder == NULL || bgra == NULL || encoder->finished ||
        bytesPerRow < (size_t)encoder->codecContext->width * 4 ||
        av_frame_make_writable(encoder->frame) < 0) {
        return false;
    }

    const int width = encoder->codecContext->width;
    const int height = encoder->codecContext->height;
    for (int y = 0; y < height; y++) {
        const uint8_t *sourceRow = bgra + (size_t)y * bytesPerRow;
        uint8_t *lumaRow = encoder->frame->data[0] + (size_t)y * encoder->frame->linesize[0];
        uint8_t *alphaRow = encoder->frame->data[3] + (size_t)y * encoder->frame->linesize[3];
        for (int x = 0; x < width; x++) {
            int red, green, blue, alpha;
            TelegramWebMUnpremultiplyBGRA(sourceRow + (size_t)x * 4, &red, &green, &blue, &alpha);
            lumaRow[x] = TelegramWebMClampByte(((47 * red + 157 * green + 16 * blue + 128) >> 8) + 16);
            alphaRow[x] = (uint8_t)alpha;
        }
    }

    for (int y = 0; y < height; y += 2) {
        uint8_t *chromaBlueRow = encoder->frame->data[1] + (size_t)(y / 2) * encoder->frame->linesize[1];
        uint8_t *chromaRedRow = encoder->frame->data[2] + (size_t)(y / 2) * encoder->frame->linesize[2];
        for (int x = 0; x < width; x += 2) {
            int red = 0;
            int green = 0;
            int blue = 0;
            for (int offsetY = 0; offsetY < 2; offsetY++) {
                const uint8_t *sourceRow = bgra + (size_t)(y + offsetY) * bytesPerRow;
                for (int offsetX = 0; offsetX < 2; offsetX++) {
                    int pixelRed, pixelGreen, pixelBlue, alpha;
                    TelegramWebMUnpremultiplyBGRA(
                        sourceRow + (size_t)(x + offsetX) * 4,
                        &pixelRed,
                        &pixelGreen,
                        &pixelBlue,
                        &alpha
                    );
                    red += pixelRed;
                    green += pixelGreen;
                    blue += pixelBlue;
                }
            }
            red /= 4;
            green /= 4;
            blue /= 4;
            chromaBlueRow[x / 2] = TelegramWebMClampByte(((-26 * red - 87 * green + 112 * blue + 128) >> 8) + 128);
            chromaRedRow[x / 2] = TelegramWebMClampByte(((112 * red - 102 * green - 10 * blue + 128) >> 8) + 128);
        }
    }

    encoder->frame->pts = encoder->frameIndex++;
    if (avcodec_send_frame(encoder->codecContext, encoder->frame) < 0) {
        return false;
    }
    return TelegramWebMWriteAvailablePackets(encoder) >= 0;
}

bool TelegramWebMEncoderFinish(TelegramWebMEncoder *encoder) {
    if (encoder == NULL) {
        return false;
    }
    if (encoder->finished) {
        return true;
    }
    if (avcodec_send_frame(encoder->codecContext, NULL) < 0 ||
        TelegramWebMWriteAvailablePackets(encoder) < 0 ||
        av_write_trailer(encoder->formatContext) < 0) {
        return false;
    }
    encoder->finished = true;
    if (encoder->formatContext->pb != NULL && avio_closep(&encoder->formatContext->pb) < 0) {
        return false;
    }
    return true;
}
