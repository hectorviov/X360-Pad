// See X360PadDevice.iig.
#include <os/log.h>
#include <DriverKit/DriverKit.h>
#include <USBDriverKit/USBDriverKit.h>
#include "X360PadDevice.h"
#include "X360Status.h"

kern_return_t IMPL(X360PadDevice, Start) {
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;
    IOUSBHostDevice * device = OSDynamicCast(IOUSBHostDevice, provider);
    if (!device) return kIOReturnNoDevice;
    ret = device->Open(this, 0, 0);
    if (ret != kIOReturnSuccess) { x360_status(this, "open", ret); os_log(OS_LOG_DEFAULT, "x360pad: receiver not opened (0x%x)", ret); RegisterService(); return kIOReturnSuccess; }
    ret = device->SetConfiguration(1, true);   // its only configuration; the interfaces then match the slot driver
    os_log(OS_LOG_DEFAULT, "x360pad: receiver configured (0x%x)", ret);
    device->Close(this, 0);
    x360_status(this, "configured", ret);
    return RegisterService();
}
