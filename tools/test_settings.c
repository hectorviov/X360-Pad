// Unit tests of Driver/X360Settings.h (the processing the driver applies): clang -I../Driver test_settings.c -o test && ./test
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "X360Settings.h"

static int failed, checks;
#define CHECK(c) do { checks++; if (!(c)) { failed++; printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); } } while (0)

static void report(uint8_t w[20], uint16_t buttons, uint8_t lt, uint8_t rt, int16_t lx, int16_t ly, int16_t rx, int16_t ry) {
    memset(w, 0, 20);
    w[1] = 0x14; w[2] = (uint8_t)buttons; w[3] = (uint8_t)(buttons >> 8); w[4] = lt; w[5] = rt;
    x360_put16(w + 6, lx); x360_put16(w + 8, ly); x360_put16(w + 10, rx); x360_put16(w + 12, ry);
}

int main(void) {
    x360_settings s;
    x360_settings_default(&s);
    uint8_t w[20];

    CHECK(fabsf(x360_sqrtf(2) - 1.41421356f) < 1e-5f && x360_sqrtf(0) == 0 && fabsf(x360_sqrtf(0.25f) - 0.5f) < 1e-6f);

    // drift inside the dead zone reads centred; a full push still reaches full
    report(w, 0, 0, 0, 5000, -4000, 32767, 0);
    x360_apply(&s, w);
    CHECK(x360_le16(w + 6) == 0 && x360_le16(w + 8) == 0);
    CHECK(x360_le16(w + 10) == 32767);
    // just past the dead zone: small, no jump to its edge
    s.stickInner[0] = 0.25f; s.stickOuter[0] = 0.95f;
    report(w, 0, 0, 0, (int16_t)(0.26f * 32767), 0, 0, 0);
    x360_apply(&s, w);
    CHECK(x360_le16(w + 6) > 0 && x360_le16(w + 6) < 600);
    // invert Y
    s.invertY[1] = 1;
    report(w, 0, 0, 0, 0, 0, 0, 30000);
    x360_apply(&s, w);
    CHECK(x360_le16(w + 12) < -20000);

    // triggers: dead zone and click level
    x360_settings_default(&s);
    s.triggerDead = 0.1f; s.triggerClick = 0.5f;
    report(w, 0, 20, 255, 0, 0, 0, 0);
    x360_apply(&s, w);
    CHECK(w[4] == 0 && w[5] == 255);
    CHECK(x360_click_level(&s) > 100 && x360_click_level(&s) < 130);

    // remap: A <-> B, Guide off
    x360_settings_default(&s);
    s.remap[X360B_A] = X360B_B; s.remap[X360B_B] = X360B_A; s.remap[X360B_GUIDE] = X360_REMAP_NONE;
    report(w, (1 << X360B_A) | (1 << X360B_GUIDE) | (1 << X360B_START), 0, 0, 0, 0, 0, 0);
    x360_apply(&s, w);
    uint16_t b = (uint16_t)(w[2] | w[3] << 8);
    CHECK(b == ((1 << X360B_B) | (1 << X360B_START)));

    // motors: floor, gain, swap
    x360_settings_default(&s);
    uint8_t a, c;
    x360_motors(&s, 0, 0, &a, &c); CHECK(a == 0 && c == 0);
    x360_motors(&s, 15, 8, &a, &c); CHECK(a >= 130 && a < 140 && c >= 130 && c < 140);
    x360_motors(&s, 255, 255, &a, &c); CHECK(a == 255 && c == 255);
    s.rumbleGain = 0; x360_motors(&s, 200, 200, &a, &c); CHECK(a == 0 && c == 0);
    s.rumbleGain = 1; s.swapMotors = 1; s.motorFloor = 0; x360_motors(&s, 200, 50, &a, &c); CHECK(a == 50 && c == 200);

    CHECK(sizeof(x360_settings) == 56 && sizeof(x360_state) == 36);
    printf("%d checks, %d failed\n", checks, failed);
    return failed != 0;
}
