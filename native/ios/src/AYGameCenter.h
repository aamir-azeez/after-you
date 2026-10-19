#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class UIViewController;

typedef void (^AYGamesResult)(NSString *requestId, NSString *operation, NSString *payloadJson);
typedef void (^AYGamesError)(NSString *requestId, NSString *operation, NSString *code);
typedef void (^AYGamesAccountChanged)(NSString *payloadJson);

/// Game Center with the Android Play Games bridge's contract: the same games_* operations,
/// payloads and codes, so the shared GDScript provider serves both. The game receives only a
/// SHA-256 player key, never the Game Center player id; the server verification credential is
/// Apple's signed identity data (fetchItemsForIdentityVerificationSignature). Saved games use
/// GKSavedGame (iCloud). Off unless the build's Info.plist has AYGameCenterEnabled = YES, so a
/// build without the Game Center capability never shows Game Center UI. Main queue only.
@interface AYGameCenter : NSObject

+ (instancetype)shared;
/// Where Apple's sign-in sheet is shown from (the top view controller), set by the extension.
@property (nonatomic, copy, nullable) UIViewController *_Nullable (^presenter)(void);
- (void)attachResult:(AYGamesResult)result error:(AYGamesError)error accountChanged:(AYGamesAccountChanged)accountChanged;
- (void)detach;

- (BOOL)available;
- (void)status:(NSString *)requestId;
- (void)signIn:(NSString *)requestId;
- (void)credential:(NSString *)requestId;
- (void)snapshotOpen:(NSString *)name requestId:(NSString *)requestId;
- (void)snapshotCommit:(NSString *)handle data:(NSString *)base64 description:(NSString *)description requestId:(NSString *)requestId;
- (void)snapshotResolve:(NSString *)handle data:(NSString *)base64 requestId:(NSString *)requestId;
- (void)snapshotDiscard:(NSString *)handle requestId:(NSString *)requestId;

@end

NS_ASSUME_NONNULL_END
