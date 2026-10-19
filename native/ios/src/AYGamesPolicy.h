#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Game Center rules with no GameKit types, so the macOS host test covers them: the request
/// shapes the bridge accepts and the one-way player key. Mirrors PlayGamesPolicy.kt.
@interface AYGamesPolicy : NSObject

/// Saved Games allows 3 MiB a slot (matching Play Games).
+ (NSUInteger)maxSnapshotBytes;
+ (BOOL)validSnapshotName:(NSString *)name;
+ (BOOL)validHandle:(NSString *)handle;
+ (BOOL)validDescription:(NSString *)description;
/// Decoded slot bytes, or nil when the text is too long or not base64. "" is an empty slot.
+ (nullable NSData *)decodeSnapshot:(NSString *)base64;
/// SHA-256 hex of "after-you:game_center:<teamPlayerID>".
+ (NSString *)playerKey:(NSString *)teamPlayerId;
+ (NSString *)newHandle;

@end

NS_ASSUME_NONNULL_END
