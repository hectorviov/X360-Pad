// Diagnostics a driver service publishes on itself (visible with `ioreg -l | grep X360Pad`), since its os_log lines are not always kept: the last
// step it reached (or failed at) and its result.
#pragma once
#include <DriverKit/IOService.h>
#include <DriverKit/OSCollections.h>

static inline void x360_status(IOService * service, const char * step, kern_return_t result) {
    OSDictionary * d = OSDictionary::withCapacity(2);
    if (!d) return;
    OSString * s = OSString::withCString(step);
    OSNumber * n = OSNumber::withNumber((uint64_t)(uint32_t)result, 32);
    if (s) { d->setObject("X360PadStep", s); s->release(); }
    if (n) { d->setObject("X360PadResult", n); n->release(); }
    service->SetProperties(d);
    d->release();
}
