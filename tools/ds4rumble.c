// Writes DualShock 4 rumble (output report 0x05) straight to the driver's gamepad (054c:09cc): strong/weak for the given milliseconds, then off.
// Usage: ds4rumble [strong 0-255] [weak 0-255] [ms]
#include <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static IOReturn send(IOHIDDeviceRef d, uint8_t strong, uint8_t weak) {
    uint8_t r[32] = {0x05, 0x01, 0x04, 0x00, weak, strong};   // flags: motors; byte 4 right (weak), 5 left (strong)
    return IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0x05, r, sizeof r);
}

int main(int argc, char **argv) {
    int strong = argc > 1 ? atoi(argv[1]) : 255, weak = argc > 2 ? atoi(argv[2]) : 255, ms = argc > 3 ? atoi(argv[3]) : 1000;
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, 0);
    int vid = 0x054c, pid = 0x09cc;
    CFNumberRef v = CFNumberCreate(0, kCFNumberIntType, &vid), p = CFNumberCreate(0, kCFNumberIntType, &pid);
    const void *keys[] = {CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey)}, *vals[] = {v, p};
    CFDictionaryRef match = CFDictionaryCreate(0, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(m, match);
    IOHIDManagerOpen(m, 0);
    CFSetRef set = IOHIDManagerCopyDevices(m);
    if (!set || !CFSetGetCount(set)) { fprintf(stderr, "no DualShock 4 gamepad (054c:09cc)\n"); return 1; }
    IOHIDDeviceRef devs[8]; CFIndex n = CFSetGetCount(set) < 8 ? CFSetGetCount(set) : 8;
    CFSetGetValues(set, (const void **)devs);
    IOHIDDeviceRef d = devs[0];
    IOReturn o = IOHIDDeviceOpen(d, 0);
    printf("%ld device(s); open 0x%x\n", (long)n, o);
    printf("on  %d/%d: 0x%x\n", strong, weak, send(d, (uint8_t)strong, (uint8_t)weak));
    usleep(ms * 1000);
    printf("off: 0x%x\n", send(d, 0, 0));
    return 0;
}
