// See X360PadUserClient.iig.
#include <os/log.h>
#include <DriverKit/DriverKit.h>
#include <DriverKit/OSCollections.h>
#include "X360PadUserClient.h"
#include "X360PadSlot.h"
#include "X360Settings.h"
#include "X360Wire.h"

struct X360PadUserClient_IVars {
    X360PadSlot * slot;
};

bool X360PadUserClient::init() {
    if (!super::init()) return false;
    ivars = IONewZero(X360PadUserClient_IVars, 1);
    return ivars != nullptr;
}

void X360PadUserClient::free() {
    if (ivars) OSSafeReleaseNULL(ivars->slot);
    IOSafeDeleteNULL(ivars, X360PadUserClient_IVars, 1);
    super::free();
}

kern_return_t IMPL(X360PadUserClient, Start) {
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;
    ivars->slot = OSDynamicCast(X360PadSlot, provider);
    if (!ivars->slot) return kIOReturnNoDevice;
    ivars->slot->retain();
    return kIOReturnSuccess;
}

kern_return_t IMPL(X360PadUserClient, Stop) {
    return Stop(provider, SUPERDISPATCH);
}

kern_return_t X360PadUserClient::ExternalMethod(uint64_t selector, IOUserClientMethodArguments * a, const IOUserClientMethodDispatch * dispatch,
                                                OSObject * target, void * reference) {
    (void)dispatch; (void)target; (void)reference;
    if (!ivars->slot) return kIOReturnNotAttached;
    switch (selector) {
    case X360_UC_SET_SETTINGS: {
        if (!a->structureInput || a->structureInput->getLength() != sizeof(x360_settings)) return kIOReturnBadArgument;
        const x360_settings * s = (const x360_settings *)a->structureInput->getBytesNoCopy();
        if (!x360_settings_valid(s)) return kIOReturnUnsupported;
        ivars->slot->SetSettings(s);
        return kIOReturnSuccess;
    }
    case X360_UC_GET_STATE: {
        x360_state st;
        ivars->slot->GetState(&st);
        a->structureOutput = OSData::withBytes(&st, sizeof st);
        return a->structureOutput ? kIOReturnSuccess : kIOReturnNoMemory;
    }
    case X360_UC_TEST_RUMBLE: {
        if (a->scalarInputCount < 3) return kIOReturnBadArgument;
        uint64_t ms = a->scalarInput[2] > 3000 ? 3000 : a->scalarInput[2];
        return ivars->slot->TestRumble((uint8_t)a->scalarInput[0], (uint8_t)a->scalarInput[1], (uint32_t)ms);
    }
    case X360_UC_POWER_OFF: {
        uint8_t cmd[12];
        x360w_power_off(cmd);
        return ivars->slot->SendCommand(cmd);
    }
    default:
        return kIOReturnUnsupported;
    }
}
