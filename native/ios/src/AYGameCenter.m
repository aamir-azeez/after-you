#import "AYGameCenter.h"
#import "AYGamesPolicy.h"

@import GameKit;
@import UIKit;

/// An open saved-games slot: every saved game with the slot's name (more than one is a conflict).
@interface AYGamesSlot : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<GKSavedGame *> *games;
@end

@implementation AYGamesSlot
@end

@interface AYGameCenter ()
@property (nonatomic, copy, nullable) AYGamesResult resultSink;
@property (nonatomic, copy, nullable) AYGamesError errorSink;
@property (nonatomic, copy, nullable) AYGamesAccountChanged accountSink;
@property (nonatomic, strong) NSMutableSet<NSString *> *pending;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AYGamesSlot *> *slots;
/// Requests waiting for the authenticate handler's next answer.
@property (nonatomic, strong) NSMutableArray<NSArray<NSString *> *> *waiting;
@property (nonatomic, strong, nullable) UIViewController *signInController;
@property (nonatomic, copy, nullable) NSString *lastPlayerKey;
@property (nonatomic) BOOL handlerInstalled;
@property (nonatomic) BOOL answered;
@property (nonatomic, copy, nullable) NSString *lastError;
@end

@implementation AYGameCenter

+ (instancetype)shared {
	static AYGameCenter *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[AYGameCenter alloc] init];
		shared.pending = [NSMutableSet set];
		shared.slots = [NSMutableDictionary dictionary];
		shared.waiting = [NSMutableArray array];
	});
	return shared;
}

- (void)attachResult:(AYGamesResult)result error:(AYGamesError)error accountChanged:(AYGamesAccountChanged)accountChanged {
	self.resultSink = result;
	self.errorSink = error;
	self.accountSink = accountChanged;
}

- (void)detach {
	self.resultSink = nil;
	self.errorSink = nil;
	self.accountSink = nil;
}

- (BOOL)available {
	// Only a build that declares the Game Center capability turns this on (export_plugin.gd).
	return [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"AYGameCenterEnabled"] boolValue];
}

#pragma mark - One answer per request

- (BOOL)begin:(NSString *)requestId {
	if (requestId.length < 1 || requestId.length > 128 || [self.pending containsObject:requestId]) {
		return NO;
	}
	[self.pending addObject:requestId];
	return YES;
}

- (void)succeed:(NSString *)requestId operation:(NSString *)operation payload:(NSDictionary *)payload {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (![self.pending containsObject:requestId]) {
			return;
		}
		[self.pending removeObject:requestId];
		NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
		if (self.resultSink) {
			self.resultSink(requestId, operation, data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}");
		}
	});
}

- (void)fail:(NSString *)requestId operation:(NSString *)operation code:(NSString *)code {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (![self.pending containsObject:requestId]) {
			return;
		}
		[self.pending removeObject:requestId];
		if (self.errorSink) {
			self.errorSink(requestId, operation, code);
		}
	});
}

/// GameKit and network errors as the game's codes; Apple's text never reaches the game.
- (NSString *)codeFor:(nullable NSError *)error {
	if (error == nil) {
		return @"failed";
	}
	if ([error.domain isEqualToString:NSURLErrorDomain]) {
		return @"offline";
	}
	if ([error.domain isEqualToString:GKErrorDomain]) {
		switch (error.code) {
			case GKErrorCancelled:
			case GKErrorUserDenied:
				return @"cancelled";
			case GKErrorCommunicationsFailure:
				return @"offline";
			case GKErrorNotAuthenticated:
				return @"signed_out";
			case GKErrorNotSupported:
			case GKErrorGameUnrecognized:
			case GKErrorParentalControlsBlocked:
				return @"unavailable";
			default:
				return @"failed";
		}
	}
	return @"failed";
}

#pragma mark - Sign-in

/// Setting the handler starts Game Center's own sign-in. It may answer more than once: with a
/// view controller when the player must sign in, later when the account changes.
- (void)installHandler {
	if (self.handlerInstalled) {
		return;
	}
	self.handlerInstalled = YES;
	__weak AYGameCenter *weakSelf = self;
	[GKLocalPlayer localPlayer].authenticateHandler = ^(UIViewController *_Nullable controller, NSError *_Nullable error) {
		AYGameCenter *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		strongSelf.answered = YES;
		strongSelf.signInController = controller;
		strongSelf.lastError = error ? [strongSelf codeFor:error] : nil;
		[strongSelf noteAccount];
		[strongSelf answerWaiting];
	};
}

- (void)noteAccount {
	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	NSString *key = player.isAuthenticated && player.teamPlayerID.length > 0 ? [AYGamesPolicy playerKey:player.teamPlayerID] : nil;
	if (self.lastPlayerKey != nil && key != nil && ![self.lastPlayerKey isEqualToString:key] && self.accountSink) {
		self.accountSink(@"{}");
	}
	if (key != nil) {
		self.lastPlayerKey = key;
	}
}

- (NSDictionary *)statusPayload {
	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	if (!player.isAuthenticated || player.teamPlayerID.length == 0) {
		return @{ @"signed_in" : @NO };
	}
	return @{ @"signed_in" : @YES, @"player_key" : [AYGamesPolicy playerKey:player.teamPlayerID] };
}

- (void)answerWaiting {
	NSArray<NSArray<NSString *> *> *waiting = [self.waiting copy];
	[self.waiting removeAllObjects];
	for (NSArray<NSString *> *entry in waiting) {
		NSString *requestId = entry[0], *operation = entry[1];
		if ([operation isEqualToString:@"sign_in"] && self.signInController != nil && ![GKLocalPlayer localPlayer].isAuthenticated) {
			// Still waiting for the player in Apple's sheet.
			[self.waiting addObject:entry];
			continue;
		}
		if (self.lastError != nil && ![GKLocalPlayer localPlayer].isAuthenticated && ![self.lastError isEqualToString:@"cancelled"]) {
			[self fail:requestId operation:operation code:self.lastError];
		} else {
			[self succeed:requestId operation:operation payload:[self statusPayload]];
		}
	}
}

- (void)status:(NSString *)requestId {
	if (![self begin:requestId]) {
		return;
	}
	if (![self available]) {
		[self fail:requestId operation:@"status" code:@"unavailable"];
		return;
	}
	[self.waiting addObject:@[ requestId, @"status" ]];
	[self installHandler];
	if (self.answered) {
		[self answerWaiting];
	}
}

- (void)signIn:(NSString *)requestId {
	if (![self begin:requestId]) {
		return;
	}
	if (![self available]) {
		[self fail:requestId operation:@"sign_in" code:@"unavailable"];
		return;
	}
	[self installHandler];
	if ([GKLocalPlayer localPlayer].isAuthenticated) {
		[self succeed:requestId operation:@"sign_in" payload:[self statusPayload]];
		return;
	}
	UIViewController *controller = self.signInController;
	if (controller == nil) {
		// Game Center shows its sheet once per launch; after a cancel the player signs in from the Settings app.
		[self fail:requestId operation:@"sign_in" code:self.answered ? @"cancelled" : @"busy"];
		return;
	}
	UIViewController *top = self.presenter ? self.presenter() : nil;
	if (top == nil) {
		[self fail:requestId operation:@"sign_in" code:@"unavailable"];
		return;
	}
	[self.waiting addObject:@[ requestId, @"sign_in" ]];
	[top presentViewController:controller animated:YES completion:nil];
}

#pragma mark - Server verification

- (void)credential:(NSString *)requestId {
	if (![self begin:requestId]) {
		return;
	}
	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	if (![self available] || !player.isAuthenticated) {
		[self fail:requestId operation:@"credential" code:[self available] ? @"signed_out" : @"unavailable"];
		return;
	}
	NSString *team = player.teamPlayerID;
	[player fetchItemsForIdentityVerificationSignature:^(NSURL *_Nullable publicKeyURL, NSData *_Nullable signature, NSData *_Nullable salt, uint64_t timestamp, NSError *_Nullable error) {
		if (error != nil || publicKeyURL == nil || signature == nil || salt == nil || team.length == 0) {
			[self fail:requestId operation:@"credential" code:[self codeFor:error]];
			return;
		}
		// The server checks the signature over teamPlayerID, bundle id, timestamp and salt.
		[self succeed:requestId operation:@"credential" payload:@{ @"credential" : @{
			@"public_key_url" : publicKeyURL.absoluteString,
			@"signature" : [signature base64EncodedStringWithOptions:0],
			@"salt" : [salt base64EncodedStringWithOptions:0],
			@"timestamp" : @(timestamp),
			@"team_player_id" : team,
		} }];
	}];
}

#pragma mark - Saved games (iCloud)

- (void)answerSlot:(AYGamesSlot *)slot requestId:(NSString *)requestId operation:(NSString *)operation {
	NSArray<GKSavedGame *> *games = slot.games;
	if (games.count == 0) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *handle = [AYGamesPolicy newHandle];
			self.slots[handle] = slot;
			[self succeed:requestId operation:operation payload:@{ @"handle" : handle, @"data" : @"" }];
		});
		return;
	}
	[games[0] loadDataWithCompletionHandler:^(NSData *_Nullable first, NSError *_Nullable error) {
		if (error != nil || first.length > [AYGamesPolicy maxSnapshotBytes]) {
			[self fail:requestId operation:operation code:[self codeFor:error]];
			return;
		}
		void (^finish)(NSData *_Nullable) = ^(NSData *_Nullable other) {
			dispatch_async(dispatch_get_main_queue(), ^{
				NSString *handle = [AYGamesPolicy newHandle];
				self.slots[handle] = slot;
				NSMutableDictionary *payload = [@{ @"handle" : handle, @"data" : [(first ?: [NSData data]) base64EncodedStringWithOptions:0] } mutableCopy];
				if (other != nil) {
					payload[@"conflict"] = @{ @"data" : [other base64EncodedStringWithOptions:0] };
				}
				[self succeed:requestId operation:operation payload:payload];
			});
		};
		if (games.count == 1) {
			finish(nil);
			return;
		}
		[games[1] loadDataWithCompletionHandler:^(NSData *_Nullable second, NSError *_Nullable otherError) {
			if (otherError != nil || second.length > [AYGamesPolicy maxSnapshotBytes]) {
				[self fail:requestId operation:operation code:[self codeFor:otherError]];
				return;
			}
			finish(second ?: [NSData data]);
		}];
	}];
}

- (void)snapshotOpen:(NSString *)name requestId:(NSString *)requestId {
	if (![self begin:requestId]) {
		return;
	}
	if (![self available] || ![GKLocalPlayer localPlayer].isAuthenticated || ![AYGamesPolicy validSnapshotName:name]) {
		[self fail:requestId operation:@"snapshot_open" code:@"unavailable"];
		return;
	}
	// One sync at a time: an open forgets slots an earlier, abandoned sync left.
	[self.slots removeAllObjects];
	[[GKLocalPlayer localPlayer] fetchSavedGamesWithCompletionHandler:^(NSArray<GKSavedGame *> *_Nullable saved, NSError *_Nullable error) {
		if (error != nil) {
			[self fail:requestId operation:@"snapshot_open" code:[self codeFor:error]];
			return;
		}
		AYGamesSlot *slot = [[AYGamesSlot alloc] init];
		slot.name = name;
		slot.games = [saved filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", name]] ?: @[];
		[self answerSlot:slot requestId:requestId operation:@"snapshot_open"];
	}];
}

- (nullable AYGamesSlot *)takeSlot:(NSString *)handle {
	if (![AYGamesPolicy validHandle:handle]) {
		return nil;
	}
	AYGamesSlot *slot = self.slots[handle];
	[self.slots removeObjectForKey:handle];
	return slot;
}

- (void)snapshotResolve:(NSString *)handle data:(NSString *)base64 requestId:(NSString *)requestId {
	if (![self begin:requestId]) {
		return;
	}
	AYGamesSlot *slot = [self takeSlot:handle];
	NSData *data = [AYGamesPolicy decodeSnapshot:base64];
	if (slot == nil || data == nil || slot.games.count < 2) {
		[self fail:requestId operation:@"snapshot_resolve" code:@"failed"];
		return;
	}
	// Only the two copies the game read and joined; any third comes back as the next conflict.
	[[GKLocalPlayer localPlayer] resolveConflictingSavedGames:@[ slot.games[0], slot.games[1] ] withData:data completionHandler:^(NSArray<GKSavedGame *> *_Nullable saved, NSError *_Nullable error) {
		if (error != nil) {
			[self fail:requestId operation:@"snapshot_resolve" code:[self codeFor:error]];
			return;
		}
		AYGamesSlot *next = [[AYGamesSlot alloc] init];
		next.name = slot.name;
		next.games = [saved filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", slot.name]] ?: @[];
		[self answerSlot:next requestId:requestId operation:@"snapshot_resolve"];
	}];
}

- (void)snapshotCommit:(NSString *)handle data:(NSString *)base64 description:(NSString *)description requestId:(NSString *)requestId {
	if (![self begin:requestId]) {
		return;
	}
	AYGamesSlot *slot = [self takeSlot:handle];
	NSData *data = [AYGamesPolicy decodeSnapshot:base64];
	if (slot == nil || data == nil || slot.games.count > 1 || ![AYGamesPolicy validDescription:description]) {
		[self fail:requestId operation:@"snapshot_commit" code:@"failed"];
		return;
	}
	[[GKLocalPlayer localPlayer] saveGameData:data withName:slot.name completionHandler:^(GKSavedGame *_Nullable savedGame, NSError *_Nullable error) {
		if (error != nil || savedGame == nil) {
			[self fail:requestId operation:@"snapshot_commit" code:[self codeFor:error]];
		} else {
			[self succeed:requestId operation:@"snapshot_commit" payload:@{ @"committed" : @YES }];
		}
	}];
}

- (void)snapshotDiscard:(NSString *)handle requestId:(NSString *)requestId {
	if (![self begin:requestId]) {
		return;
	}
	BOOL held = [self takeSlot:handle] != nil;
	[self succeed:requestId operation:@"snapshot_discard" payload:@{ @"discarded" : @(held) }];
}

@end
