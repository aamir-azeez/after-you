#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AYPurchaseResult)(NSString *requestId, NSString *operation, NSString *payloadJson);
typedef void (^AYPurchaseError)(NSString *requestId, NSString *operation, NSString *code, NSString *message, BOOL cancelled);
typedef void (^AYPurchaseCustomer)(NSString *payloadJson);

/// RevenueCat on iOS with the Android bridge's contract: the same operations, payload schema 1,
/// and no receipt, transaction or original customer ID passed to GDScript. Modes: "app_store"
/// (appl_ key) in every build, "test_store" (test_ key) in debug builds only. The SDK is
/// reached through the Objective-C runtime and linked only when a store is configured;
/// without it every request fails with "not_configured". Main queue only.
@interface AYPurchases : NSObject

+ (instancetype)shared;
- (void)attachResult:(AYPurchaseResult)result error:(AYPurchaseError)error customer:(AYPurchaseCustomer)customer;
- (void)detach;

- (void)configureKey:(NSString *)publicKey player:(NSString *)playerId mode:(NSString *)mode requestId:(NSString *)requestId;
- (void)getOfferings:(NSString *)requestId;
- (void)getCustomerInfo:(NSString *)requestId;
- (void)purchaseOffering:(NSString *)offeringId package:(NSString *)packageId requestId:(NSString *)requestId;
- (void)restore:(NSString *)requestId;

@end

NS_ASSUME_NONNULL_END
