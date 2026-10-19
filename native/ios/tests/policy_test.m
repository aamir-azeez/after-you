// Host test for the platform-independent parts of the iOS plugin: validation rules and the
// notification ledger. Built and run on the macOS CI runner:
//   clang -fobjc-arc -fmodules -I native/ios/src native/ios/tests/policy_test.m \
//     native/ios/src/AYPolicy.m native/ios/src/AYNotificationStore.m native/ios/src/AYGamesPolicy.m -lsqlite3 -o policy_test
#import <Foundation/Foundation.h>

#import "AYGamesPolicy.h"
#import "AYNotificationStore.h"
#import "AYPolicy.h"

static int failures = 0;
static int checks = 0;

static void check(BOOL condition, NSString *message) {
	checks++;
	if (!condition) {
		failures++;
		fprintf(stderr, "FAIL: %s\n", message.UTF8String);
	}
}

static NSString *repeat(NSString *text, NSUInteger count) {
	return [@"" stringByPaddingToLength:text.length * count withString:text startingAtIndex:0];
}

static NSDictionary *turnEvent(NSString *eventId, NSString *room, NSString *revision, NSString *epoch) {
	return @{ @"schema_version" : @"1", @"event_id" : eventId, @"kind" : @"turn_ready", @"room_id" : room, @"room_family" : @"relay", @"revision" : revision, @"binding_epoch" : epoch };
}

int main(void) {
	@autoreleasepool {
		NSString *player = repeat(@"P", 22);
		NSString *link = [@"https://aamirazeez.com/after-you/link#friend-" stringByAppendingString:player];
		check([AYPolicy validInviteLink:link], @"Fragment invite link is accepted");
		check([AYPolicy validInviteLink:[@"https://aamirazeez.com/after-you/link/?c=friend-" stringByAppendingString:player]], @"Query form with a trailing slash is accepted");
		check([AYPolicy validInviteLink:@"HTTPS://AAMIRAZEEZ.COM/after-you/link#friend-aamir"], @"Scheme and host are case-insensitive; short names are accepted");
		check(![AYPolicy validInviteLink:@"https://aamirazeez.com/after-you#friend-aamir"], @"The bare /after-you path is rejected");
		check(![AYPolicy validInviteLink:@"https://aamirazeez.com:443/after-you/link#friend-aamir"], @"Ports are rejected");
		check(![AYPolicy validInviteLink:@"https://aamirazeez.com/after-you/link#room-ABCDEF"], @"Other code types are rejected");
		check(![AYPolicy validInviteLink:[link stringByAppendingString:@"&x=1"]], @"Extra parameters are rejected");
		check([[AYPolicy inboxValueForURL:[NSURL URLWithString:@"https://aamirazeez.com/elsewhere"]] isEqualToString:@"invalid"], @"A rejected opened URL becomes the generic invalid value");
		check([[AYPolicy inboxValueForURL:[NSURL URLWithString:link]] isEqualToString:link], @"A valid opened URL is passed unchanged");

		check([AYPolicy validStorageName:@"device_token"] && ![AYPolicy validStorageName:@"Device"] && ![AYPolicy validStorageName:@""], @"Storage names follow the Android pattern");
		check([AYPolicy validStorageValue:repeat(@"a", 16384)] && ![AYPolicy validStorageValue:repeat(@"a", 16385)], @"Storage values are capped at 16 KiB");
		NSString *recovery = [AYPolicy recoveryTextForPlayer:repeat(@"i", 22) code:repeat(@"r", 43)];
		check([recovery isEqualToString:[NSString stringWithFormat:@"After You recovery details\nIdentity: %@\nRecovery code: %@", repeat(@"i", 22), repeat(@"r", 43)]], @"Recovery text matches Android exactly");
		check([AYPolicy recoveryTextForPlayer:@"short" code:repeat(@"r", 43)] == nil, @"Malformed recovery details are refused");

		NSString *key = @"appl_abcdefghijklmnop";
		check([AYPolicy configErrorForKey:key player:repeat(@"p", 22) mode:@"app_store" allowTestStore:NO] == nil, @"App Store key and mode are accepted in release");
		check([[AYPolicy configErrorForKey:@"test_abcdefghijklmnop" player:repeat(@"p", 22) mode:@"test_store" allowTestStore:NO] isEqualToString:@"unsupported_store"], @"Test Store is refused in release builds");
		check([AYPolicy configErrorForKey:@"test_abcdefghijklmnop" player:repeat(@"p", 22) mode:@"test_store" allowTestStore:YES] == nil, @"Test Store is accepted in debug builds");
		check([[AYPolicy configErrorForKey:@"goog_abcdefghijklmnop" player:repeat(@"p", 22) mode:@"google_play" allowTestStore:YES] isEqualToString:@"unsupported_store"], @"Google Play mode is not an iOS store");
		check([[AYPolicy configErrorForKey:@"test_abcdefghijklmnop" player:repeat(@"p", 22) mode:@"app_store" allowTestStore:YES] isEqualToString:@"store_key_mismatch"], @"A key for another store is refused");
		check([[AYPolicy configErrorForKey:key player:@"bad id" mode:@"app_store" allowTestStore:NO] isEqualToString:@"invalid_player_id"], @"Player IDs are validated");

		NSString *epoch = repeat(@"E", 22);
		NSString *room = repeat(@"R", 22);
		NSString *eventA = repeat(@"a", 20);
		NSMutableDictionary *push = [turnEvent(eventA, room, @"5", epoch) mutableCopy];
		push[@"aps"] = @{ @"content-available" : @1 };
		push[@"gcm.message_id"] = @"1234";
		push[@"google.c.sender.id"] = @"5678";
		check([[AYPolicy notificationFromPayload:push] isEqualToDictionary:turnEvent(eventA, room, @"5", epoch)], @"APNs and FCM keys are ignored; the hint fields remain");
		NSMutableDictionary *extra = [push mutableCopy];
		extra[@"title"] = @"x";
		check([AYPolicy notificationFromPayload:extra] == nil, @"Unknown keys are rejected");
		check([AYPolicy notificationFromPayload:turnEvent(eventA, room, @"0", epoch)] == nil, @"Revision zero is rejected");
		NSDictionary *hosting = @{ @"schema_version" : @"1", @"event_id" : [room stringByAppendingString:@"_7"], @"kind" : @"friend_room_available", @"host_id" : room, @"room_id" : room, @"room_family" : @"relay", @"publication_epoch" : @"7", @"binding_epoch" : epoch };
		check([AYPolicy notificationFromPayload:hosting] != nil, @"Friend room hints are accepted when the event ID matches host and epoch");
		NSMutableDictionary *badHost = [hosting mutableCopy];
		badHost[@"publication_epoch"] = @"8";
		check([AYPolicy notificationFromPayload:badHost] == nil, @"A friend room event ID must match its publication epoch");

		NSDictionary *firebase = @{ @"GOOGLE_APP_ID" : @"1:123456789:ios:0123456789abcdef", @"API_KEY" : [@"AIza" stringByAppendingString:repeat(@"x", 35)], @"GCM_SENDER_ID" : @"123456789", @"PROJECT_ID" : @"after-you-game", @"BUNDLE_ID" : @"com.aamirazeez.afteryou" };
		check([AYPolicy validFirebaseOptions:firebase bundleId:@"com.aamirazeez.afteryou"], @"A complete iOS Firebase configuration is accepted");
		check(![AYPolicy validFirebaseOptions:firebase bundleId:@"com.example.other"], @"A configuration for another bundle is refused");

		NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSUUID UUID].UUIDString];
		AYNotificationStore *store = [AYNotificationStore openInDirectory:directory];
		check(store != nil, @"The ledger opens");
		check([store registration].generation == 0 && ![store registration].optedIn, @"A new ledger starts opted out at generation 0");
		check(![store receive:turnEvent(eventA, room, @"5", epoch) now:1000], @"Hints are ignored before opt-in");
		AYNotificationRegistration *opted = [store setOptedIn:YES];
		check(opted.optedIn && opted.generation == 1 && opted.pending, @"Opting in bumps the generation and leaves registration pending");
		NSString *token = repeat(@"t", 40);
		check([store noteToken:token], @"A valid token is noted by hash only");
		check(![store bindEpoch:epoch token:token generation:0], @"A stale generation cannot bind");
		check([store bindEpoch:epoch token:token generation:1] && ![store registration].pending, @"Binding completes registration");
		check([store receive:turnEvent(eventA, room, @"5", epoch) now:1000], @"A new hint is accepted");
		check([store pendingPosts:1000].count == 1, @"An unposted hint stays pending");
		[store markPosted:turnEvent(eventA, room, @"5", epoch)];
		check(![store receive:turnEvent(eventA, room, @"5", epoch) now:1001], @"A posted hint is not delivered twice");
		check(![store receive:turnEvent(repeat(@"b", 20), room, @"4", epoch) now:1002], @"An older revision for the same room is ignored");
		check(![store receive:turnEvent(repeat(@"c", 20), room, @"6", repeat(@"Z", 22)) now:1003], @"A hint for another binding is ignored");
		check([store markTapped:eventA], @"A tap marks the event");
		check([[store pendingRoute:1004][@"event_id"] isEqualToString:eventA], @"The tapped event becomes the pending route");
		check([store acknowledge:eventA] && [store pendingRoute:1005] == nil, @"Acknowledging clears the route");
		check([store receive:turnEvent(repeat(@"d", 20), room, @"9", epoch) now:1000 + 8LL * 24 * 3600 * 1000], @"A newer hint after retention is accepted");
		check([store categoryEnabled:@"turn_ready"] && ![store categoryEnabled:@"friend_room_available"] && ![store categoryEnabled:@"redo_requested"], @"Category defaults match Android");
		check([store setCategoriesTurns:NO hosting:YES requests:YES] && ![store categoryEnabled:@"turn_ready"] && [store categoryEnabled:@"friend_room_available"], @"Saved categories apply");
		AYNotificationRegistration *cleared = [store clearBinding];
		check(cleared.optedIn && cleared.epoch.length == 0 && cleared.generation == 2 && cleared.pending, @"Clearing the binding keeps the preference and bumps the generation");
		AYNotificationRegistration *off = [store setOptedIn:NO];
		check(!off.optedIn && off.generation == 3, @"Opting out bumps the generation");
		store = nil;
		AYNotificationStore *reopened = [AYNotificationStore openInDirectory:directory];
		check(reopened != nil && [reopened registration].generation == 3, @"The ledger persists across opens");
		[[NSFileManager defaultManager] removeItemAtURL:directory error:nil];

		// Game Center: the same request shapes as Android's PlayGamesPolicy, and a one-way key.
		check([[AYGamesPolicy playerKey:@"T:_synthetic_team_player"] isEqualToString:@"d814ecfc33e4de3163fcacc697464f16a476e0fa6c17ceab191a280c45ed5f51"], @"The Game Center player key is SHA-256 of the prefixed team player id");
		check(![[AYGamesPolicy playerKey:@"T:_a"] isEqualToString:[AYGamesPolicy playerKey:@"T:_b"]], @"Different players get different keys");
		check([AYGamesPolicy validSnapshotName:@"after-you-progress"] && ![AYGamesPolicy validSnapshotName:@"../x"] && ![AYGamesPolicy validSnapshotName:repeat(@"a", 65)], @"Saved game names are bounded");
		NSString *handle = [AYGamesPolicy newHandle];
		check([AYGamesPolicy validHandle:handle] && ![handle isEqualToString:[AYGamesPolicy newHandle]] && ![AYGamesPolicy validHandle:@"zz"], @"Slot handles are random 32-hex strings");
		check([AYGamesPolicy validDescription:@"After You progress"] && ![AYGamesPolicy validDescription:@"line\nbreak"] && ![AYGamesPolicy validDescription:repeat(@"x", 101)], @"Slot descriptions are short plain text");
		check([AYGamesPolicy decodeSnapshot:@""].length == 0 && [[AYGamesPolicy decodeSnapshot:@"QVlDMQ=="] isEqualToData:[@"AYC1" dataUsingEncoding:NSUTF8StringEncoding]], @"Slot bytes decode from base64");
		check([AYGamesPolicy decodeSnapshot:@"not base64!"] == nil && [AYGamesPolicy decodeSnapshot:repeat(@"A", 4 * 1024 * 1024 + 8)] == nil, @"Bad or oversized slot text is refused");

		printf("AFTER YOU iOS POLICY: %d checks, %d failures\n", checks, failures);
	}
	return failures == 0 ? 0 : 1;
}
