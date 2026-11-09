// See X360PadSlot.iig.
#include <os/log.h>
#include <DriverKit/DriverKit.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/OSCollections.h>
#include <USBDriverKit/USBDriverKit.h>
#include "X360PadSlot.h"
#include "X360PadGamepad.h"
#include "X360Wire.h"
#include "X360Status.h"
#include "X360Settings.h"

#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "x360pad: slot %d: " fmt, ivars ? ivars->slot + 1 : 0, ##__VA_ARGS__)

struct X360PadSlot_IVars {
    IOUSBHostInterface * iface;
    IOUSBHostPipe * in;
    IOUSBHostPipe * out;
    IOBufferMemoryDescriptor * inBuf;
    IOBufferMemoryDescriptor * outBuf;   // the command in flight
    OSAction * readAction;
    OSAction * writeAction;
    IOLock * lock;                       // the command queue: the gamepad's queue and this one both send
    bool writing;
    uint8_t pending[3][12];              // rumble, LED, presence query waiting to be sent (latest wins)
    bool hasPending[3];
    IOTimerDispatchSource * holdTimer;   // the motors' minimum time on
    OSAction * holdAction;
    uint64_t holdUntil;                  // mach time before which a stop is deferred
    uint8_t deferredStop[12];
    bool hasDeferredStop;
    X360PadGamepad * pad;
    uint8_t slot;
    bool stopping;
    x360_settings settings;              // the app's (defaults until it sends its own); under the lock
    uint8_t raw[20];                     // the last wire report, before the settings
    uint8_t motors[2];                   // the last levels sent to the motors
    uint32_t reports;
};

bool X360PadSlot::init() {
    if (!super::init()) return false;
    ivars = IONewZero(X360PadSlot_IVars, 1);
    if (!ivars) return false;
    ivars->lock = IOLockAlloc();
    x360_settings_default(&ivars->settings);
    return ivars->lock != nullptr;
}

void X360PadSlot::free() {
    if (ivars) {
        OSSafeReleaseNULL(ivars->readAction);
        OSSafeReleaseNULL(ivars->writeAction);
        OSSafeReleaseNULL(ivars->holdAction);
        OSSafeReleaseNULL(ivars->holdTimer);
        if (ivars->lock) IOLockFree(ivars->lock);
        OSSafeReleaseNULL(ivars->inBuf);
        OSSafeReleaseNULL(ivars->outBuf);
        OSSafeReleaseNULL(ivars->in);
        OSSafeReleaseNULL(ivars->out);
        OSSafeReleaseNULL(ivars->iface);
    }
    IOSafeDeleteNULL(ivars, X360PadSlot_IVars, 1);
    super::free();
}

uint8_t X360PadSlot::SlotNumber() { return ivars->slot; }

static int command_kind(const uint8_t * c) {   // 0 rumble, 1 LED or power off (latest wins), 2 presence query (and anything else)
    if (c[0] == 0x00 && c[1] == 0x01) return 0;
    if (c[0] == 0x00 && c[1] == 0x00 && c[2] == 0x08) return 1;
    return 2;
}

// Starts the next waiting command if none is in flight; called with the lock held. Returns the result of queueing it.
static kern_return_t start_next(X360PadSlot_IVars * ivars) {
    if (ivars->writing || ivars->stopping || !ivars->out) return kIOReturnSuccess;
    for (int k = 0; k < 3; k++) {
        if (!ivars->hasPending[k]) continue;
        ivars->hasPending[k] = false;
        if (k == 0) { ivars->motors[0] = ivars->pending[0][5]; ivars->motors[1] = ivars->pending[0][6]; }   // what the motors get, for the app
        IOAddressSegment range = {};
        ivars->outBuf->GetAddressRange(&range);
        memcpy((void *)range.address, ivars->pending[k], 12);
        ivars->outBuf->SetLength(12);
        kern_return_t ret = ivars->out->AsyncIO(ivars->outBuf, 12, ivars->writeAction, 0);   // interrupt pipes take no completion timeout
        if (ret == kIOReturnSuccess) ivars->writing = true;
        return ret;
    }
    return kIOReturnSuccess;
}

// Games' rumble effects can be a frame or two long, shorter than a 360 controller's motors take to spin up, so once on they stay on at least the
// settings' motorHoldMs before a stop is honoured (mach time is 24 MHz); a new start extends it

kern_return_t X360PadSlot::SendCommand(const uint8_t * command) {
    if (!ivars->out || ivars->stopping) return kIOReturnNotOpen;
    IOLockLock(ivars->lock);
    int k = command_kind(command);
    if (k == 0) {
        uint64_t now = mach_absolute_time();
        bool on = command[5] || command[6];
        if (on) { ivars->holdUntil = now + (uint64_t)ivars->settings.motorHoldMs * 24000ull; ivars->hasDeferredStop = false; }
        else if (now < ivars->holdUntil && ivars->holdTimer) {   // stop later, when the hold ends
            memcpy(ivars->deferredStop, command, 12);
            ivars->hasDeferredStop = true;
            uint64_t until = ivars->holdUntil;
            IOLockUnlock(ivars->lock);
            ivars->holdTimer->WakeAtTime(kIOTimerClockMachAbsoluteTime, until, 0);
            return kIOReturnSuccess;
        }
    }
    memcpy(ivars->pending[k], command, 12);
    ivars->hasPending[k] = true;
    kern_return_t ret = start_next(ivars);
    IOLockUnlock(ivars->lock);
    if (ret != kIOReturnSuccess) { x360_status(this, "command", ret); LOG("command not queued (0x%x)", ret); }
    return ret;
}

void IMPL(X360PadSlot, HoldEnded) {
    (void)action; (void)time;
    IOLockLock(ivars->lock);
    kern_return_t ret = kIOReturnSuccess;
    if (ivars->hasDeferredStop) {
        uint64_t now = mach_absolute_time();
        if (now + 24000 >= ivars->holdUntil) {   // the hold is over (a new start would have cleared the deferred stop)
            memcpy(ivars->pending[0], ivars->deferredStop, 12);
            ivars->hasPending[0] = true;
            ivars->hasDeferredStop = false;
            ret = start_next(ivars);
        }
    }
    uint64_t until = ivars->hasDeferredStop ? ivars->holdUntil : 0;
    IOLockUnlock(ivars->lock);
    if (until && ivars->holdTimer) ivars->holdTimer->WakeAtTime(kIOTimerClockMachAbsoluteTime, until, 0);
    if (ret != kIOReturnSuccess) LOG("command not queued (0x%x)", ret);
}

void IMPL(X360PadSlot, WriteComplete) {
    (void)action; (void)completionTimestamp; (void)actualByteCount;
    if (status != kIOReturnSuccess && status != kIOReturnAborted) x360_status(this, "command", status);
    IOLockLock(ivars->lock);
    ivars->writing = false;
    kern_return_t ret = status == kIOReturnAborted ? kIOReturnSuccess : start_next(ivars);
    IOLockUnlock(ivars->lock);
    if (ret != kIOReturnSuccess) LOG("command not queued (0x%x)", ret);
}

kern_return_t X360PadSlot::Rumble(uint8_t strong, uint8_t weak) {
    IOLockLock(ivars->lock);
    uint8_t a = 0, b = 0;
    x360_motors(&ivars->settings, strong, weak, &a, &b);
    IOLockUnlock(ivars->lock);
    uint8_t cmd[12];
    x360w_rumble(cmd, a, b);
    return SendCommand(cmd);
}

void X360PadSlot::SetSettings(const void * settings) {
    IOLockLock(ivars->lock);
    memcpy(&ivars->settings, settings, sizeof ivars->settings);
    IOLockUnlock(ivars->lock);
}

void X360PadSlot::GetState(void * state) {
    x360_state * st = (x360_state *)state;
    memset(st, 0, sizeof *st);
    IOLockLock(ivars->lock);
    st->connected = ivars->pad != nullptr;
    st->slot = ivars->slot;
    memcpy(st->raw, ivars->raw, sizeof st->raw);
    st->motors[0] = ivars->motors[0]; st->motors[1] = ivars->motors[1];
    st->reports = ivars->reports;
    IOLockUnlock(ivars->lock);
}

kern_return_t X360PadSlot::TestRumble(uint8_t strong, uint8_t weak, uint32_t ms) {
    if (!ivars->holdTimer) return kIOReturnNotReady;
    uint8_t cmd[12];
    x360w_rumble(cmd, strong, weak);
    kern_return_t ret = SendCommand(cmd);
    if (ret != kIOReturnSuccess) return ret;
    IOLockLock(ivars->lock);   // the stop, after ms: through the motors' hold
    uint64_t until = mach_absolute_time() + (uint64_t)ms * 24000ull;
    if (until > ivars->holdUntil) ivars->holdUntil = until;
    x360w_rumble(ivars->deferredStop, 0, 0);
    ivars->hasDeferredStop = true;
    until = ivars->holdUntil;
    IOLockUnlock(ivars->lock);
    return ivars->holdTimer->WakeAtTime(kIOTimerClockMachAbsoluteTime, until, 0);
}

kern_return_t IMPL(X360PadSlot, NewUserClient) {
    (void)type;
    IOService * client = nullptr;
    kern_return_t ret = Create(this, "UserClientProperties", &client);
    if (ret != kIOReturnSuccess || !client) return ret ? ret : kIOReturnNoMemory;
    *userClient = OSDynamicCast(IOUserClient, client);
    if (!*userClient) { client->release(); return kIOReturnUnsupported; }
    return kIOReturnSuccess;
}

static void publish(X360PadSlot * self, X360PadSlot_IVars * ivars) {
    if (ivars->pad) return;
    IOService * child = nullptr;
    kern_return_t ret = self->Create(self, "X360PadGamepadProperties", &child);
    if (ret != kIOReturnSuccess || !child) { x360_status(self, "gamepad create", ret); LOG("gamepad not created (0x%x)", ret); return; }
    ivars->pad = OSDynamicCast(X360PadGamepad, child);
    if (!ivars->pad) { LOG("created service is not the gamepad"); child->Terminate(0); child->release(); return; }
    uint8_t cmd[12];
    x360w_led(cmd, ivars->slot);
    self->SendCommand(cmd);
    x360_status(self, "controller on", 0);
    LOG("controller on: gamepad published");
}

static void unpublish(X360PadSlot * self, X360PadSlot_IVars * ivars) {
    if (!ivars->pad) return;
    ivars->pad->Terminate(0);
    OSSafeReleaseNULL(ivars->pad);
    IOLockLock(ivars->lock);
    memset(ivars->raw, 0, sizeof ivars->raw);
    IOLockUnlock(ivars->lock);
    x360_status(self, "controller off", 0);
    LOG("controller off: gamepad removed");
    (void)self;
}

// A failing step is published on the service (X360PadStep / X360PadResult, see X360Status.h) and the service stays registered, so `ioreg -l`
// shows what went wrong: the driver's os_log lines are not always kept.
#define FAIL(step, r) do { x360_status(this, step, r); LOG(step " failed (0x%x)", r); RegisterService(); return kIOReturnSuccess; } while (0)

kern_return_t IMPL(X360PadSlot, Start) {
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;
    x360_status(this, "started", 0);

    ivars->iface = OSDynamicCast(IOUSBHostInterface, provider);
    if (!ivars->iface) FAIL("provider", kIOReturnNoDevice);
    ivars->iface->retain();
    ret = ivars->iface->Open(this, 0, nullptr);
    if (ret != kIOReturnSuccess) FAIL("open", ret);

    const IOUSBConfigurationDescriptor * cfg = ivars->iface->CopyConfigurationDescriptor();
    const IOUSBInterfaceDescriptor * ifd = cfg ? ivars->iface->GetInterfaceDescriptor(cfg) : nullptr;
    if (!ifd) { if (cfg) IOFree((void *)cfg, USBToHost16(cfg->wTotalLength)); FAIL("descriptors", kIOReturnNoDevice); }
    ivars->slot = (uint8_t)((ifd->bInterfaceNumber / 2) & 3);   // interfaces 0, 2, 4, 6 are slots 1..4 (the odd ones: headsets)
    const IOUSBDescriptorHeader * cur = (const IOUSBDescriptorHeader *)ifd;
    const IOUSBEndpointDescriptor * ep;
    while ((ep = IOUSBGetNextEndpointDescriptor(cfg, ifd, cur))) {
        cur = (const IOUSBDescriptorHeader *)ep;
        if ((ep->bmAttributes & 3) != 3) continue;   // interrupt endpoints only
        IOUSBHostPipe * pipe = nullptr;
        if (ivars->iface->CopyPipe(ep->bEndpointAddress, &pipe) != kIOReturnSuccess) continue;
        if (ep->bEndpointAddress & 0x80) { OSSafeReleaseNULL(ivars->in); ivars->in = pipe; }
        else { OSSafeReleaseNULL(ivars->out); ivars->out = pipe; }
    }
    IOFree((void *)cfg, USBToHost16(cfg->wTotalLength));
    if (!ivars->in || !ivars->out) FAIL("pipes", kIOReturnNoResources);

    ret = ivars->iface->CreateIOBuffer(kIOMemoryDirectionIn, 32, &ivars->inBuf);
    if (ret == kIOReturnSuccess) ret = ivars->iface->CreateIOBuffer(kIOMemoryDirectionInOut, 12, &ivars->outBuf);
    if (ret == kIOReturnSuccess) ret = CreateActionReadComplete(0, &ivars->readAction);
    if (ret == kIOReturnSuccess) ret = CreateActionWriteComplete(0, &ivars->writeAction);
    if (ret == kIOReturnSuccess) {   // the motors' hold timer, on this service's queue
        IODispatchQueue * queue = nullptr;
        ret = CopyDispatchQueue(kIOServiceDefaultQueueName, &queue);
        if (ret == kIOReturnSuccess) ret = IOTimerDispatchSource::Create(queue, &ivars->holdTimer);
        if (ret == kIOReturnSuccess) ret = CreateActionHoldEnded(0, &ivars->holdAction);
        if (ret == kIOReturnSuccess) ret = ivars->holdTimer->SetHandler(ivars->holdAction);
        if (ret == kIOReturnSuccess) ret = ivars->holdTimer->SetEnable(true);
        OSSafeReleaseNULL(queue);
    }
    if (ret != kIOReturnSuccess) FAIL("buffers", ret);

    ret = ivars->in->AsyncIO(ivars->inBuf, 32, ivars->readAction, 0);
    if (ret != kIOReturnSuccess) FAIL("read", ret);
    uint8_t cmd[12];
    x360w_presence_query(cmd);   // the receiver answers with presence reports
    SendCommand(cmd);
    LOG("started");
    x360_status(this, "reading", 0);
    if (OSDictionary * d = OSDictionary::withCapacity(1)) {   // for the app, which finds the slots by it
        if (OSNumber * n = OSNumber::withNumber((uint64_t)ivars->slot, 32)) { d->setObject("X360PadSlotNumber", n); n->release(); }
        SetProperties(d); d->release();
    }
    return RegisterService();
}

void IMPL(X360PadSlot, ReadComplete) {
    if (status != kIOReturnSuccess) {
        if (status != kIOReturnAborted) { x360_status(this, "read error", status); LOG("read stopped (0x%x)", status); }
        if (status == kIOReturnAborted || ivars->stopping) return;
    } else {
        IOAddressSegment range = {};
        ivars->inBuf->GetAddressRange(&range);
        const uint8_t * report = nullptr;
        int r = x360w_parse((const uint8_t *)range.address, actualByteCount, &report);
        if (r & X360W_ABSENT) unpublish(this, ivars);
        if (r & (X360W_PRESENT | X360W_INPUT)) publish(this, ivars);   // input proves presence too (a missed presence report)
        if (r & X360W_INPUT) {
            uint8_t w[X360_REPORT_LEN];
            memcpy(w, report, sizeof w);
            IOLockLock(ivars->lock);
            memcpy(ivars->raw, report, sizeof ivars->raw);
            ivars->reports++;
            x360_apply(&ivars->settings, w);
            uint8_t click = x360_click_level(&ivars->settings);
            IOLockUnlock(ivars->lock);
            if (ivars->pad) ivars->pad->PostInput(w, X360_REPORT_LEN, click);
        }
    }
    if (!ivars->stopping) {
        kern_return_t ret = ivars->in->AsyncIO(ivars->inBuf, 32, ivars->readAction, 0);
        if (ret != kIOReturnSuccess) LOG("read not requeued (0x%x)", ret);
    }
}

kern_return_t IMPL(X360PadSlot, Stop) {
    ivars->stopping = true;
    if (ivars->holdTimer) ivars->holdTimer->Cancel(nullptr);
    unpublish(this, ivars);
    if (ivars->in) ivars->in->Abort(kIOUSBAbortAsynchronous, kIOReturnAborted, nullptr);
    if (ivars->out) ivars->out->Abort(kIOUSBAbortAsynchronous, kIOReturnAborted, nullptr);
    if (ivars->iface) ivars->iface->Close(this, 0);
    LOG("stopped");
    return Stop(provider, SUPERDISPATCH);
}
