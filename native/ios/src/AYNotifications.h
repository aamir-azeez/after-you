#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AYNotificationResult)(NSString *requestId, NSString *operation, NSString *payloadJson);
typedef void (^AYNotificationError)(NSString *requestId, NSString *operation, NSString *code);
typedef void (^AYNotificationEvent)(NSString *payloadJson);

/// Turn notifications on iOS, mirroring the Android NotificationBridge contract: opt-in,
/// binding epochs and generations, a local ledger with watermarks, and a take-once tap route.
/// Firebase Messaging supplies the token because the backend sends through FCM. Without a
/// valid bundled GoogleService-Info.plist and the Firebase SDK, every request reports
/// "notification_unconfigured" and nothing is registered. All methods run on the main queue.
@interface AYNotifications : NSObject

+ (instancetype)shared;

// App lifecycle hooks (AYAppHooks).
- (void)installCenterDelegate;
- (void)didRegisterDeviceToken:(NSData *)token;
- (void)didFailToRegister;
- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo completion:(void (^)(UIBackgroundFetchResult))completion;

// Godot singleton.
- (void)attachResult:(AYNotificationResult)result error:(AYNotificationError)error received:(AYNotificationEvent)received tokenChanged:(AYNotificationEvent)tokenChanged;
- (void)detach;
- (void)setGodotReady:(BOOL)ready;
- (void)setResumed:(BOOL)resumed;

- (void)setCategoriesTurns:(BOOL)turns hosting:(BOOL)hosting requests:(BOOL)requests requestId:(NSString *)requestId;
- (void)status:(NSString *)requestId;
- (void)requestPermission:(NSString *)requestId;
- (void)getToken:(NSString *)requestId;
- (void)setBindingEpoch:(NSString *)epoch token:(NSString *)token generation:(int64_t)generation requestId:(NSString *)requestId;
- (void)clearBinding:(NSString *)requestId;
- (void)pendingRoute:(NSString *)requestId;
- (void)acknowledge:(NSString *)eventId requestId:(NSString *)requestId;
- (void)disable:(NSString *)requestId;

@end

NS_ASSUME_NONNULL_END
