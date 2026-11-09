// The app's side of the driver's user client (Driver/X360PadUserClient): finds each controller slot's driver service (X360PadSlot, by its
// X360PadSlotNumber property), opens it, and sends settings / reads state / tests the motors. Discovery runs on the main queue; every call to the
// driver runs on the slot's own background queue, so a driver that stops answering can never stall the app's window.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol X360DriverDelegate <NSObject>
- (void)x360DriverSlotAppeared:(NSInteger)slot;
- (void)x360DriverSlotGone:(NSInteger)slot;
- (void)x360DriverOpenFailed:(NSInteger)slot result:(int)result;
@end

@interface X360Driver : NSObject
@property (nonatomic, weak) id<X360DriverDelegate> delegate;
- (void)start;
- (BOOL)isOpen:(NSInteger)slot;
/// Sends an x360_settings (Driver/X360Settings.h).
- (void)setSettings:(NSData *)settings forSlot:(NSInteger)slot;
/// Reads the slot's x360_state; the reply comes on the main queue: the state (nil if the call failed), and whether the driver is answering
/// (NO while an earlier call has been waiting for over a second, in which case no new call is made).
- (void)pollSlot:(NSInteger)slot reply:(void (^)(NSData *_Nullable state, BOOL responding))reply;
- (void)powerOffSlot:(NSInteger)slot;
- (void)testRumbleStrong:(uint8_t)strong weak:(uint8_t)weak milliseconds:(uint32_t)ms forSlot:(NSInteger)slot;
@end

NS_ASSUME_NONNULL_END
