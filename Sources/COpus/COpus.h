#ifndef COpus_h
#define COpus_h

#include <opus.h>

/// Static inline wrapper to set the bitrate of the Opus encoder.
/// This works around Swift's limitation on calling C variadic functions directly.
static inline int flight_opus_encoder_set_bitrate(OpusEncoder *st, opus_int32 bitrate) {
    return opus_encoder_ctl(st, OPUS_SET_BITRATE(bitrate));
}

/// Static inline wrapper to configure VBR (Variable Bit Rate) on the Opus encoder.
/// This works around Swift's limitation on calling C variadic functions directly.
static inline int flight_opus_encoder_set_vbr(OpusEncoder *st, opus_int32 vbr) {
    return opus_encoder_ctl(st, OPUS_SET_VBR(vbr));
}

#endif /* COpus_h */
