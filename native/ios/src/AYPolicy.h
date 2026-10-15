#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Validation shared by every native service. The rules match the Android bridge
/// (BridgePolicy.kt, InviteLink.kt, NotificationPolicy.kt). Nothing here grants access.
@interface AYPolicy : NSObject

+ (BOOL)validStorageName:(NSString *)name;
+ (BOOL)validStorageValue:(NSString *)value;
+ (nullable NSString *)recoveryTextForPlayer:(NSString *)playerId code:(NSString *)recoveryCode;

/// Returns nil when the configuration is valid, otherwise the Android error code.
+ (nullable NSString *)configErrorForKey:(NSString *)apiKey player:(NSString *)playerId mode:(NSString *)mode allowTestStore:(BOOL)allowTestStore;

/// The invite link contract: https://aamirazeez.com/after-you/link#friend-... or ?c=friend-...
+ (BOOL)validInviteLink:(nullable NSString *)link;
/// The value to offer the inbox for one opened link: the URL text, "invalid", or nil to ignore.
+ (nullable NSString *)inboxValueForURL:(nullable NSURL *)url;
+ (NSString *)invalidLink;

+ (BOOL)validToken:(nullable NSString *)token;
+ (BOOL)validEpoch:(nullable NSString *)epoch;
+ (BOOL)validEventId:(nullable NSString *)eventId;
/// Accepts only the agreed hint schema. APNs and FCM keys ("aps", "gcm.*", "google.*") are
/// ignored; every remaining key must be one of the hint fields. Returns the canonical fields.
+ (nullable NSDictionary<NSString *, NSString *> *)notificationFromPayload:(NSDictionary *)payload;

/// Public Firebase configuration from GoogleService-Info.plist, checked like Android's.
+ (BOOL)validFirebaseOptions:(NSDictionary *)options bundleId:(NSString *)bundleId;

@end

NS_ASSUME_NONNULL_END
