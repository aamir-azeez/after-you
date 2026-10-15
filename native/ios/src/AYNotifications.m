#import "AYNotifications.h"

#import <UserNotifications/UserNotifications.h>

#import "AYNotificationStore.h"
#import "AYPolicy.h"

// Firebase is optional and linked only when push is configured, so it is reached through
// the Objective-C runtime. These are the documented FirebaseCore/FirebaseMessaging selectors.
// Class methods are declared as instance methods and sent to the class object.
@protocol AYFirebaseAppClass <NSObject>
- (void)configureWithOptions:(id)options;
- (nullable id)defaultApp;
@end
@protocol AYFirebaseOptions <NSObject>
- (nullable id)initWithContentsOfFile:(NSString *)plistPath;
@end
@protocol AYFirebaseMessaging <NSObject>
- (void)setAutoInitEnabled:(BOOL)enabled;
- (void)setAPNSToken:(nullable NSData *)token;
- (nullable NSData *)APNSToken;
- (void)setDelegate:(nullable id)delegate;
- (void)tokenWithCompletion:(void (^)(NSString *_Nullable token, NSError *_Nullable error))completion;
- (void)deleteTokenWithCompletion:(void (^)(NSError *_Nullable error))completion;
@end
@protocol AYFirebaseMessagingClass <NSObject>
- (id<AYFirebaseMessaging>)messaging;
@end

static NSString *const AYEventKey = @"after_you_event_id";
static NSString *const AYTagPrefix = @"after_you_update:";
static const NSTimeInterval AYLocalTimeout = 9.0;
static const NSTimeInterval AYPermissionTimeout = 90.0;

// Native notification text, the same wording as the Android PlayerCopy entries.
static NSString *const AYCopyTurnTitle = @"Your friend left a turn";
static NSString *const AYCopyHostingTitle = @"Friend rooms";
static NSString *const AYCopyRedoTitle = @"Your friend asked for a redo";
static NSString *const AYCopyBody = @"Open After You to see your shared moment.";

static int64_t AYNowMs(void) {
	return (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

static NSString *AYJson(NSDictionary *value) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

@interface AYNotifications () <UNUserNotificationCenterDelegate>
@end

@implementation AYNotifications {
	AYNotificationStore *_store;
	BOOL _storeOpened;
	AYNotificationResult _resultSink;
	AYNotificationError _errorSink;
	AYNotificationEvent _receivedSink;
	AYNotificationEvent _tokenSink;
	NSMutableDictionary<NSString *, NSNumber *> *_active;
	NSMutableDictionary<NSString *, NSString *> *_operations;
	uint64_t _serial;
	NSNumber *_permissionTicket;
	NSString *_permissionId;
	BOOL _authorized;
	BOOL _sdkBusy;
	BOOL _ready;
	BOOL _resumed;
	BOOL _firebaseStarted;
	NSMutableArray<void (^)(BOOL)> *_apnsWaiters;
}

+ (instancetype)shared {
	static AYNotifications *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [AYNotifications new];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_active = [NSMutableDictionary dictionary];
		_operations = [NSMutableDictionary dictionary];
		_apnsWaiters = [NSMutableArray array];
	}
	return self;
}

- (AYNotificationStore *)store {
	if (!_storeOpened) {
		_storeOpened = YES;
		NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
		_store = support ? [AYNotificationStore openInDirectory:[support URLByAppendingPathComponent:@"after-you-notifications"]] : nil;
	}
	return _store;
}

// MARK: Firebase

- (nullable NSString *)firebasePlistPath {
	NSString *path = [[NSBundle mainBundle] pathForResource:@"GoogleService-Info" ofType:@"plist"];
	if (path == nil || NSClassFromString(@"FIRApp") == Nil || NSClassFromString(@"FIRMessaging") == Nil || NSClassFromString(@"FIROptions") == Nil) {
		return nil;
	}
	NSDictionary *options = [NSDictionary dictionaryWithContentsOfFile:path];
	NSString *bundleId = [NSBundle mainBundle].bundleIdentifier ?: @"";
	return options && [AYPolicy validFirebaseOptions:options bundleId:bundleId] ? path : nil;
}

- (BOOL)configured {
	return [self firebasePlistPath] != nil;
}

/// Configures Firebase once, only with a valid public configuration. Never raises.
- (nullable id<AYFirebaseMessaging>)messaging {
	NSString *path = [self firebasePlistPath];
	if (path == nil) {
		return nil;
	}
	@try {
		id<AYFirebaseAppClass> appClass = (id<AYFirebaseAppClass>)NSClassFromString(@"FIRApp");
		if ([appClass defaultApp] == nil) {
			id<AYFirebaseOptions> blank = (id<AYFirebaseOptions>)[NSClassFromString(@"FIROptions") alloc];
			id options = [blank initWithContentsOfFile:path];
			if (options == nil) {
				return nil;
			}
			[appClass configureWithOptions:options];
		}
		id<AYFirebaseMessaging> messaging = [(id<AYFirebaseMessagingClass>)NSClassFromString(@"FIRMessaging") messaging];
		if (!_firebaseStarted) {
			_firebaseStarted = YES;
			[messaging setDelegate:self];
		}
		return messaging;
	} @catch (NSException *exception) {
		return nil;
	}
}

// FIRMessagingDelegate, called on the main queue after a token rotation.
- (void)messaging:(id)messaging didReceiveRegistrationToken:(nullable NSString *)fcmToken {
	if (![AYPolicy validToken:fcmToken] || ![[self store] noteToken:fcmToken]) {
		return;
	}
	[self announceTokenChanged];
}

- (void)announceTokenChanged {
	if (!_ready || !_resumed || _tokenSink == nil) {
		return;
	}
	AYNotificationRegistration *state = [[self store] registration];
	if (state) {
		_tokenSink(AYJson(@{ @"generation" : @(state.generation), @"registration_pending" : @(state.pending) }));
	}
}

/// A tapped route is waiting. Sent only while the game runs in the foreground; otherwise its
/// own resume check reads the route after this tap was recorded.
- (void)announceRoutePending {
	if (!_ready || !_resumed || _tokenSink == nil) {
		return;
	}
	AYNotificationRegistration *state = [[self store] registration];
	if (state) {
		_tokenSink(AYJson(@{ @"generation" : @(state.generation), @"registration_pending" : @(state.pending), @"route_pending" : @YES }));
	}
}

// MARK: App hooks

- (void)installCenterDelegate {
	[UNUserNotificationCenter currentNotificationCenter].delegate = self;
	AYNotificationRegistration *state = [[self store] registration];
	if (state.optedIn && [self configured]) {
		// Apple asks apps to register on every launch; the APNs token can change.
		id<AYFirebaseMessaging> messaging = [self messaging];
		[messaging setAutoInitEnabled:YES];
		[[UIApplication sharedApplication] registerForRemoteNotifications];
	}
	[self refreshAuthorization:nil];
}

- (void)didRegisterDeviceToken:(NSData *)token {
	if ([self configured]) {
		[[self messaging] setAPNSToken:token];
	}
	[self finishApnsWaiters:YES];
}

- (void)didFailToRegister {
	[self finishApnsWaiters:NO];
}

- (void)finishApnsWaiters:(BOOL)registered {
	NSArray *waiters = [_apnsWaiters copy];
	[_apnsWaiters removeAllObjects];
	for (void (^waiter)(BOOL) in waiters) {
		waiter(registered);
	}
}

- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo completion:(void (^)(UIBackgroundFetchResult))completion {
	BOOL handled = [self receivePayload:userInfo presented:NO];
	if (completion) {
		completion(handled ? UIBackgroundFetchResultNewData : UIBackgroundFetchResultNoData);
	}
}

- (void)refreshAuthorization:(nullable void (^)(void))done {
	[[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
		BOOL authorized = settings.authorizationStatus == UNAuthorizationStatusAuthorized || settings.authorizationStatus == UNAuthorizationStatusProvisional ||
				settings.authorizationStatus == UNAuthorizationStatusEphemeral;
		BOOL alerts = authorized && settings.alertSetting != UNNotificationSettingDisabled;
		dispatch_async(dispatch_get_main_queue(), ^{
			self->_authorized = alerts;
			if (done) {
				done();
			}
		});
	}];
}

// MARK: Delivery

/// A hint from a push. Foreground hints refresh Godot; background hints become a local
/// notification. presented: the system already shows this alert, so never post another.
- (BOOL)receivePayload:(NSDictionary *)payload presented:(BOOL)presented {
	NSDictionary<NSString *, NSString *> *event = [AYPolicy notificationFromPayload:payload];
	AYNotificationStore *store = [self store];
	if (event == nil || store == nil || ![store categoryEnabled:event[@"kind"]]) {
		return NO;
	}
	if (![store receive:event now:AYNowMs()]) {
		return NO;
	}
	[self deliver:event store:store presented:presented];
	return YES;
}

- (void)deliver:(NSDictionary<NSString *, NSString *> *)event store:(AYNotificationStore *)store presented:(BOOL)presented {
	if (![store categoryEnabled:event[@"kind"]]) {
		return;
	}
	if (_ready && _resumed && _receivedSink) {
		_receivedSink(AYJson(event));
		[store markPosted:event];
		return;
	}
	if (presented) {
		[store markPosted:event];
		return;
	}
	if (!_authorized) {
		return;
	}
	UNMutableNotificationContent *content = [UNMutableNotificationContent new];
	NSString *kind = event[@"kind"];
	content.title = [kind isEqualToString:@"friend_room_available"] ? AYCopyHostingTitle : ([kind isEqualToString:@"redo_requested"] ? AYCopyRedoTitle : AYCopyTurnTitle);
	content.body = AYCopyBody;
	content.sound = [UNNotificationSound defaultSound];
	content.userInfo = @{ AYEventKey : event[@"event_id"] };
	// One visible notification per room and kind; a newer hint replaces the older one.
	NSString *tag = [AYTagPrefix stringByAppendingString:[AYNotificationStore sha256:[NSString stringWithFormat:@"%@:%@:%@", event[@"room_family"], event[@"room_id"], kind]]];
	content.threadIdentifier = tag;
	UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:tag content:content trigger:nil];
	[[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError *error) {
		if (error == nil) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[[self store] markPosted:event];
			});
		}
	}];
}

- (void)retryPending {
	AYNotificationStore *store = [self store];
	if (store == nil) {
		return;
	}
	for (NSDictionary *event in [store pendingPosts:AYNowMs()]) {
		[self deliver:event store:store presented:NO];
	}
}

- (void)cancelVisible {
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
	[center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
		NSMutableArray *identifiers = [NSMutableArray array];
		for (UNNotification *notification in notifications) {
			NSDictionary *info = notification.request.content.userInfo;
			if ([notification.request.identifier hasPrefix:AYTagPrefix] || info[AYEventKey] != nil || [AYPolicy notificationFromPayload:info] != nil) {
				[identifiers addObject:notification.request.identifier];
			}
		}
		[center removeDeliveredNotificationsWithIdentifiers:identifiers];
	}];
}

// UNUserNotificationCenterDelegate: in the foreground a hint refreshes the game without a banner.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSDictionary *info = notification.request.content.userInfo;
		if (info[AYEventKey] == nil) {
			[self receivePayload:info presented:YES];
		}
		completionHandler(UNNotificationPresentationOptionNone);
	});
}

// A tap records the route durably, like Android's NotificationOpenActivity. The game reads it
// through pending_route when it decides navigation is safe; the tap itself never navigates.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
	dispatch_async(dispatch_get_main_queue(), ^{
		@try {
			if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
				NSDictionary *info = response.notification.request.content.userInfo;
				AYNotificationStore *store = [self store];
				NSString *eventId = [info[AYEventKey] isKindOfClass:[NSString class]] ? info[AYEventKey] : nil;
				if (eventId == nil) {
					// An alert the system showed while the app was not running: record it first.
					NSDictionary<NSString *, NSString *> *event = [AYPolicy notificationFromPayload:info];
					if (event && [store categoryEnabled:event[@"kind"]]) {
						if ([store receive:event now:AYNowMs()]) {
							[store markPosted:event];
						}
						eventId = event[@"event_id"];
					}
				}
				if (eventId != nil && [store markTapped:eventId]) {
					// Android marks the tap before the game resumes, so its resume check always
					// sees it. Here the tap can arrive after that check, so ask for another one.
					[self announceRoutePending];
				}
			}
		} @catch (NSException *exception) {
			// A missing or stale hint cannot authorise another route.
		}
		completionHandler();
	});
}

// MARK: Godot requests

- (void)attachResult:(AYNotificationResult)result error:(AYNotificationError)error received:(AYNotificationEvent)received tokenChanged:(AYNotificationEvent)tokenChanged {
	_resultSink = [result copy];
	_errorSink = [error copy];
	_receivedSink = [received copy];
	_tokenSink = [tokenChanged copy];
}

- (void)detach {
	for (NSString *requestId in _active.allKeys) {
		[self failId:requestId operation:_operations[requestId] ?: @"" code:@"notification_activity_closed"];
	}
	_resultSink = nil;
	_errorSink = nil;
	_receivedSink = nil;
	_tokenSink = nil;
	_ready = NO;
	_resumed = NO;
}

- (void)setGodotReady:(BOOL)ready {
	_ready = ready;
	[self flush];
}

- (void)setResumed:(BOOL)resumed {
	_resumed = resumed;
	if (resumed) {
		[self refreshAuthorization:^{
			[self flush];
		}];
	}
}

- (void)flush {
	if (_ready && _resumed) {
		[self retryPending];
	}
}

/// Main-queue tickets stop an expired SDK callback from completing a reused ID.
- (nullable NSNumber *)begin:(NSString *)requestId operation:(NSString *)operation timeout:(NSTimeInterval)timeout {
	if (requestId.length < 1 || requestId.length > 128 || _active[requestId] != nil || _active.count >= 32) {
		return nil;
	}
	NSNumber *ticket = @(++_serial);
	_active[requestId] = ticket;
	_operations[requestId] = operation;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self fail:requestId operation:operation ticket:ticket code:@"notification_timeout"];
	});
	return ticket;
}

- (BOOL)current:(NSString *)requestId ticket:(NSNumber *)ticket {
	return [_active[requestId] isEqualToNumber:ticket];
}

- (BOOL)finish:(NSString *)requestId ticket:(NSNumber *)ticket {
	if (![self current:requestId ticket:ticket]) {
		return NO;
	}
	[_active removeObjectForKey:requestId];
	[_operations removeObjectForKey:requestId];
	if ([_permissionTicket isEqualToNumber:ticket]) {
		_permissionTicket = nil;
		_permissionId = nil;
	}
	return YES;
}

- (void)succeed:(NSString *)requestId operation:(NSString *)operation ticket:(NSNumber *)ticket data:(NSDictionary *)data {
	if ([self finish:requestId ticket:ticket] && _resultSink) {
		_resultSink(requestId, operation, AYJson(data));
	}
}

- (void)fail:(NSString *)requestId operation:(NSString *)operation ticket:(NSNumber *)ticket code:(NSString *)code {
	if ([self finish:requestId ticket:ticket] && _errorSink) {
		_errorSink(requestId, operation, code);
	}
}

- (void)failId:(NSString *)requestId operation:(NSString *)operation code:(NSString *)code {
	NSNumber *ticket = _active[requestId];
	if (ticket) {
		[self fail:requestId operation:operation ticket:ticket code:code];
	}
}

/// Runs one request on the main queue with its deadline, like the Android call() helper.
- (void)call:(NSString *)requestId operation:(NSString *)operation timeout:(NSTimeInterval)timeout action:(void (^)(NSNumber *ticket))action {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSNumber *ticket = [self begin:requestId operation:operation timeout:timeout];
		if (ticket == nil) {
			return;
		}
		if ([self store] == nil) {
			[self fail:requestId operation:operation ticket:ticket code:@"notification_unavailable"];
			return;
		}
		@try {
			action(ticket);
		} @catch (NSException *exception) {
			[self fail:requestId operation:operation ticket:ticket code:@"notification_unavailable"];
		}
	});
}

- (NSDictionary *)statusData {
	AYNotificationRegistration *state = [[self store] registration];
	BOOL configured = [self configured];
	return @{
		@"supported" : @(configured),
		@"configured" : @(configured),
		@"opted_in" : @(state.optedIn),
		@"permission_granted" : @(_authorized),
		@"channel_enabled" : @(_authorized),
		@"hosting_channel_enabled" : @(_authorized),
		@"registration_pending" : @(state.pending),
		@"generation" : @(state.generation),
	};
}

- (void)setCategoriesTurns:(BOOL)turns hosting:(BOOL)hosting requests:(BOOL)requests requestId:(NSString *)requestId {
	[self call:requestId operation:@"set_categories" timeout:AYLocalTimeout action:^(NSNumber *ticket) {
		if ([[self store] setCategoriesTurns:turns hosting:hosting requests:requests]) {
			[self succeed:requestId operation:@"set_categories" ticket:ticket data:@{ @"updated" : @YES }];
		} else {
			[self fail:requestId operation:@"set_categories" ticket:ticket code:@"notification_unavailable"];
		}
	}];
}

- (void)status:(NSString *)requestId {
	[self call:requestId operation:@"status" timeout:AYLocalTimeout action:^(NSNumber *ticket) {
		[self refreshAuthorization:^{
			[self succeed:requestId operation:@"status" ticket:ticket data:[self statusData]];
		}];
	}];
}

- (void)requestPermission:(NSString *)requestId {
	[self call:requestId operation:@"request_permission" timeout:AYPermissionTimeout action:^(NSNumber *ticket) {
		if (![self configured]) {
			[self fail:requestId operation:@"request_permission" ticket:ticket code:@"notification_unconfigured"];
			return;
		}
		if (self->_permissionTicket != nil) {
			[self fail:requestId operation:@"request_permission" ticket:ticket code:@"notification_permission_busy"];
			return;
		}
		self->_permissionTicket = ticket;
		self->_permissionId = requestId;
		// iOS asks once. After a refusal this returns at once with granted = NO.
		UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
		[[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self refreshAuthorization:^{
					if (![self current:requestId ticket:ticket]) {
						return;
					}
					[self completePermission:requestId ticket:ticket];
				}];
			});
		}];
	}];
}

- (void)completePermission:(NSString *)requestId ticket:(NSNumber *)ticket {
	BOOL granted = _authorized;
	if ([[self store] setOptedIn:granted] == nil) {
		[self fail:requestId operation:@"request_permission" ticket:ticket code:@"notification_unavailable"];
		return;
	}
	if (granted) {
		[[UIApplication sharedApplication] registerForRemoteNotifications];
	} else {
		[self cancelVisible];
		[[self messaging] setAutoInitEnabled:NO];
	}
	[self succeed:requestId operation:@"request_permission" ticket:ticket data:[self statusData]];
}

- (void)getToken:(NSString *)requestId {
	[self call:requestId operation:@"get_token" timeout:AYLocalTimeout action:^(NSNumber *ticket) {
		if (![self configured]) {
			[self fail:requestId operation:@"get_token" ticket:ticket code:@"notification_unconfigured"];
			return;
		}
		if (self->_sdkBusy) {
			[self fail:requestId operation:@"get_token" ticket:ticket code:@"notification_provider_busy"];
			return;
		}
		AYNotificationRegistration *before = [[self store] registration];
		if (!before.optedIn || !self->_authorized) {
			[self fail:requestId operation:@"get_token" ticket:ticket code:@"notification_not_enabled"];
			return;
		}
		id<AYFirebaseMessaging> messaging = [self messaging];
		if (messaging == nil) {
			[self fail:requestId operation:@"get_token" ticket:ticket code:@"notification_unconfigured"];
			return;
		}
		[messaging setAutoInitEnabled:YES];
		self->_sdkBusy = YES;
		void (^fetch)(BOOL) = ^(BOOL registered) {
			if (!registered) {
				self->_sdkBusy = NO;
				[self fail:requestId operation:@"get_token" ticket:ticket code:@"notification_token_unavailable"];
				return;
			}
			[messaging tokenWithCompletion:^(NSString *token, NSError *error) {
				dispatch_async(dispatch_get_main_queue(), ^{
					self->_sdkBusy = NO;
					if (![self current:requestId ticket:ticket]) {
						return;
					}
					[self finishToken:token before:before requestId:requestId ticket:ticket];
				});
			}];
		};
		// FCM needs the APNs device token first.
		if ([messaging APNSToken] != nil) {
			fetch(YES);
		} else {
			[self->_apnsWaiters addObject:fetch];
			[[UIApplication sharedApplication] registerForRemoteNotifications];
		}
	}];
}

- (void)finishToken:(nullable NSString *)token before:(AYNotificationRegistration *)before requestId:(NSString *)requestId ticket:(NSNumber *)ticket {
	AYNotificationStore *store = [self store];
	AYNotificationRegistration *current = [store registration];
	if (current == nil || !current.optedIn || current.generation != before.generation) {
		[self fail:requestId operation:@"get_token" ticket:ticket code:@"notification_binding_changed"];
		return;
	}
	if (![AYPolicy validToken:token]) {
		[self fail:requestId operation:@"get_token" ticket:ticket code:@"notification_token_unavailable"];
		return;
	}
	NSString *digest = [AYNotificationStore sha256:token];
	if (![current.tokenHash isEqualToString:before.tokenHash] && ![current.tokenHash isEqualToString:digest]) {
		[self fail:requestId operation:@"get_token" ticket:ticket code:@"notification_binding_changed"];
		return;
	}
	[store noteToken:token];
	AYNotificationRegistration *next = [store registration];
	[self succeed:requestId operation:@"get_token" ticket:ticket data:@{ @"token" : token, @"generation" : @(next.generation) }];
}

- (void)setBindingEpoch:(NSString *)epoch token:(NSString *)token generation:(int64_t)generation requestId:(NSString *)requestId {
	[self call:requestId operation:@"set_binding" timeout:AYLocalTimeout action:^(NSNumber *ticket) {
		if (![self configured] || !self->_authorized) {
			[self fail:requestId operation:@"set_binding" ticket:ticket code:@"notification_not_enabled"];
			return;
		}
		AYNotificationStore *store = [self store];
		AYNotificationRegistration *before = [store registration];
		if (![store bindEpoch:epoch token:token generation:generation]) {
			[self fail:requestId operation:@"set_binding" ticket:ticket code:@"notification_binding_changed"];
			return;
		}
		if (![before.epoch isEqualToString:epoch]) {
			[self cancelVisible];
		}
		[self succeed:requestId operation:@"set_binding" ticket:ticket data:@{ @"bound" : @YES, @"binding_epoch" : epoch, @"generation" : @([store registration].generation) }];
	}];
}

- (void)clearBinding:(NSString *)requestId {
	[self call:requestId operation:@"clear_binding" timeout:AYLocalTimeout action:^(NSNumber *ticket) {
		AYNotificationRegistration *next = [[self store] clearBinding];
		[self cancelVisible];
		if (next == nil) {
			[self fail:requestId operation:@"clear_binding" ticket:ticket code:@"notification_unavailable"];
			return;
		}
		[self succeed:requestId operation:@"clear_binding" ticket:ticket data:@{ @"cleared" : @YES, @"generation" : @(next.generation) }];
	}];
}

- (void)disable:(NSString *)requestId {
	[self call:requestId operation:@"disable" timeout:AYLocalTimeout action:^(NSNumber *ticket) {
		AYNotificationRegistration *next = [[self store] setOptedIn:NO];
		[self cancelVisible];
		if (next == nil) {
			[self fail:requestId operation:@"disable" ticket:ticket code:@"notification_unavailable"];
			return;
		}
		void (^done)(BOOL) = ^(BOOL deleted) {
			[self succeed:requestId operation:@"disable" ticket:ticket data:@{ @"disabled" : @YES, @"token_deleted" : @(deleted), @"generation" : @(next.generation) }];
		};
		id<AYFirebaseMessaging> messaging = [self configured] ? [self messaging] : nil;
		if (messaging == nil) {
			done(next.tokenHash.length == 0);
			return;
		}
		[messaging setAutoInitEnabled:NO];
		if (self->_sdkBusy) {
			[self fail:requestId operation:@"disable" ticket:ticket code:@"notification_provider_busy"];
			return;
		}
		self->_sdkBusy = YES;
		[messaging deleteTokenWithCompletion:^(NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				self->_sdkBusy = NO;
				if (![self current:requestId ticket:ticket]) {
					return;
				}
				if ([[self store] registration].generation != next.generation) {
					[self fail:requestId operation:@"disable" ticket:ticket code:@"notification_binding_changed"];
				} else {
					done(error == nil);
				}
			});
		}];
	}];
}

- (void)pendingRoute:(NSString *)requestId {
	[self call:requestId operation:@"pending_route" timeout:AYLocalTimeout action:^(NSNumber *ticket) {
		NSDictionary *route = [[self store] pendingRoute:AYNowMs()];
		[self succeed:requestId operation:@"pending_route" ticket:ticket data:@{ @"route" : route ?: @{} }];
	}];
}

- (void)acknowledge:(NSString *)eventId requestId:(NSString *)requestId {
	[self call:requestId operation:@"ack_route" timeout:AYLocalTimeout action:^(NSNumber *ticket) {
		if ([[self store] acknowledge:eventId]) {
			[self succeed:requestId operation:@"ack_route" ticket:ticket data:@{ @"acknowledged" : @YES, @"event_id" : eventId }];
		} else {
			[self fail:requestId operation:@"ack_route" ticket:ticket code:@"notification_route_unavailable"];
		}
	}];
}

@end
