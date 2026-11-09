// See X360Driver.h.
#import "X360Driver.h"
#import <IOKit/IOKitLib.h>
#import <os/lock.h>
#import <os/log.h>
#include "../../Driver/X360Settings.h"

@implementation X360Driver {
    io_connect_t _conn[4];               // written on the main queue, read under _lock
    io_object_t _notice[4];
    os_unfair_lock _lock;
    dispatch_queue_t _queue[4];          // each slot's calls, in order
    uint64_t _busySince[4];              // mach time a call started, 0 none (under _lock)
    IONotificationPortRef _port;
    io_iterator_t _iter;
}

static __weak X360Driver *gDriver;   // the one instance (the slots' termination notices carry only their slot number)

static void slotGone(void *ctx, io_service_t svc, natural_t type, void *arg) {
    (void)svc; (void)arg;
    if (type != kIOMessageServiceIsTerminated) return;
    X360Driver *self = gDriver;
    NSInteger i = (NSInteger)(intptr_t)ctx - 1;
    if (!self || i < 0 || i > 3) return;
    [self closeSlot:i];
    if (self->_notice[i]) { IOObjectRelease(self->_notice[i]); self->_notice[i] = 0; }
    [self.delegate x360DriverSlotGone:i];
}

static void matched(void *ctx, io_iterator_t it) {
    X360Driver *self = (__bridge X360Driver *)ctx;
    io_service_t svc;
    while ((svc = IOIteratorNext(it))) { [self open:svc]; IOObjectRelease(svc); }
}

- (void)open:(io_service_t)svc {
    CFTypeRef p = IORegistryEntryCreateCFProperty(svc, CFSTR("X360PadSlotNumber"), kCFAllocatorDefault, 0);
    NSInteger slot = p ? [(__bridge NSNumber *)p integerValue] : -1;
    if (p) CFRelease(p);
    if (slot < 0 || slot > 3) return;   // not started yet (its slot number comes with its start)
    [self closeSlot:slot];
    io_connect_t c = 0;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &c);
    if (kr != KERN_SUCCESS) { [self.delegate x360DriverOpenFailed:slot result:kr]; return; }
    // a fresh queue for the new connection: one stuck in a call to a driver that stopped answering is left behind
    dispatch_queue_t q = dispatch_queue_create([NSString stringWithFormat:@"x360pad.slot%ld", (long)slot + 1].UTF8String, DISPATCH_QUEUE_SERIAL);
    os_unfair_lock_lock(&_lock); _conn[slot] = c; _queue[slot] = q; _busySince[slot] = 0; os_unfair_lock_unlock(&_lock);
    if (_notice[slot]) { IOObjectRelease(_notice[slot]); _notice[slot] = 0; }
    IOServiceAddInterestNotification(_port, svc, kIOGeneralInterest, slotGone, (void *)(intptr_t)(slot + 1), &_notice[slot]);
    [self.delegate x360DriverSlotAppeared:slot];
}

- (instancetype)init {
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        for (int i = 0; i < 4; i++) _queue[i] = dispatch_queue_create([NSString stringWithFormat:@"x360pad.slot%d", i + 1].UTF8String, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (io_connect_t)connection:(NSInteger)slot {
    os_unfair_lock_lock(&_lock); io_connect_t c = _conn[slot]; os_unfair_lock_unlock(&_lock);
    return c;
}

/// Forgets the slot's connection at once and closes it on the slot's queue, after any call still waiting on it.
- (void)closeSlot:(NSInteger)slot {
    os_unfair_lock_lock(&_lock); io_connect_t c = _conn[slot]; _conn[slot] = 0; dispatch_queue_t q = _queue[slot]; os_unfair_lock_unlock(&_lock);
    if (c) dispatch_async(q, ^{ IOServiceClose(c); });
}

/// Runs a call to the slot's driver on the slot's queue, with the slot marked busy while it waits.
- (void)call:(NSInteger)slot work:(void (^)(io_connect_t c))work {
    os_unfair_lock_lock(&_lock); io_connect_t c = _conn[slot]; dispatch_queue_t q = _queue[slot]; os_unfair_lock_unlock(&_lock);
    if (!c) return;
    dispatch_async(q, ^{
        os_unfair_lock_lock(&self->_lock); if (self->_queue[slot] == q) self->_busySince[slot] = mach_absolute_time(); os_unfair_lock_unlock(&self->_lock);
        work(c);
        os_unfair_lock_lock(&self->_lock); if (self->_queue[slot] == q) self->_busySince[slot] = 0; os_unfair_lock_unlock(&self->_lock);
    });
}

- (void)start {
    if (_port) return;
    gDriver = self;
    _port = IONotificationPortCreate(kIOMainPortDefault);
    IONotificationPortSetDispatchQueue(_port, dispatch_get_main_queue());
    CFMutableDictionaryRef m = IOServiceMatching("IOUserService");
    NSMutableDictionary *md = (__bridge NSMutableDictionary *)m;
    md[@kIOPropertyMatchKey] = @{@"IOUserClass": @"X360PadSlot"};
    // the slots register before they publish their number, so match on the number's arrival too: re-scan when one appears
    if (IOServiceAddMatchingNotification(_port, kIOMatchedNotification, m, matched, (__bridge void *)self, &_iter) == KERN_SUCCESS)
        matched((__bridge void *)self, _iter);
    // a slot's number is set right after it registers: look again shortly for any slot not yet open
    dispatch_async(dispatch_get_main_queue(), ^{ [self rescanLater]; });
}

- (void)rescanLater {
    __weak X360Driver *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        X360Driver *me = weak; if (!me) return;
        io_iterator_t it = 0;
        CFMutableDictionaryRef m = IOServiceMatching("IOUserService");
        ((__bridge NSMutableDictionary *)m)[@kIOPropertyMatchKey] = @{@"IOUserClass": @"X360PadSlot"};
        if (IOServiceGetMatchingServices(kIOMainPortDefault, m, &it) == KERN_SUCCESS) {
            io_service_t svc;
            while ((svc = IOIteratorNext(it))) {
                CFTypeRef p = IORegistryEntryCreateCFProperty(svc, CFSTR("X360PadSlotNumber"), kCFAllocatorDefault, 0);
                NSInteger slot = p ? [(__bridge NSNumber *)p integerValue] : -1;
                if (p) CFRelease(p);
                if (slot >= 0 && slot < 4 && ![me connection:slot]) [me open:svc];
                IOObjectRelease(svc);
            }
            IOObjectRelease(it);
        }
        [me rescanLater];
    });
}

- (BOOL)isOpen:(NSInteger)slot { return slot >= 0 && slot < 4 && [self connection:slot]; }

- (void)setSettings:(NSData *)settings forSlot:(NSInteger)slot {
    if (![self isOpen:slot] || settings.length != sizeof(x360_settings)) return;
    NSData *copy = [settings copy];
    [self call:slot work:^(io_connect_t c) {
        kern_return_t kr = IOConnectCallStructMethod(c, X360_UC_SET_SETTINGS, copy.bytes, copy.length, NULL, NULL);
        if (kr) os_log_error(OS_LOG_DEFAULT, "x360pad: slot %ld: settings not sent (0x%x)", (long)slot + 1, kr);
    }];
}

- (void)pollSlot:(NSInteger)slot reply:(void (^)(NSData *, BOOL))reply {
    if (![self isOpen:slot]) return;
    os_unfair_lock_lock(&_lock); uint64_t since = _busySince[slot]; os_unfair_lock_unlock(&_lock);
    if (since) {   // the last call has not come back: none queued behind it; after a second, the driver is not answering
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        uint64_t ns = (mach_absolute_time() - since) * tb.numer / tb.denom;
        if (ns > NSEC_PER_SEC) dispatch_async(dispatch_get_main_queue(), ^{ reply(nil, NO); });
        return;
    }
    [self call:slot work:^(io_connect_t c) {
        x360_state st; size_t n = sizeof st;
        kern_return_t kr = IOConnectCallStructMethod(c, X360_UC_GET_STATE, NULL, 0, &st, &n);
        NSData *d = kr == KERN_SUCCESS && n == sizeof st ? [NSData dataWithBytes:&st length:sizeof st] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ reply(d, YES); });
    }];
}

- (void)powerOffSlot:(NSInteger)slot {
    [self call:slot work:^(io_connect_t c) {
        kern_return_t kr = IOConnectCallScalarMethod(c, X360_UC_POWER_OFF, NULL, 0, NULL, NULL);
        if (kr) os_log_error(OS_LOG_DEFAULT, "x360pad: slot %ld: power off not sent (0x%x)", (long)slot + 1, kr);
    }];
}

- (void)testRumbleStrong:(uint8_t)strong weak:(uint8_t)weak milliseconds:(uint32_t)ms forSlot:(NSInteger)slot {
    [self call:slot work:^(io_connect_t c) {
        uint64_t in[3] = {strong, weak, ms};
        kern_return_t kr = IOConnectCallScalarMethod(c, X360_UC_TEST_RUMBLE, in, 3, NULL, NULL);
        if (kr) os_log_error(OS_LOG_DEFAULT, "x360pad: slot %ld: test rumble not sent (0x%x)", (long)slot + 1, kr);
    }];
}

@end
