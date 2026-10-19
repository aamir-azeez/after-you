#include "after_you_ios.h"

#include <godot_cpp/classes/os.hpp>

#import <UIKit/UIKit.h>

#import "AYAppHooks.h"
#import "AYGameCenter.h"
#import "AYKeychainStore.h"
#import "AYNotifications.h"
#import "AYPolicy.h"
#import "AYPurchases.h"

using namespace godot;

static NSString *ay_ns(const String &p_value) {
	return [NSString stringWithUTF8String:p_value.utf8().get_data()] ?: @"";
}

static String ay_gd(NSString *p_value) {
	return String::utf8(p_value ? p_value.UTF8String : "");
}

static NSString *ay_json(NSDictionary *p_value) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:p_value options:0 error:nil];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

// Objective-C state lives here so the class header stays plain C++.
static AfterYouIOS *ay_instance = nullptr;
static dispatch_queue_t ay_storage_queue;
static AYKeychainStore *ay_keychain;
static NSMutableSet<NSString *> *ay_secure_pending;
static NSMutableArray *ay_observers;

static NSURL *ay_native_directory() {
	NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
	return [support URLByAppendingPathComponent:@"after-you-native"];
}

// Android keeps app data out of backups (allowBackup=false, noBackupFilesDir). Match it, so a
// restored save never arrives on a new phone without its Keychain credentials (ThisDeviceOnly).
static void ay_exclude_user_data_from_backup() {
	NSString *path = ay_ns(OS::get_singleton()->get_user_data_dir());
	if (path.length == 0) {
		return;
	}
	NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
	[[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
	[url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
}

static UIViewController *ay_top_controller() {
	UIWindow *window = nil;
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
			if (candidate.isKeyWindow || window == nil) {
				window = candidate;
			}
		}
	}
	UIViewController *controller = window.rootViewController;
	while (controller.presentedViewController != nil && !controller.presentedViewController.isBeingDismissed) {
		controller = controller.presentedViewController;
	}
	return controller;
}

AfterYouIOS::AfterYouIOS() {
	ay_instance = this;
	ay_storage_queue = dispatch_queue_create("com.aamirazeez.afteryou.secure", DISPATCH_QUEUE_SERIAL);
	ay_keychain = [[AYKeychainStore alloc] initWithService:@"com.aamirazeez.afteryou.secure" markerDirectory:ay_native_directory()];
	ay_secure_pending = [NSMutableSet set];
	ay_exclude_user_data_from_backup();

	// The early hook normally ran before main(); this covers a build where it could not.
	AYInstallAppHooks();

	[AYInviteLinkInbox shared].listener = ^{
		// A hint only: the game also polls on start and resume, and take is atomic.
		if (ay_instance && [[AYInviteLinkInbox shared] hasPending]) {
			ay_instance->emit_signal("invite_link_available");
		}
	};

	[[AYPurchases shared] attachResult:^(NSString *request_id, NSString *operation, NSString *payload) {
		if (ay_instance) {
			ay_instance->emit_signal("request_result", ay_gd(request_id), ay_gd(operation), ay_gd(payload));
		}
	}
			error:^(NSString *request_id, NSString *operation, NSString *code, NSString *message, BOOL cancelled) {
				if (ay_instance) {
					ay_instance->emit_signal("request_error", ay_gd(request_id), ay_gd(operation), ay_gd(code), ay_gd(message), (bool)cancelled);
				}
			}
			customer:^(NSString *payload) {
				if (ay_instance) {
					ay_instance->emit_signal("customer_info_updated", ay_gd(payload));
				}
			}];

	AYNotifications *notifications = [AYNotifications shared];
	[notifications attachResult:^(NSString *request_id, NSString *operation, NSString *payload) {
		if (ay_instance) {
			ay_instance->emit_signal("notification_result", ay_gd(request_id), ay_gd(operation), ay_gd(payload));
		}
	}
			error:^(NSString *request_id, NSString *operation, NSString *code) {
				if (ay_instance) {
					ay_instance->emit_signal("notification_error", ay_gd(request_id), ay_gd(operation), ay_gd(code));
				}
			}
			received:^(NSString *payload) {
				if (ay_instance) {
					ay_instance->emit_signal("notification_received", ay_gd(payload));
				}
			}
			tokenChanged:^(NSString *payload) {
				if (ay_instance) {
					ay_instance->emit_signal("notification_token_changed", ay_gd(payload));
				}
			}];

	AYGameCenter *games = [AYGameCenter shared];
	games.presenter = ^UIViewController * {
		return ay_top_controller();
	};
	[games attachResult:^(NSString *request_id, NSString *operation, NSString *payload) {
		if (ay_instance) {
			ay_instance->emit_signal("games_result", ay_gd(request_id), ay_gd(operation), ay_gd(payload));
		}
	}
			error:^(NSString *request_id, NSString *operation, NSString *code) {
				if (ay_instance) {
					ay_instance->emit_signal("games_error", ay_gd(request_id), ay_gd(operation), ay_gd(code));
				}
			}
			accountChanged:^(NSString *payload) {
				if (ay_instance) {
					ay_instance->emit_signal("games_account_changed", ay_gd(payload));
				}
			}];

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	ay_observers = [NSMutableArray array];
	[ay_observers addObject:[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		[[AYNotifications shared] setResumed:YES];
	}]];
	[ay_observers addObject:[center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		[[AYNotifications shared] setResumed:NO];
	}]];
	[notifications setResumed:[UIApplication sharedApplication].applicationState == UIApplicationStateActive];
	// The singleton is created while Godot sets up; its main loop runs from the next turn.
	dispatch_async(dispatch_get_main_queue(), ^{
		[[AYNotifications shared] setGodotReady:YES];
	});
}

AfterYouIOS::~AfterYouIOS() {
	for (id observer in ay_observers) {
		[[NSNotificationCenter defaultCenter] removeObserver:observer];
	}
	ay_observers = nil;
	[AYInviteLinkInbox shared].listener = nil;
	[[AYPurchases shared] detach];
	[[AYNotifications shared] detach];
	[[AYGameCenter shared] detach];
	[AYGameCenter shared].presenter = nil;
	if (ay_instance == this) {
		ay_instance = nullptr;
	}
}

void AfterYouIOS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("secure_put", "name", "value", "request_id"), &AfterYouIOS::secure_put);
	ClassDB::bind_method(D_METHOD("secure_get", "name", "request_id"), &AfterYouIOS::secure_get);
	ClassDB::bind_method(D_METHOD("secure_remove", "name", "request_id"), &AfterYouIOS::secure_remove);
	ClassDB::bind_method(D_METHOD("secure_copy_recovery", "player_id", "recovery_code", "request_id"), &AfterYouIOS::secure_copy_recovery);
	ClassDB::bind_method(D_METHOD("share_text", "text"), &AfterYouIOS::share_text);
	ClassDB::bind_method(D_METHOD("invite_link_take"), &AfterYouIOS::invite_link_take);
	ClassDB::bind_method(D_METHOD("configure", "public_key", "player_id", "mode", "request_id"), &AfterYouIOS::configure);
	ClassDB::bind_method(D_METHOD("get_offerings", "request_id"), &AfterYouIOS::get_offerings);
	ClassDB::bind_method(D_METHOD("get_customer_info", "request_id"), &AfterYouIOS::get_customer_info);
	ClassDB::bind_method(D_METHOD("purchase_package", "offering_id", "package_id", "request_id"), &AfterYouIOS::purchase_package);
	ClassDB::bind_method(D_METHOD("restore_purchases", "request_id"), &AfterYouIOS::restore_purchases);
	ClassDB::bind_method(D_METHOD("notification_set_categories", "turns", "hosting", "requests", "request_id"), &AfterYouIOS::notification_set_categories);
	ClassDB::bind_method(D_METHOD("notification_status", "request_id"), &AfterYouIOS::notification_status);
	ClassDB::bind_method(D_METHOD("notification_request_permission", "request_id"), &AfterYouIOS::notification_request_permission);
	ClassDB::bind_method(D_METHOD("notification_get_token", "request_id"), &AfterYouIOS::notification_get_token);
	ClassDB::bind_method(D_METHOD("notification_set_binding", "epoch", "token", "generation", "request_id"), &AfterYouIOS::notification_set_binding);
	ClassDB::bind_method(D_METHOD("notification_clear_binding", "request_id"), &AfterYouIOS::notification_clear_binding);
	ClassDB::bind_method(D_METHOD("notification_pending_route", "request_id"), &AfterYouIOS::notification_pending_route);
	ClassDB::bind_method(D_METHOD("notification_ack_route", "event_id", "request_id"), &AfterYouIOS::notification_ack_route);
	ClassDB::bind_method(D_METHOD("notification_disable", "request_id"), &AfterYouIOS::notification_disable);
	ClassDB::bind_method(D_METHOD("games_available"), &AfterYouIOS::games_available);
	ClassDB::bind_method(D_METHOD("games_status", "request_id"), &AfterYouIOS::games_status);
	ClassDB::bind_method(D_METHOD("games_sign_in", "request_id"), &AfterYouIOS::games_sign_in);
	ClassDB::bind_method(D_METHOD("games_credential", "web_client_id", "request_id"), &AfterYouIOS::games_credential);
	ClassDB::bind_method(D_METHOD("games_snapshot_open", "name", "request_id"), &AfterYouIOS::games_snapshot_open);
	ClassDB::bind_method(D_METHOD("games_snapshot_commit", "handle", "data", "description", "request_id"), &AfterYouIOS::games_snapshot_commit);
	ClassDB::bind_method(D_METHOD("games_snapshot_resolve", "handle", "data", "request_id"), &AfterYouIOS::games_snapshot_resolve);
	ClassDB::bind_method(D_METHOD("games_snapshot_discard", "handle", "request_id"), &AfterYouIOS::games_snapshot_discard);

	PropertyInfo id_info(Variant::STRING, "request_id");
	PropertyInfo operation_info(Variant::STRING, "operation");
	PropertyInfo payload_info(Variant::STRING, "payload_json");
	PropertyInfo code_info(Variant::STRING, "code");
	ADD_SIGNAL(MethodInfo("request_result", id_info, operation_info, payload_info));
	ADD_SIGNAL(MethodInfo("request_error", id_info, operation_info, code_info, PropertyInfo(Variant::STRING, "safe_message"), PropertyInfo(Variant::BOOL, "cancelled")));
	ADD_SIGNAL(MethodInfo("customer_info_updated", payload_info));
	ADD_SIGNAL(MethodInfo("secure_result", id_info, operation_info, payload_info));
	ADD_SIGNAL(MethodInfo("secure_error", id_info, operation_info, code_info));
	ADD_SIGNAL(MethodInfo("notification_result", id_info, operation_info, payload_info));
	ADD_SIGNAL(MethodInfo("notification_error", id_info, operation_info, code_info));
	ADD_SIGNAL(MethodInfo("notification_received", payload_info));
	ADD_SIGNAL(MethodInfo("notification_token_changed", payload_info));
	ADD_SIGNAL(MethodInfo("invite_link_available"));
	ADD_SIGNAL(MethodInfo("games_result", id_info, operation_info, payload_info));
	ADD_SIGNAL(MethodInfo("games_error", id_info, operation_info, code_info));
	ADD_SIGNAL(MethodInfo("games_account_changed", payload_info));
}

// MARK: Secure storage

static bool ay_begin_secure(NSString *p_id) {
	if (p_id.length < 1 || p_id.length > 128 || [ay_secure_pending containsObject:p_id]) {
		return false;
	}
	[ay_secure_pending addObject:p_id];
	return true;
}

static void ay_secure_finish(NSString *p_id, NSString *p_operation, NSDictionary *p_payload, NSString *p_error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (![ay_secure_pending containsObject:p_id]) {
			return;
		}
		[ay_secure_pending removeObject:p_id];
		if (!ay_instance) {
			return;
		}
		if (p_error) {
			ay_instance->emit_signal("secure_error", ay_gd(p_id), ay_gd(p_operation), ay_gd(p_error));
		} else {
			ay_instance->emit_signal("secure_result", ay_gd(p_id), ay_gd(p_operation), ay_gd(ay_json(p_payload)));
		}
	});
}

static void ay_storage(NSString *p_id, NSString *p_operation, NSString *p_name, NSDictionary * (^p_action)(void)) {
	if (!ay_begin_secure(p_id)) {
		return;
	}
	if (![AYPolicy validStorageName:p_name]) {
		ay_secure_finish(p_id, p_operation, nil, @"invalid_name");
		return;
	}
	dispatch_async(ay_storage_queue, ^{
		NSDictionary *payload = nil;
		@try {
			payload = p_action();
		} @catch (NSException *exception) {
			payload = nil;
		}
		ay_secure_finish(p_id, p_operation, payload, payload ? nil : @"secure_storage_unavailable");
	});
}

void AfterYouIOS::secure_put(const String &p_name, const String &p_value, const String &p_request_id) {
	NSString *name = ay_ns(p_name);
	NSString *value = ay_ns(p_value);
	ay_storage(ay_ns(p_request_id), @"put", name, ^NSDictionary * {
		return [ay_keychain putName:name value:value] ? @{ @"stored" : @YES } : nil;
	});
}

void AfterYouIOS::secure_get(const String &p_name, const String &p_request_id) {
	NSString *name = ay_ns(p_name);
	ay_storage(ay_ns(p_request_id), @"get", name, ^NSDictionary * {
		BOOL found = NO;
		BOOL failed = NO;
		NSString *value = [ay_keychain getName:name found:&found failed:&failed];
		if (failed) {
			return nil;
		}
		return @{ @"found" : @(found), @"value" : found ? value : [NSNull null] };
	});
}

void AfterYouIOS::secure_remove(const String &p_name, const String &p_request_id) {
	NSString *name = ay_ns(p_name);
	ay_storage(ay_ns(p_request_id), @"remove", name, ^NSDictionary * {
		return [ay_keychain removeName:name] ? @{ @"removed" : @YES } : nil;
	});
}

void AfterYouIOS::secure_copy_recovery(const String &p_player_id, const String &p_recovery_code, const String &p_request_id) {
	NSString *request_id = ay_ns(p_request_id);
	if (!ay_begin_secure(request_id)) {
		return;
	}
	NSString *text = [AYPolicy recoveryTextForPlayer:ay_ns(p_player_id) code:ay_ns(p_recovery_code)];
	if (text == nil) {
		ay_secure_finish(request_id, @"copy_recovery", nil, @"invalid_recovery_details");
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		@try {
			// Local only, so Universal Clipboard never sends it to another device, and gone after
			// two minutes. iOS has no sensitive-preview flag; the paste banner is the system's.
			[[UIPasteboard generalPasteboard] setItems:@[ @{ @"public.utf8-plain-text" : text } ]
											   options:@{ UIPasteboardOptionLocalOnly : @YES, UIPasteboardOptionExpirationDate : [NSDate dateWithTimeIntervalSinceNow:120] }];
			ay_secure_finish(request_id, @"copy_recovery", @{ @"copied" : @YES }, nil);
		} @catch (NSException *exception) {
			ay_secure_finish(request_id, @"copy_recovery", nil, @"clipboard_unavailable");
		}
	});
}

// MARK: Share and links

void AfterYouIOS::share_text(const String &p_text) {
	NSString *text = ay_ns(p_text);
	if ([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0 || text.length > 4096) {
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *host = ay_top_controller();
		if (host == nil) {
			return;
		}
		UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[ text ] applicationActivities:nil];
		// iPad presents the sheet as a popover, which needs an anchor.
		sheet.popoverPresentationController.sourceView = host.view;
		sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds), 1, 1);
		sheet.popoverPresentationController.permittedArrowDirections = 0;
		[host presentViewController:sheet animated:YES completion:nil];
	});
}

String AfterYouIOS::invite_link_take() {
	return ay_gd([[AYInviteLinkInbox shared] take]);
}

// MARK: Purchases

void AfterYouIOS::configure(const String &p_public_key, const String &p_player_id, const String &p_mode, const String &p_request_id) {
	[[AYPurchases shared] configureKey:ay_ns(p_public_key) player:ay_ns(p_player_id) mode:ay_ns(p_mode) requestId:ay_ns(p_request_id)];
}

void AfterYouIOS::get_offerings(const String &p_request_id) {
	[[AYPurchases shared] getOfferings:ay_ns(p_request_id)];
}

void AfterYouIOS::get_customer_info(const String &p_request_id) {
	[[AYPurchases shared] getCustomerInfo:ay_ns(p_request_id)];
}

void AfterYouIOS::purchase_package(const String &p_offering_id, const String &p_package_id, const String &p_request_id) {
	[[AYPurchases shared] purchaseOffering:ay_ns(p_offering_id) package:ay_ns(p_package_id) requestId:ay_ns(p_request_id)];
}

void AfterYouIOS::restore_purchases(const String &p_request_id) {
	[[AYPurchases shared] restore:ay_ns(p_request_id)];
}

// MARK: Notifications

void AfterYouIOS::notification_set_categories(bool p_turns, bool p_hosting, bool p_requests, const String &p_request_id) {
	[[AYNotifications shared] setCategoriesTurns:p_turns hosting:p_hosting requests:p_requests requestId:ay_ns(p_request_id)];
}

void AfterYouIOS::notification_status(const String &p_request_id) {
	[[AYNotifications shared] status:ay_ns(p_request_id)];
}

void AfterYouIOS::notification_request_permission(const String &p_request_id) {
	[[AYNotifications shared] requestPermission:ay_ns(p_request_id)];
}

void AfterYouIOS::notification_get_token(const String &p_request_id) {
	[[AYNotifications shared] getToken:ay_ns(p_request_id)];
}

void AfterYouIOS::notification_set_binding(const String &p_epoch, const String &p_token, int64_t p_generation, const String &p_request_id) {
	[[AYNotifications shared] setBindingEpoch:ay_ns(p_epoch) token:ay_ns(p_token) generation:p_generation requestId:ay_ns(p_request_id)];
}

void AfterYouIOS::notification_clear_binding(const String &p_request_id) {
	[[AYNotifications shared] clearBinding:ay_ns(p_request_id)];
}

void AfterYouIOS::notification_pending_route(const String &p_request_id) {
	[[AYNotifications shared] pendingRoute:ay_ns(p_request_id)];
}

void AfterYouIOS::notification_ack_route(const String &p_event_id, const String &p_request_id) {
	[[AYNotifications shared] acknowledge:ay_ns(p_event_id) requestId:ay_ns(p_request_id)];
}

void AfterYouIOS::notification_disable(const String &p_request_id) {
	[[AYNotifications shared] disable:ay_ns(p_request_id)];
}

// MARK: Game Center (same games_* contract as Android's Play Games)

bool AfterYouIOS::games_available() {
	return [[AYGameCenter shared] available];
}

void AfterYouIOS::games_status(const String &p_request_id) {
	[[AYGameCenter shared] status:ay_ns(p_request_id)];
}

void AfterYouIOS::games_sign_in(const String &p_request_id) {
	[[AYGameCenter shared] signIn:ay_ns(p_request_id)];
}

void AfterYouIOS::games_credential(const String &p_web_client_id, const String &p_request_id) {
	// Game Center needs no web client id; the argument keeps the method shared with Android.
	[[AYGameCenter shared] credential:ay_ns(p_request_id)];
}

void AfterYouIOS::games_snapshot_open(const String &p_name, const String &p_request_id) {
	[[AYGameCenter shared] snapshotOpen:ay_ns(p_name) requestId:ay_ns(p_request_id)];
}

void AfterYouIOS::games_snapshot_commit(const String &p_handle, const String &p_data, const String &p_description, const String &p_request_id) {
	[[AYGameCenter shared] snapshotCommit:ay_ns(p_handle) data:ay_ns(p_data) description:ay_ns(p_description) requestId:ay_ns(p_request_id)];
}

void AfterYouIOS::games_snapshot_resolve(const String &p_handle, const String &p_data, const String &p_request_id) {
	[[AYGameCenter shared] snapshotResolve:ay_ns(p_handle) data:ay_ns(p_data) requestId:ay_ns(p_request_id)];
}

void AfterYouIOS::games_snapshot_discard(const String &p_handle, const String &p_request_id) {
	[[AYGameCenter shared] snapshotDiscard:ay_ns(p_handle) requestId:ay_ns(p_request_id)];
}
