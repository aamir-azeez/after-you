#import "AYGamesPolicy.h"

#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

@implementation AYGamesPolicy

+ (NSUInteger)maxSnapshotBytes {
	return 3 * 1024 * 1024;
}

+ (BOOL)matches:(NSString *)value pattern:(NSString *)pattern {
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", pattern];
	return [predicate evaluateWithObject:value];
}

+ (BOOL)validSnapshotName:(NSString *)name {
	return [self matches:name pattern:@"[a-z][a-z0-9-]{0,63}"];
}

+ (BOOL)validHandle:(NSString *)handle {
	return [self matches:handle pattern:@"[a-f0-9]{32}"];
}

+ (BOOL)validDescription:(NSString *)description {
	if (description.length > 100) {
		return NO;
	}
	return [description rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound;
}

+ (nullable NSData *)decodeSnapshot:(NSString *)base64 {
	if (base64.length == 0) {
		return [NSData data];
	}
	if (base64.length > ([self maxSnapshotBytes] / 3 + 1) * 4) {
		return nil;
	}
	NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
	return data.length <= [self maxSnapshotBytes] ? data : nil;
}

+ (BOOL)validPlayerName:(nullable NSString *)name {
	return name.length > 0 && name.length <= 64;
}

+ (NSString *)playerKey:(NSString *)teamPlayerId {
	NSData *input = [[@"after-you:game_center:" stringByAppendingString:teamPlayerId] dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
		[hex appendFormat:@"%02x", digest[i]];
	}
	return hex;
}

+ (NSString *)newHandle {
	uint8_t bytes[16];
	if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) {
		arc4random_buf(bytes, sizeof(bytes));
	}
	NSMutableString *hex = [NSMutableString stringWithCapacity:32];
	for (int i = 0; i < 16; i++) {
		[hex appendFormat:@"%02x", bytes[i]];
	}
	return hex;
}

@end
