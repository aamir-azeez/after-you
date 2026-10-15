#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AYNotificationRegistration : NSObject
@property(nonatomic) BOOL optedIn;
@property(nonatomic, copy) NSString *epoch;
@property(nonatomic, copy) NSString *tokenHash;
@property(nonatomic, copy) NSString *registeredHash;
@property(nonatomic) int64_t generation;
@property(nonatomic, readonly) BOOL pending;
@end

/// The Android NotificationStore schema and rules on SQLite. No credentials, photos,
/// recordings or raw tokens are stored. The file lives in Application Support and is
/// excluded from backup. Callers stay on one queue; methods throw no exceptions and
/// return nil/NO when the database is unavailable.
@interface AYNotificationStore : NSObject

+ (nullable instancetype)openInDirectory:(NSURL *)directory;
+ (NSString *)sha256:(NSString *)value;

- (nullable AYNotificationRegistration *)registration;
- (nullable AYNotificationRegistration *)setOptedIn:(BOOL)enabled;
- (BOOL)noteToken:(NSString *)token;
- (nullable AYNotificationRegistration *)clearBinding;
- (BOOL)bindEpoch:(NSString *)epoch token:(NSString *)token generation:(int64_t)generation;
/// YES only for a new or previously unposted event under the current binding.
- (BOOL)receive:(NSDictionary<NSString *, NSString *> *)event now:(int64_t)now;
- (void)markPosted:(NSDictionary<NSString *, NSString *> *)event;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)pendingPosts:(int64_t)now;
- (BOOL)markTapped:(NSString *)eventId;
- (nullable NSDictionary<NSString *, NSString *> *)pendingRoute:(int64_t)now;
- (BOOL)acknowledge:(NSString *)eventId;

- (BOOL)categoryEnabled:(NSString *)kind;
- (BOOL)setCategoriesTurns:(BOOL)turns hosting:(BOOL)hosting requests:(BOOL)requests;

@end

NS_ASSUME_NONNULL_END
