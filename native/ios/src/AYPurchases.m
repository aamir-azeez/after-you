#import "AYPurchases.h"

// Compiled against the RevenueCat headers for types, selectors and enum values. Every class
// object comes from NSClassFromString and this file is built with -fno-autolink, so nothing
// here forces RevenueCat to be linked. Builds without a store simply lack the classes.
#import <RevenueCat/RevenueCat-Swift.h>

#import "AYPolicy.h"

// Native purchase text, the same wording as the Android PlayerCopy entries.
static NSString *const AYCopyStoreFailed = @"The store request could not complete. Please try again.";
static NSString *const AYCopyNotConfigured = @"This build does not have purchases configured.";
static NSString *const AYCopyCouldNotStart = @"The store request could not start.";
static NSString *const AYCopyInvalidSettings = @"The purchase settings for this store are invalid.";
static NSString *const AYCopyRestartToChange = @"Restart the app before changing purchase identity or store.";
static NSString *const AYCopyFinishDialog = @"Complete the existing store dialog.";
static NSString *const AYCopyRefreshFirst = @"Refresh the store before purchasing.";
static NSString *const AYCopyPurchaseNotStarted = @"The purchase was not able to begin.";
static NSString *const AYCopyCancelled = @"Purchase cancelled.";

static NSString *AYJsonText(NSDictionary *value) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

static int64_t AYMillis(NSDate *date) {
	return (int64_t)(date.timeIntervalSince1970 * 1000.0);
}

// Android enum names, so the GDScript validators read both platforms the same way.
static NSString *AYStoreName(RCStore store) {
	switch (store) {
		case RCAppStore: return @"APP_STORE";
		case RCMacAppStore: return @"MAC_APP_STORE";
		case RCPlayStore: return @"PLAY_STORE";
		case RCStripe: return @"STRIPE";
		case RCPromotional: return @"PROMOTIONAL";
		case RCAmazon: return @"AMAZON";
		case RCBilling: return @"RC_BILLING";
		case RCExternal: return @"EXTERNAL";
		case RCPaddle: return @"PADDLE";
		case RCTestStore: return @"TEST_STORE";
		case RCGalaxy: return @"GALAXY";
		default: return @"UNKNOWN_STORE";
	}
}

static NSString *AYPackageTypeName(RCPackageType type) {
	switch (type) {
		case RCPackageTypeCustom: return @"CUSTOM";
		case RCPackageTypeLifetime: return @"LIFETIME";
		case RCPackageTypeAnnual: return @"ANNUAL";
		case RCPackageTypeSixMonth: return @"SIX_MONTH";
		case RCPackageTypeThreeMonth: return @"THREE_MONTH";
		case RCPackageTypeTwoMonth: return @"TWO_MONTH";
		case RCPackageTypeMonthly: return @"MONTHLY";
		case RCPackageTypeWeekly: return @"WEEKLY";
		default: return @"UNKNOWN";
	}
}

static NSString *AYVerificationName(RCVerificationResult result) {
	switch (result) {
		case RCVerificationResultVerified: return @"VERIFIED";
		case RCVerificationResultVerifiedOnDevice: return @"VERIFIED_ON_DEVICE";
		case RCVerificationResultFailed: return @"FAILED";
		default: return @"NOT_REQUESTED";
	}
}

@interface AYPurchases () <RCPurchasesDelegate>
@end

@implementation AYPurchases {
	AYPurchaseResult _resultSink;
	AYPurchaseError _errorSink;
	AYPurchaseCustomer _customerSink;
	NSMutableSet<NSString *> *_pending;
	BOOL _configured;
	NSString *_configuredKey;
	NSString *_configuredPlayer;
	NSString *_configuredMode;
	BOOL _purchaseInProgress;
	NSMutableDictionary<NSString *, RCPackage *> *_packages;
}

+ (instancetype)shared {
	static AYPurchases *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [AYPurchases new];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_pending = [NSMutableSet set];
		_packages = [NSMutableDictionary dictionary];
		_configuredKey = @"";
		_configuredPlayer = @"";
		_configuredMode = @"";
	}
	return self;
}

- (void)attachResult:(AYPurchaseResult)result error:(AYPurchaseError)error customer:(AYPurchaseCustomer)customer {
	_resultSink = [result copy];
	_errorSink = [error copy];
	_customerSink = [customer copy];
}

- (void)detach {
	_resultSink = nil;
	_errorSink = nil;
	_customerSink = nil;
	[_pending removeAllObjects];
}

+ (BOOL)allowTestStore {
#ifdef DEBUG_ENABLED
	return YES;
#else
	return NO;
#endif
}

- (Class)sdk {
	return NSClassFromString(@"RCPurchases");
}

- (BOOL)begin:(NSString *)requestId {
	if (requestId.length < 1 || requestId.length > 128 || [_pending containsObject:requestId]) {
		return NO;
	}
	[_pending addObject:requestId];
	return YES;
}

- (void)succeed:(NSString *)requestId operation:(NSString *)operation payload:(NSDictionary *)payload {
	if ([_pending containsObject:requestId]) {
		[_pending removeObject:requestId];
		if (_resultSink) {
			_resultSink(requestId, operation, AYJsonText(payload));
		}
	}
}

- (void)fail:(NSString *)requestId operation:(NSString *)operation code:(NSString *)code message:(NSString *)message cancelled:(BOOL)cancelled {
	if ([_pending containsObject:requestId]) {
		[_pending removeObject:requestId];
		if (_errorSink) {
			_errorSink(requestId, operation, code, message, cancelled);
		}
	}
}

- (void)sdkFail:(NSString *)requestId operation:(NSString *)operation error:(NSError *)error cancelled:(BOOL)cancelled {
	// The SDK's own message may contain URLs or account identifiers. Forward only its category.
	NSString *code = [NSString stringWithFormat:@"revenuecat_%ld", (long)error.code];
	[self fail:requestId operation:operation code:code message:cancelled ? AYCopyCancelled : AYCopyStoreFailed cancelled:cancelled];
}

- (BOOL)ready {
	Class sdk = [self sdk];
	if (!_configured || sdk == Nil || [AYPolicy configErrorForKey:_configuredKey player:_configuredPlayer mode:_configuredMode allowTestStore:[AYPurchases allowTestStore]] != nil) {
		return NO;
	}
	if (![sdk isConfigured]) {
		return NO;
	}
	RCPurchases *purchases = [sdk sharedPurchases];
	return [purchases.appUserID isEqualToString:_configuredPlayer];
}

/// Like the Android onUi helper: dedupe the request, then run on the main queue.
- (void)run:(NSString *)requestId operation:(NSString *)operation needsConfiguration:(BOOL)needsConfiguration work:(void (^)(void))work {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (![self begin:requestId]) {
			return;
		}
		if (needsConfiguration && ![self ready]) {
			[self fail:requestId operation:operation code:@"not_configured" message:AYCopyNotConfigured cancelled:NO];
			return;
		}
		@try {
			work();
		} @catch (NSException *exception) {
			[self fail:requestId operation:operation code:@"native_request_failed" message:AYCopyCouldNotStart cancelled:NO];
		}
	});
}

- (void)configureKey:(NSString *)publicKey player:(NSString *)playerId mode:(NSString *)mode requestId:(NSString *)requestId {
	[self run:requestId operation:@"configure" needsConfiguration:NO work:^{
		Class sdk = [self sdk];
		if (sdk == Nil) {
			[self fail:requestId operation:@"configure" code:@"not_configured" message:AYCopyNotConfigured cancelled:NO];
			return;
		}
		NSString *invalid = [AYPolicy configErrorForKey:publicKey player:playerId mode:mode allowTestStore:[AYPurchases allowTestStore]];
		if (invalid != nil) {
			[self fail:requestId operation:@"configure" code:invalid message:AYCopyInvalidSettings cancelled:NO];
			return;
		}
		BOOL sdkConfigured = [sdk isConfigured];
		// Never adopt a preconfigured SDK whose store, key or identity this bridge did not validate.
		if (!self->_configured && sdkConfigured) {
			[self fail:requestId operation:@"configure" code:@"configuration_locked" message:AYCopyNotConfigured cancelled:NO];
			return;
		}
		if (self->_configured && !sdkConfigured) {
			[self fail:requestId operation:@"configure" code:@"not_configured" message:AYCopyNotConfigured cancelled:NO];
			return;
		}
		if (self->_configured) {
			if (![self->_configuredKey isEqualToString:publicKey] || ![self->_configuredPlayer isEqualToString:playerId] || ![self->_configuredMode isEqualToString:mode]) {
				[self fail:requestId operation:@"configure" code:@"configuration_locked" message:AYCopyRestartToChange cancelled:NO];
			} else if (![self ready]) {
				[self fail:requestId operation:@"configure" code:@"not_configured" message:AYCopyNotConfigured cancelled:NO];
			} else {
				[self refreshCustomer:requestId operation:@"configure"];
			}
			return;
		}
		// The SDK selects its store from the validated key; Test Store is debug-only.
		[sdk setLogLevel:RCLogLevelError];
		[sdk setLogHandler:^(RCLogLevel level, NSString *message) {
		}];
		RCConfigurationBuilder *builder = [[NSClassFromString(@"RCConfigurationBuilder") alloc] initWithAPIKey:publicKey];
		builder = [[builder withAppUserID:playerId] withDiagnosticsEnabled:NO];
		[sdk configureWithConfiguration:[builder build]];
		self->_configured = YES;
		self->_configuredKey = [publicKey copy];
		self->_configuredPlayer = [playerId copy];
		self->_configuredMode = [mode copy];
		[sdk sharedPurchases].delegate = self;
		[self refreshCustomer:requestId operation:@"configure"];
	}];
}

// RCPurchasesDelegate.
- (void)purchases:(RCPurchases *)purchases receivedUpdatedCustomerInfo:(RCCustomerInfo *)customerInfo {
	dispatch_async(dispatch_get_main_queue(), ^{
		if ([self ready] && self->_customerSink) {
			self->_customerSink(AYJsonText([self customerPayload:customerInfo]));
		}
	});
}

- (void)refreshCustomer:(NSString *)requestId operation:(NSString *)operation {
	[[[self sdk] sharedPurchases] getCustomerInfoWithFetchPolicy:RCCacheFetchPolicyFetchCurrent completion:^(RCCustomerInfo *info, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (info == nil || error != nil) {
				[self sdkFail:requestId operation:operation error:error cancelled:NO];
			} else {
				[self customerSuccess:requestId operation:operation info:info];
			}
		});
	}];
}

- (void)customerSuccess:(NSString *)requestId operation:(NSString *)operation info:(RCCustomerInfo *)info {
	if ([self ready]) {
		[self succeed:requestId operation:operation payload:[self customerPayload:info]];
	} else {
		[self fail:requestId operation:operation code:@"not_configured" message:AYCopyNotConfigured cancelled:NO];
	}
}

- (void)getOfferings:(NSString *)requestId {
	[self run:requestId operation:@"get_offerings" needsConfiguration:YES work:^{
		[[[self sdk] sharedPurchases] getOfferingsWithCompletion:^(RCOfferings *offerings, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (offerings == nil || error != nil) {
					[self sdkFail:requestId operation:@"get_offerings" error:error cancelled:NO];
				} else if ([self ready]) {
					[self->_packages removeAllObjects];
					[self succeed:requestId operation:@"get_offerings" payload:[self offeringsPayload:offerings]];
				} else {
					[self fail:requestId operation:@"get_offerings" code:@"not_configured" message:AYCopyNotConfigured cancelled:NO];
				}
			});
		}];
	}];
}

- (void)getCustomerInfo:(NSString *)requestId {
	[self run:requestId operation:@"get_customer_info" needsConfiguration:YES work:^{
		[self refreshCustomer:requestId operation:@"get_customer_info"];
	}];
}

- (void)purchaseOffering:(NSString *)offeringId package:(NSString *)packageId requestId:(NSString *)requestId {
	[self run:requestId operation:@"purchase_package" needsConfiguration:YES work:^{
		if (self->_purchaseInProgress) {
			[self fail:requestId operation:@"purchase_package" code:@"purchase_in_progress" message:AYCopyFinishDialog cancelled:NO];
			return;
		}
		RCPackage *selected = self->_packages[[NSString stringWithFormat:@"%@%C%@", offeringId, (unichar)0, packageId]];
		if (selected == nil) {
			[self fail:requestId operation:@"purchase_package" code:@"package_not_loaded" message:AYCopyRefreshFirst cancelled:NO];
			return;
		}
		self->_purchaseInProgress = YES;
		@try {
			[[[self sdk] sharedPurchases] purchasePackage:selected withCompletion:^(RCStoreTransaction *transaction, RCCustomerInfo *info, NSError *error, BOOL userCancelled) {
				dispatch_async(dispatch_get_main_queue(), ^{
					self->_purchaseInProgress = NO;
					if (info == nil || error != nil) {
						[self sdkFail:requestId operation:@"purchase_package" error:error cancelled:userCancelled];
					} else {
						[self customerSuccess:requestId operation:@"purchase_package" info:info];
					}
				});
			}];
		} @catch (NSException *exception) {
			self->_purchaseInProgress = NO;
			[self fail:requestId operation:@"purchase_package" code:@"purchase_failed" message:AYCopyPurchaseNotStarted cancelled:NO];
		}
	}];
}

- (void)restore:(NSString *)requestId {
	[self run:requestId operation:@"restore_purchases" needsConfiguration:YES work:^{
		if (self->_purchaseInProgress) {
			[self fail:requestId operation:@"restore_purchases" code:@"purchase_in_progress" message:AYCopyFinishDialog cancelled:NO];
			return;
		}
		[[[self sdk] sharedPurchases] restorePurchasesWithCompletion:^(RCCustomerInfo *info, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (info == nil || error != nil) {
					[self sdkFail:requestId operation:@"restore_purchases" error:error cancelled:NO];
				} else {
					[self customerSuccess:requestId operation:@"restore_purchases" info:info];
				}
			});
		}];
	}];
}

- (NSDictionary *)offeringsPayload:(RCOfferings *)offerings {
	NSMutableArray *items = [NSMutableArray array];
	for (RCOffering *offering in offerings.all.allValues) {
		NSMutableArray *choices = [NSMutableArray array];
		for (RCPackage *item in offering.availablePackages) {
			_packages[[NSString stringWithFormat:@"%@%C%@", offering.identifier, (unichar)0, item.identifier]] = item;
			RCStoreProduct *product = item.storeProduct;
			NSDecimalNumber *micros = [product.price decimalNumberByMultiplyingByPowerOf10:6];
			[choices addObject:@{
				@"id" : item.identifier,
				@"product_id" : product.productIdentifier,
				@"type" : AYPackageTypeName(item.packageType),
				@"title" : product.localizedTitle ?: @"",
				@"description" : product.localizedDescription ?: @"",
				@"price" : product.localizedPriceString ?: @"",
				@"currency" : product.currencyCode ?: @"",
				@"price_micros" : @(micros.longLongValue),
			}];
		}
		[items addObject:@{ @"id" : offering.identifier, @"packages" : choices }];
	}
	return @{
		@"schema_version" : @1,
		@"mode" : _configuredMode,
		@"current_id" : offerings.current.identifier ?: [NSNull null],
		@"offerings" : items,
	};
}

- (NSDictionary *)customerPayload:(RCCustomerInfo *)info {
	NSMutableDictionary *entitlements = [NSMutableDictionary dictionary];
	[info.entitlements.all enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, RCEntitlementInfo *item, BOOL *stop) {
		entitlements[identifier] = @{
			@"active" : @(item.isActive),
			@"product_id" : item.productIdentifier,
			@"store" : AYStoreName(item.store),
			@"sandbox" : @(item.isSandbox),
			@"expires_at_ms" : item.expirationDate ? @(AYMillis(item.expirationDate)) : [NSNull null],
			@"verification" : AYVerificationName(item.verification),
		};
	}];
	return @{
		@"schema_version" : @1,
		@"mode" : _configuredMode,
		@"player_id" : _configuredPlayer,
		@"request_date_ms" : @(AYMillis(info.requestDate)),
		@"entitlements" : entitlements,
	};
}

@end
