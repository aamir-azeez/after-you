#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Single-slot, take-once, memory-only invite link inbox, like Android's InviteLinkInbox.
/// A newer link replaces an untaken one. Links are untrusted and never logged.
@interface AYInviteLinkInbox : NSObject
+ (instancetype)shared;
- (void)offer:(NSString *)value;
- (NSString *)take;
- (BOOL)hasPending;
/// Called on the main queue after each offer. Set by the Godot singleton once it exists.
@property(atomic, copy, nullable) void (^listener)(void);
@end

/// Installs the app delegate service, the notification center delegate and the APNs
/// callbacks before UIApplicationMain runs. Safe to call more than once.
void AYInstallAppHooks(void);

NS_ASSUME_NONNULL_END
