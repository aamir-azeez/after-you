#import "AYPolicy.h"

static BOOL AYMatches(NSString *pattern, NSString *value) {
	if (value == nil) {
		return NO;
	}
	NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
	NSRange whole = NSMakeRange(0, value.length);
	NSTextCheckingResult *match = [expression firstMatchInString:value options:NSMatchingAnchored range:whole];
	return match != nil && NSEqualRanges(match.range, whole);
}

@implementation AYPolicy

+ (BOOL)validStorageName:(NSString *)name {
	return AYMatches(@"[a-z][a-z0-9_.-]{0,63}", name);
}

+ (BOOL)validStorageValue:(NSString *)value {
	return [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 16384;
}

+ (NSString *)recoveryTextForPlayer:(NSString *)playerId code:(NSString *)recoveryCode {
	if (!AYMatches(@"[A-Za-z0-9_-]{22}", playerId) || !AYMatches(@"[A-Za-z0-9_-]{43}", recoveryCode)) {
		return nil;
	}
	return [NSString stringWithFormat:@"After You recovery details\nIdentity: %@\nRecovery code: %@", playerId, recoveryCode];
}

+ (NSString *)configErrorForKey:(NSString *)apiKey player:(NSString *)playerId mode:(NSString *)mode allowTestStore:(BOOL)allowTestStore {
	// The bridge supplies the compile-time build flag; caller configuration cannot enable
	// Test Store in a release build. Tester codes never configure a purchase SDK.
	NSString *prefix = nil;
	if ([mode isEqualToString:@"app_store"]) {
		prefix = @"appl_";
	} else if ([mode isEqualToString:@"test_store"] && allowTestStore) {
		prefix = @"test_";
	} else {
		return @"unsupported_store";
	}
	if (!AYMatches(@"[A-Za-z0-9_-]{8,128}", playerId)) {
		return @"invalid_player_id";
	}
	if (apiKey.length < 12 || apiKey.length > 256 || !AYMatches(@"[A-Za-z0-9_-]+", apiKey)) {
		return @"invalid_public_key";
	}
	return [apiKey hasPrefix:prefix] ? nil : @"store_key_mismatch";
}

+ (NSString *)invalidLink {
	return @"invalid";
}

+ (BOOL)validInviteLink:(NSString *)link {
	// Code in the fragment, or the ?c= fallback; optional trailing slash. The bare /after-you
	// path, other paths, ports, user info, extra parameters and other code types never match.
	return link != nil && link.length <= 256 &&
			AYMatches(@"(?i:https)://(?i:aamirazeez\\.com)/after-you/link/?(?:#|\\?c=)friend-(?:[A-Za-z0-9_-]{22}|[A-Za-z][A-Za-z0-9]{2,15})", link);
}

+ (NSString *)inboxValueForURL:(NSURL *)url {
	if (url == nil) {
		return nil;
	}
	NSString *text = url.absoluteString;
	return [self validInviteLink:text] ? text : [self invalidLink];
}

+ (BOOL)validToken:(NSString *)token {
	if (token == nil || token.length < 16 || token.length > 4096) {
		return NO;
	}
	for (NSUInteger i = 0; i < token.length; i++) {
		unichar c = [token characterAtIndex:i];
		if (c < 33 || c > 126) {
			return NO;
		}
	}
	return YES;
}

+ (BOOL)validEpoch:(NSString *)epoch {
	return AYMatches(@"[A-Za-z0-9_-]{22}", epoch);
}

+ (BOOL)validEventId:(NSString *)eventId {
	return AYMatches(@"[A-Za-z0-9_-]{16,128}", eventId);
}

+ (NSDictionary<NSString *, NSString *> *)notificationFromPayload:(NSDictionary *)payload {
	NSSet *turnKeys = [NSSet setWithArray:@[ @"schema_version", @"event_id", @"kind", @"room_id", @"room_family", @"revision", @"binding_epoch" ]];
	NSSet *friendKeys = [NSSet setWithArray:@[ @"schema_version", @"event_id", @"kind", @"host_id", @"room_id", @"room_family", @"publication_epoch", @"binding_epoch" ]];
	NSMutableDictionary<NSString *, NSString *> *data = [NSMutableDictionary dictionary];
	NSUInteger total = 0;
	for (id key in payload) {
		if (![key isKindOfClass:[NSString class]]) {
			return nil;
		}
		NSString *name = key;
		if ([name isEqualToString:@"aps"] || [name hasPrefix:@"gcm."] || [name hasPrefix:@"google."]) {
			continue;
		}
		id value = payload[key];
		if (![value isKindOfClass:[NSString class]]) {
			return nil;
		}
		data[name] = value;
		total += [(NSString *)value length];
	}
	NSSet *keys = [NSSet setWithArray:data.allKeys];
	if ((![keys isEqualToSet:turnKeys] && ![keys isEqualToSet:friendKeys]) || total > 1024) {
		return nil;
	}
	if (![data[@"schema_version"] isEqualToString:@"1"]) {
		return nil;
	}
	NSString *event = data[@"event_id"];
	NSString *kind = data[@"kind"];
	BOOL hosting = [kind isEqualToString:@"friend_room_available"];
	if (hosting && (![keys isEqualToSet:friendKeys] || !AYMatches(@"[A-Za-z0-9_-]{22}", data[@"host_id"]))) {
		return nil;
	}
	if (!hosting && ![keys isEqualToSet:turnKeys]) {
		return nil;
	}
	NSString *rawRevision = data[hosting ? @"publication_epoch" : @"revision"];
	if (![self validEventId:event] || !AYMatches(@"[A-Za-z0-9_-]{22}", data[@"room_id"]) || ![self validEpoch:data[@"binding_epoch"]]) {
		return nil;
	}
	if (![@[ @"turn_ready", @"friend_room_available", @"redo_requested" ] containsObject:kind] || ![@[ @"legacy", @"relay" ] containsObject:data[@"room_family"]]) {
		return nil;
	}
	if ([kind isEqualToString:@"redo_requested"] && !AYMatches(@"redo_[a-f0-9]{64}", event)) {
		return nil;
	}
	if (!AYMatches(@"[1-9][0-9]{0,15}", rawRevision) || rawRevision.longLongValue > 9007199254740991LL) {
		return nil;
	}
	if (hosting && ![event isEqualToString:[NSString stringWithFormat:@"%@_%@", data[@"host_id"], rawRevision]]) {
		return nil;
	}
	return [data copy];
}

+ (BOOL)validFirebaseOptions:(NSDictionary *)options bundleId:(NSString *)bundleId {
	id appId = options[@"GOOGLE_APP_ID"];
	id apiKey = options[@"API_KEY"];
	id sender = options[@"GCM_SENDER_ID"];
	id project = options[@"PROJECT_ID"];
	id bundle = options[@"BUNDLE_ID"];
	for (id value in @[ appId ?: [NSNull null], apiKey ?: [NSNull null], sender ?: [NSNull null], project ?: [NSNull null], bundle ?: [NSNull null] ]) {
		if (![value isKindOfClass:[NSString class]]) {
			return NO;
		}
	}
	if (!AYMatches(@"1:[0-9]{6,20}:ios:[A-Fa-f0-9]{16,64}", appId) || !AYMatches(@"AIza[A-Za-z0-9_-]{35}", apiKey) ||
			!AYMatches(@"[0-9]{6,20}", sender) || !AYMatches(@"[a-z][a-z0-9-]{4,62}", project)) {
		return NO;
	}
	NSArray *parts = [(NSString *)appId componentsSeparatedByString:@":"];
	return parts.count > 1 && [parts[1] isEqualToString:sender] && [bundle isEqualToString:bundleId];
}

@end
