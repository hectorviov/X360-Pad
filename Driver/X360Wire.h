// The receiver's wire format, in plain C for the driver (C++) and the app.
//
// Receiver (Linux xpad.c's facts): each controller slot is a vendor interface (FF/5D/81) with an interrupt IN and OUT endpoint. IN: byte 0 bit 3 is a
// presence report, byte 1 bit 7 the controller present (bit 6 a headset); byte 1 == 0x01 with byte 4 == 0x00 is an input report whose bytes 4..23 are
// exactly the wired controller's 20-byte report. OUT: 12-byte commands.
// The wired report: 0 type, 1 length (0x14), 2 / 3 the buttons (X360Settings.h's bits), 4 / 5 the triggers, 6..13 the sticks (signed 16-bit, y up),
// 14..19 padding.
#pragma once
#include <stdint.h>

#define X360_VENDOR 0x045e
#define X360_REPORT_LEN 20

enum { X360W_NONE = 0, X360W_PRESENT = 1, X360W_ABSENT = 2, X360W_INPUT = 4, X360W_HEADSET = 8 };

/// What one IN transfer says; on X360W_INPUT the 20-byte wired report is at *report.
static inline int x360w_parse(const uint8_t *d, uint32_t n, const uint8_t **report) {
    int r = X360W_NONE;
    if (n >= 2 && (d[0] & 0x08)) r |= (d[1] & 0x80) ? (X360W_PRESENT | ((d[1] & 0x40) ? X360W_HEADSET : 0)) : X360W_ABSENT;
    if (n >= 4 + X360_REPORT_LEN && d[1] == 0x01 && d[4] == 0x00) { *report = d + 4; r |= X360W_INPUT; }
    return r;
}

static inline void x360w_led(uint8_t cmd[12], int slot) {   // slot 0..3 lights its quadrant, -1 off
    for (int i = 0; i < 12; i++) cmd[i] = 0;
    cmd[2] = 0x08; cmd[3] = (uint8_t)(0x40 + (slot >= 0 ? 6 + (slot & 3) : 0));
}
static inline void x360w_presence_query(uint8_t cmd[12]) {
    for (int i = 0; i < 12; i++) cmd[i] = 0;
    cmd[0] = 0x08; cmd[2] = 0x0f; cmd[3] = 0xc0;
}
static inline void x360w_power_off(uint8_t cmd[12]) {   // turns the slot's controller off, as the console's Guide menu does
    for (int i = 0; i < 12; i++) cmd[i] = 0;
    cmd[2] = 0x08; cmd[3] = 0xc0;
}
static inline void x360w_rumble(uint8_t cmd[12], uint8_t strong, uint8_t weak) {
    for (int i = 0; i < 12; i++) cmd[i] = 0;
    cmd[1] = 0x01; cmd[2] = 0x0f; cmd[3] = 0xc0; cmd[5] = strong; cmd[6] = weak;
}
