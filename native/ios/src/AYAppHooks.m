#import "AYAppHooks.h"

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "AYNotifications.h"
#import "AYPolicy.h"

@implementation AYInviteLinkInbox {
	NSString *_pending;
}

+ (instancetype)shared {
	static AYInviteLinkInbox *inbox;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		inbox = [AYInviteLinkInbox new];
	});
	return inbox;
}

- (void)offer:(NSString *)value {
	if (![value isEqualToString:[AYPolicy invalidLink]] && ![AYPolicy validInviteLink:value]) {
		return;
	}
	@synchronized(self) {
		_pending = [value copy];
	}
	void (^listener)(void) = self.listener;
	if (listener) {
		dispatch_async(dispatch_get_main_queue(), listener);
	}
}

- (NSString *)take {
	@synchronized(self) {
		NSString *value = _pending ?: @"";
		_pending = nil;
		return value;
	}
}

- (BOOL)hasPending {
	@synchronized(self) {
		return _pending != nil;
	}
}

@end

/// Registered with Godot's app delegate. Godot forwards launch, scene and user activity
/// callbacks to every service; this one only reads invite links and wires notifications.
@interface AYAppDelegateService : NSObject <UIApplicationDelegate, UIWindowSceneDelegate>
@end

@implementation AYAppDelegateService

- (void)offerActivity:(NSUserActivity *)activity {
	if (![activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
		return;
	}
	NSString *value = [AYPolicy inboxValueForURL:activity.webpageURL];
	if (value != nil) {
		[[AYInviteLinkInbox shared] offer:value];
	}
}

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	// Must happen before launch finishes, so a tap that launched the app still arrives.
	[[AYNotifications shared] installCenterDelegate];
	return YES;
}

// Cold start: the link arrives with the scene connection, before Godot has started.
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions API_AVAILABLE(ios(13.0)) {
	for (NSUserActivity *activity in connectionOptions.userActivities) {
		[self offerActivity:activity];
	}
}

// Warm start: the app was already running.
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity API_AVAILABLE(ios(13.0)) {
	[self offerActivity:userActivity];
}

// Without a scene manifest UIKit uses the application-level callback instead.
- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *))restorationHandler {
	if (![userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
		return NO;
	}
	[self offerActivity:userActivity];
	return YES;
}

@end

// Godot's GDTApplicationDelegate does not implement the APNs callbacks, so UIKit would never
// deliver the device token. Add them to that class before UIApplicationMain caches which
// delegate methods exist. class_addMethod leaves an existing implementation untouched.
static void AYAddRemoteNotificationMethods(Class delegateClass) {
	IMP registered = imp_implementationWithBlock(^(id delegate, UIApplication *application, NSData *token) {
		[[AYNotifications shared] didRegisterDeviceToken:token];
	});
	class_addMethod(delegateClass, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), registered, "v@:@@");
	IMP failed = imp_implementationWithBlock(^(id delegate, UIApplication *application, NSError *error) {
		[[AYNotifications shared] didFailToRegister];
	});
	class_addMethod(delegateClass, @selector(application:didFailToRegisterForRemoteNotificationsWithError:), failed, "v@:@@");
	IMP received = imp_implementationWithBlock(^(id delegate, UIApplication *application, NSDictionary *userInfo, void (^completion)(UIBackgroundFetchResult)) {
		[[AYNotifications shared] didReceiveRemoteNotification:userInfo completion:completion];
	});
	class_addMethod(delegateClass, @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:), received, "v@:@@@?");
}

void AYInstallAppHooks(void) {
	static AYAppDelegateService *service;
	Class delegateClass = NSClassFromString(@"GDTApplicationDelegate");
	if (delegateClass == Nil || ![delegateClass respondsToSelector:@selector(addService:)] || ![delegateClass respondsToSelector:@selector(services)]) {
		return;
	}
	if (service == nil) {
		service = [AYAppDelegateService new];
		AYAddRemoteNotificationMethods(delegateClass);
	}
	// +[GDTApplicationDelegate services] and +addService: (drivers/apple_embedded/godot_app_delegate.h).
	// addService: ignores the call while Godot's list does not exist yet, so check membership.
	NSArray *services = ((NSArray * (*)(id, SEL))objc_msgSend)(delegateClass, @selector(services));
	if (![services containsObject:service]) {
		((void (*)(id, SEL, id))objc_msgSend)(delegateClass, @selector(addService:), service);
	}
}
