#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Game Center rules with no GameKit types, so the macOS host test covers them: the request
/// shapes the bridge accepts, the one-way player key and the bound on the Game Center alias the
/// game may ask for with player_name. Mirrors PlayGamesPolicy.kt.
@interface AYGamesPolicy : NSObject

/// Saved Games allows 3 MiB a slot (matching Play Games).
+ (NSUInteger)maxSnapshotBytes;
+ (BOOL)validSnapshotName:(NSString *)name;
+ (BOOL)validHandle:(NSString *)handle;
+ (BOOL)validDescription:(NSString *)description;
/// Decoded slot bytes, or nil when the text is too long or not base64. "" is an empty slot.
+ (nullable NSData *)decodeSnapshot:(NSString *)base64;
/// 1 to 64 UTF-16 units. Only a bound: the name is passed on unchanged and the game validates it.
+ (BOOL)validPlayerName:(nullable NSString *)name;
/// SHA-256 hex of "after-you:game_center:<teamPlayerID>".
+ (NSString *)playerKey:(NSString *)teamPlayerId;
+ (NSString *)newHandle;

@end

NS_ASSUME_NONNULL_END
