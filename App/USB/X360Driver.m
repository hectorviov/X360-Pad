// See X360Driver.h.
#import "X360Driver.h"
#import <IOKit/IOKitLib.h>
#include "../../Driver/X360Settings.h"

@implementation X360Driver {
    io_connect_t _conn[4];
    io_object_t _notice[4];
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
    if (self->_conn[i]) { IOServiceClose(self->_conn[i]); self->_conn[i] = 0; }
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
    if (_conn[slot]) { IOServiceClose(_conn[slot]); _conn[slot] = 0; }
    io_connect_t c = 0;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &c);
    if (kr != KERN_SUCCESS) { [self.delegate x360DriverOpenFailed:slot result:kr]; return; }
    _conn[slot] = c;
    if (_notice[slot]) { IOObjectRelease(_notice[slot]); _notice[slot] = 0; }
    IOServiceAddInterestNotification(_port, svc, kIOGeneralInterest, slotGone, (void *)(intptr_t)(slot + 1), &_notice[slot]);
    [self.delegate x360DriverSlotAppeared:slot];
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
                if (slot >= 0 && slot < 4 && !me->_conn[slot]) [me open:svc];
                IOObjectRelease(svc);
            }
            IOObjectRelease(it);
        }
        [me rescanLater];
    });
}

- (BOOL)isOpen:(NSInteger)slot { return slot >= 0 && slot < 4 && _conn[slot]; }

- (int)setSettings:(NSData *)settings forSlot:(NSInteger)slot {
    if (![self isOpen:slot] || settings.length != sizeof(x360_settings)) return kIOReturnNotOpen;
    return IOConnectCallStructMethod(_conn[slot], X360_UC_SET_SETTINGS, settings.bytes, settings.length, NULL, NULL);
}

- (NSData *)stateForSlot:(NSInteger)slot {
    if (![self isOpen:slot]) return nil;
    x360_state st; size_t n = sizeof st;
    if (IOConnectCallStructMethod(_conn[slot], X360_UC_GET_STATE, NULL, 0, &st, &n) != KERN_SUCCESS || n != sizeof st) return nil;
    return [NSData dataWithBytes:&st length:sizeof st];
}

- (int)powerOffSlot:(NSInteger)slot {
    if (![self isOpen:slot]) return kIOReturnNotOpen;
    return IOConnectCallScalarMethod(_conn[slot], X360_UC_POWER_OFF, NULL, 0, NULL, NULL);
}

- (int)testRumbleStrong:(uint8_t)strong weak:(uint8_t)weak milliseconds:(uint32_t)ms forSlot:(NSInteger)slot {
    if (![self isOpen:slot]) return kIOReturnNotOpen;
    uint64_t in[3] = {strong, weak, ms};
    return IOConnectCallScalarMethod(_conn[slot], X360_UC_TEST_RUMBLE, in, 3, NULL, NULL);
}

@end
