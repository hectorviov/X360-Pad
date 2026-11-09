// The app's side of the driver's user client (Driver/X360PadUserClient): finds each controller slot's driver service (X360PadSlot, by its
// X360PadSlotNumber property), opens it, and sends settings / reads state / tests the motors. Main queue.
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
/// An x360_settings (Driver/X360Settings.h). Returns the IOKit result.
- (int)setSettings:(NSData *)settings forSlot:(NSInteger)slot;
/// An x360_state, or nil when the slot is not open.
- (nullable NSData *)stateForSlot:(NSInteger)slot;
- (int)powerOffSlot:(NSInteger)slot;
- (int)testRumbleStrong:(uint8_t)strong weak:(uint8_t)weak milliseconds:(uint32_t)ms forSlot:(NSInteger)slot;
@end

NS_ASSUME_NONNULL_END
