// See X360PadGamepad.iig.
#include <os/log.h>
#include <DriverKit/DriverKit.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/OSCollections.h>
#include <HIDDriverKit/HIDDriverKit.h>
#include "X360PadGamepad.h"
#include "X360PadSlot.h"
#include "X360Wire.h"
#include "DualShock4Wire.h"

struct X360PadGamepad_IVars {
    X360PadSlot * slot;
    IOBufferMemoryDescriptor * report;
    uint8_t number;
    uint8_t sequence;
};

bool X360PadGamepad::init() {
    if (!super::init()) return false;
    ivars = IONewZero(X360PadGamepad_IVars, 1);
    return ivars != nullptr;
}

void X360PadGamepad::free() {
    if (ivars) OSSafeReleaseNULL(ivars->report);
    IOSafeDeleteNULL(ivars, X360PadGamepad_IVars, 1);
    super::free();
}

kern_return_t IMPL(X360PadGamepad, Start) {
    // The provider is the slot; its number goes into the description, which the superclass asks for as it starts
    ivars->slot = OSDynamicCast(X360PadSlot, provider);
    if (!ivars->slot) return kIOReturnNoDevice;
    ivars->number = ivars->slot->SlotNumber();
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) { os_log(OS_LOG_DEFAULT, "x360pad: gamepad did not start (0x%x)", ret); return ret; }
    return RegisterService();
}

bool X360PadGamepad::handleStart(IOService * provider) {
    if (!super::handleStart(provider)) return false;
    return IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut, DS4_INPUT_LEN, 0, &ivars->report) == kIOReturnSuccess;
}

static void setNumber(OSDictionary * d, const char * key, uint32_t v) {
    OSNumber * n = OSNumber::withNumber(v, 32);
    if (n) { d->setObject(key, n); n->release(); }
}
static void setString(OSDictionary * d, const char * key, const char * v) {
    OSString * s = OSString::withCString(v);
    if (s) { d->setObject(key, s); s->release(); }
}

OSDictionary * X360PadGamepad::newDeviceDescription() {
    OSDictionary * d = OSDictionary::withCapacity(12);
    if (!d) return nullptr;
    setNumber(d, kIOHIDVendorIDKey, DS4_VENDOR);
    setNumber(d, kIOHIDProductIDKey, DS4_PRODUCT);
    setNumber(d, kIOHIDVersionNumberKey, 0x0100);
    setString(d, kIOHIDTransportKey, "USB");
    setString(d, kIOHIDManufacturerKey, "Sony Interactive Entertainment");
    setString(d, kIOHIDProductKey, "Wireless Controller");
    char serial[] = "x360pad-0";
    serial[sizeof serial - 2] = (char)('1' + (ivars->number & 3));
    setString(d, kIOHIDSerialNumberKey, serial);
    setNumber(d, kIOHIDLocationIDKey, 0x03600000 + ivars->number);
    setNumber(d, kIOHIDPrimaryUsagePageKey, 0x01);
    setNumber(d, kIOHIDPrimaryUsageKey, 0x05);
    setNumber(d, kIOHIDReportIntervalKey, 8000);   // µs: the receiver's 8 ms polling
    return d;
}

OSData * X360PadGamepad::newReportDescriptor() {
    return OSData::withBytes(ds4_descriptor, sizeof ds4_descriptor);
}

kern_return_t X360PadGamepad::PostInput(const uint8_t * report, uint32_t length, uint8_t clickLevel) {
    if (!ivars->report || length != X360_REPORT_LEN) return kIOReturnBadArgument;
    IOAddressSegment range = {};
    ivars->report->GetAddressRange(&range);
    uint64_t now = mach_absolute_time();
    uint16_t ts = (uint16_t)(now / 128);   // DualShock 4 timestamps count 5.33 µs: 128 ticks of the 24 MHz timebase
    ds4_from_x360((uint8_t *)range.address, report, ivars->sequence++, ts, clickLevel);
    ivars->report->SetLength(DS4_INPUT_LEN);
    return handleReport(now, ivars->report, DS4_INPUT_LEN, kIOHIDReportTypeInput, 0);
}

// Feature reports a host reads from a DualShock 4 (0x02 calibration, 0x12 / 0x81 its MAC address, 0xa3 firmware): the descriptor's size, the
// report ID first. Calibration is neutral (zero bias, the ranges a DualShock 4 reports); the controller has no motion sensors.
kern_return_t X360PadGamepad::getReport(IOMemoryDescriptor * report, IOHIDReportType reportType, IOOptionBits options, uint32_t completionTimeout,
                                        OSAction * action) {
    (void)completionTimeout;
    uint8_t id = (uint8_t)(options & 0xff);
    uint32_t n = id == 0x02 ? 37 : id == 0x12 ? 16 : id == 0x81 ? 7 : id == 0xa3 ? 49 : 0;
    IOMemoryMap * map = nullptr;
    if (reportType != kIOHIDReportTypeFeature || !n || report->CreateMapping(0, 0, 0, 0, 0, &map) != kIOReturnSuccess || !map || map->GetLength() < n) {
        OSSafeReleaseNULL(map);
        if (action) CompleteReport(action, kIOReturnUnsupported, 0);
        return kIOReturnUnsupported;
    }
    uint8_t * b = (uint8_t *)map->GetAddress();
    for (uint32_t i = 0; i < n; i++) b[i] = 0;
    b[0] = id;
    if (id == 0x02) {   // USB order: biases, then plus/minus per axis, the speeds, then the accelerometer's plus/minus per axis
        int16_t v[17] = {0, 0, 0, 8192, -8192, 8192, -8192, 8192, -8192, 540, 540, 8192, -8192, 8192, -8192, 8192, -8192};
        for (int i = 0; i < 17; i++) { b[1 + 2 * i] = (uint8_t)v[i]; b[2 + 2 * i] = (uint8_t)((uint16_t)v[i] >> 8); }
    } else if (id == 0x12 || id == 0x81) {   // a made-up MAC address, one per slot
        b[1] = (uint8_t)(0x60 + ivars->number); b[2] = 0x55; b[3] = 0x44; b[4] = 0x33; b[5] = 0x22; b[6] = 0x11;
    }
    map->release();
    if (action) CompleteReport(action, kIOReturnSuccess, n);   // a caller waiting on an asynchronous request is told it finished
    return kIOReturnSuccess;
}

// Output report 0x05 (rumble and the light bar): the motors go to the slot, which applies the app's gain, swap and floor
kern_return_t X360PadGamepad::setReport(IOMemoryDescriptor * report, IOHIDReportType reportType, IOOptionBits options, uint32_t completionTimeout,
                                        OSAction * action) {
    (void)completionTimeout; (void)options;
    IOMemoryMap * map = nullptr;
    if (report->CreateMapping(0, 0, 0, 0, 0, &map) != kIOReturnSuccess || !map) {
        if (action) CompleteReport(action, kIOReturnNoMemory, 0);
        return kIOReturnNoMemory;
    }
    const uint8_t * b = (const uint8_t *)map->GetAddress();
    uint64_t n = map->GetLength();
    uint8_t strong = 0, weak = 0;
    if (reportType == kIOHIDReportTypeOutput && ds4_rumble(b, n, &strong, &weak) && ivars->slot) ivars->slot->Rumble(strong, weak);
    map->release();
    if (action) CompleteReport(action, kIOReturnSuccess, (uint32_t)n);
    return kIOReturnSuccess;
}
