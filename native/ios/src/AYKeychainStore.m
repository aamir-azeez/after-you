#import "AYKeychainStore.h"

#import <Security/Security.h>

#import "AYPolicy.h"

@implementation AYKeychainStore {
	NSString *_service;
	NSURL *_marker;
	BOOL _installChecked;
}

- (instancetype)initWithService:(NSString *)service markerDirectory:(NSURL *)markerDirectory {
	self = [super init];
	if (self) {
		_service = [service copy];
		_marker = [markerDirectory URLByAppendingPathComponent:@"keychain-install-v1"];
	}
	return self;
}

- (NSMutableDictionary *)queryFor:(NSString *)name {
	return [@{
		(__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService : _service,
		(__bridge id)kSecAttrAccount : name,
	} mutableCopy];
}

// Keychain items outlive an uninstall on iOS, while the Android store and the game's save
// do not. A marker file in the app container (removed on uninstall, excluded from backup)
// tells a fresh install apart, so stale credentials never meet a fresh save.
- (BOOL)prepareInstall {
	if (_installChecked) {
		return YES;
	}
	NSFileManager *files = [NSFileManager defaultManager];
	if (![files fileExistsAtPath:_marker.path]) {
		NSDictionary *all = @{
			(__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
			(__bridge id)kSecAttrService : _service,
		};
		OSStatus status = SecItemDelete((__bridge CFDictionaryRef)all);
		if (status != errSecSuccess && status != errSecItemNotFound) {
			return NO;
		}
		NSURL *directory = _marker.URLByDeletingLastPathComponent;
		if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]) {
			return NO;
		}
		[directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
		if (![[NSData data] writeToURL:_marker options:NSDataWritingAtomic error:nil]) {
			return NO;
		}
	}
	_installChecked = YES;
	return YES;
}

- (BOOL)putName:(NSString *)name value:(NSString *)value {
	@synchronized(self) {
		if (![AYPolicy validStorageName:name] || ![AYPolicy validStorageValue:value] || ![self prepareInstall]) {
			return NO;
		}
		NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
		NSDictionary *update = @{
			(__bridge id)kSecValueData : data,
			(__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
		};
		OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)[self queryFor:name], (__bridge CFDictionaryRef)update);
		if (status == errSecItemNotFound) {
			NSMutableDictionary *add = [self queryFor:name];
			[add addEntriesFromDictionary:update];
			status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
		}
		if (status != errSecSuccess) {
			return NO;
		}
		// Never acknowledge a new identity until the stored value reads back exactly.
		BOOL found = NO;
		BOOL failed = NO;
		NSString *stored = [self readName:name found:&found failed:&failed];
		return found && !failed && [stored isEqualToString:value];
	}
}

- (NSString *)readName:(NSString *)name found:(BOOL *)found failed:(BOOL *)failed {
	*found = NO;
	*failed = NO;
	NSMutableDictionary *query = [self queryFor:name];
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound) {
		return nil;
	}
	if (status != errSecSuccess || result == NULL) {
		*failed = YES;
		return nil;
	}
	NSData *data = (__bridge_transfer NSData *)result;
	NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (value == nil) {
		*failed = YES;
		return nil;
	}
	*found = YES;
	return value;
}

- (NSString *)getName:(NSString *)name found:(BOOL *)found failed:(BOOL *)failed {
	@synchronized(self) {
		*found = NO;
		*failed = NO;
		if (![AYPolicy validStorageName:name] || ![self prepareInstall]) {
			*failed = YES;
			return nil;
		}
		return [self readName:name found:found failed:failed];
	}
}

- (BOOL)removeName:(NSString *)name {
	@synchronized(self) {
		if (![AYPolicy validStorageName:name] || ![self prepareInstall]) {
			return NO;
		}
		OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self queryFor:name]);
		if (status != errSecSuccess && status != errSecItemNotFound) {
			return NO;
		}
		// A failed delete must stay retryable, so confirm the item is really gone.
		BOOL found = NO;
		BOOL failed = NO;
		[self readName:name found:&found failed:&failed];
		return !found && !failed;
	}
}

@end
