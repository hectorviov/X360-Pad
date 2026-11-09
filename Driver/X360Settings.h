// A controller slot's settings and how they change its state, in plain C: the driver applies them to every report (so they hold in every game,
// with or without the app running) and the app's window draws with the same functions. The app sends them to the driver through
// X360PadUserClient (selector X360_UC_SET_SETTINGS). Defaults are what the driver uses until the app sends its own.
#pragma once
#include <stdint.h>

#define X360_SETTINGS_VERSION 1

typedef struct {
    uint32_t version;            // X360_SETTINGS_VERSION
    float stickInner[2];         // left, right: deflection (of full) below which the stick reads centred, the cure for drift
    float stickOuter[2];         // deflection past which it reads fully deflected
    uint8_t invertY[2];
    uint8_t swapMotors;
    uint8_t motorFloor;          // 0..254: a requested motor level 1..255 is spread over floor..255 (a 360's motors do not turn below ~130)
    float triggerDead;           // travel (of full) below which a trigger reads released
    float triggerClick;          // travel past which it also presses its digital button
    float rumbleGain;            // 0 silent .. 2
    uint16_t motorHoldMs;        // once on, the motors stay on at least this long (games' effects can be shorter than the motors' spin-up)
    uint16_t reserved;
    uint8_t remap[16];           // wire button bit (x360_button) -> the bit it presses instead, X360_REMAP_NONE for nothing
} x360_settings;

#define X360_REMAP_NONE 0xFF

// The wire report's button bits (bytes 2 and 3 as one little-endian 16-bit field)
enum {
    X360B_UP, X360B_DOWN, X360B_LEFT, X360B_RIGHT, X360B_START, X360B_BACK, X360B_L3, X360B_R3,
    X360B_LB, X360B_RB, X360B_GUIDE, X360B_UNUSED, X360B_A, X360B_B, X360B_X, X360B_Y,
};

static inline void x360_settings_default(x360_settings *s) {
    s->version = X360_SETTINGS_VERSION;
    s->stickInner[0] = 7849.0f / 32767.0f; s->stickInner[1] = 8689.0f / 32767.0f;   // XInput's own dead zones for this controller
    s->stickOuter[0] = s->stickOuter[1] = 0.98f;
    s->invertY[0] = s->invertY[1] = 0;
    s->swapMotors = 0;
    s->motorFloor = 130;
    s->triggerDead = 0.03f; s->triggerClick = 0.12f;
    s->rumbleGain = 1;
    s->motorHoldMs = 200;
    s->reserved = 0;
    for (int i = 0; i < 16; i++) s->remap[i] = (uint8_t)i;
}

static inline int x360_settings_valid(const x360_settings *s) { return s->version == X360_SETTINGS_VERSION; }

static inline float x360_clampf(float v, float lo, float hi) { return v < lo ? lo : v > hi ? hi : v; }
static inline float x360_sqrtf(float x) {   // DriverKit has no libm
    if (x <= 0) return 0;
    float r = x > 1 ? x : 1;
    for (int i = 0; i < 20; i++) r = 0.5f * (r + x / r);
    return r;
}
static inline int16_t x360_le16(const uint8_t *p) { return (int16_t)(p[0] | p[1] << 8); }
static inline void x360_put16(uint8_t *p, int16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)((uint16_t)v >> 8); }

/// One stick (x, y in -1..1, y up): a round dead zone, rescaled from its edge to the full-deflection point, capped at 1 in the same direction.
static inline void x360_stick(float *x, float *y, float inner, float outer, int invertY) {
    float r = x360_sqrtf(*x * *x + *y * *y);
    inner = x360_clampf(inner, 0, 0.95f);
    outer = x360_clampf(outer, inner + 0.01f, 1);
    if (r <= inner) { *x = *y = 0; return; }
    float scaled = (r - inner) / (outer - inner);
    if (scaled > 1) scaled = 1;
    float k = scaled / r;
    *x = x360_clampf(*x * k, -1, 1); *y = x360_clampf(*y * k, -1, 1);
    if (invertY) *y = -*y;
}

/// The settings applied to a 20-byte wire report (X360Wire.h), in place: sticks, triggers, buttons.
static inline void x360_apply(const x360_settings *s, uint8_t w[20]) {
    for (int k = 0; k < 2; k++) {
        uint8_t *p = w + 6 + 4 * k;
        float x = x360_le16(p) / 32767.0f, y = x360_le16(p + 2) / 32767.0f;
        if (x < -1) x = -1;
        if (y < -1) y = -1;
        x360_stick(&x, &y, s->stickInner[k], s->stickOuter[k], s->invertY[k]);
        x360_put16(p, (int16_t)(x * 32767.0f)); x360_put16(p + 2, (int16_t)(y * 32767.0f));
    }
    float dz = x360_clampf(s->triggerDead, 0, 0.9f);
    for (int k = 0; k < 2; k++) {
        float f = w[4 + k] / 255.0f;
        f = f <= dz ? 0 : (f - dz) / (1 - dz);
        w[4 + k] = (uint8_t)(f * 255.0f + 0.5f);
    }
    uint16_t in = (uint16_t)(w[2] | w[3] << 8), out = 0;
    for (int b = 0; b < 16; b++) {
        if (!(in >> b & 1)) continue;
        uint8_t t = s->remap[b];
        if (t < 16) out |= (uint16_t)(1u << t);
    }
    w[2] = (uint8_t)out; w[3] = (uint8_t)(out >> 8);
}

/// The trigger travel (0..255 after x360_apply) past which a trigger also reports its digital button
static inline uint8_t x360_click_level(const x360_settings *s) {
    float dz = x360_clampf(s->triggerDead, 0, 0.9f), c = x360_clampf(s->triggerClick, dz, 1);
    float f = (c - dz) / (1 - dz);
    return (uint8_t)(f * 255.0f + 0.5f);
}

/// A game's motor request after the gain, swap and floor: what goes to the receiver.
static inline void x360_motors(const x360_settings *s, uint8_t strong, uint8_t weak, uint8_t *outStrong, uint8_t *outWeak) {
    float g = x360_clampf(s->rumbleGain, 0, 2);
    int a = (int)(strong * g + 0.5f), b = (int)(weak * g + 0.5f);
    if (a > 255) a = 255;
    if (b > 255) b = 255;
    if (s->swapMotors) { int t = a; a = b; b = t; }
    int f = s->motorFloor > 254 ? 254 : s->motorFloor;
    *outStrong = (uint8_t)(a ? f + (a * (255 - f) + 127) / 255 : 0);
    *outWeak = (uint8_t)(b ? f + (b * (255 - f) + 127) / 255 : 0);
}

// The user client's selectors (X360PadUserClient)
enum {
    X360_UC_SET_SETTINGS = 0,    // struct in: x360_settings
    X360_UC_GET_STATE = 1,       // struct out: x360_state
    X360_UC_TEST_RUMBLE = 2,     // scalars in: strong, weak (0..255, the gain and floor not applied), milliseconds
    X360_UC_POWER_OFF = 3,       // turns the slot's controller off
};

typedef struct {
    uint32_t connected;          // a controller is on in this slot
    uint32_t slot;               // 0..3
    uint8_t raw[20];             // its last wire report, before the settings
    uint8_t motors[2];           // what was last sent to its motors (strong, weak)
    uint8_t reserved[2];
    uint32_t reports;            // input reports so far
} x360_state;
