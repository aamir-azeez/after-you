#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Device credentials in the iOS Keychain: generic passwords under one service, readable
/// after first unlock and never synced or migrated (ThisDeviceOnly). The counterpart of the
/// Android Keystore store. Methods are blocking; call them from a background queue.
@interface AYKeychainStore : NSObject

- (instancetype)initWithService:(NSString *)service markerDirectory:(NSURL *)markerDirectory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// YES once the value can be read back exactly.
- (BOOL)putName:(NSString *)name value:(NSString *)value;
/// Sets *found; returns nil with *found = NO when absent. Returns nil with *failed = YES on error.
- (nullable NSString *)getName:(NSString *)name found:(BOOL *)found failed:(BOOL *)failed;
/// YES when the item is gone afterwards.
- (BOOL)removeName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
