#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The monthly Full Journey Pollen hint's kind. It names no room.
extern NSString *const AYPollenKind;

/// Validation shared by every native service. The rules match the Android bridge
/// (BridgePolicy.kt, InviteLink.kt, NotificationPolicy.kt). Nothing here grants access.
@interface AYPolicy : NSObject

+ (BOOL)validStorageName:(NSString *)name;
// The identity's own secrets, kept in the Keychain when the app is removed and installed again:
// the identity, and a recovery or platform restore still waiting for its answer (it may hold the
// only copy of new credentials). Everything else starts fresh with the install.
+ (BOOL)keptAcrossReinstall:(NSString *)name;
+ (BOOL)validStorageValue:(NSString *)value;
+ (nullable NSString *)recoveryTextForPlayer:(NSString *)playerId code:(NSString *)recoveryCode;

/// Returns nil when the configuration is valid, otherwise the Android error code.
+ (nullable NSString *)configErrorForKey:(NSString *)apiKey player:(NSString *)playerId mode:(NSString *)mode allowTestStore:(BOOL)allowTestStore;

/// The invite link contract: https://aamirazeez.com/after-you/link#friend-... or ?c=friend-...
+ (BOOL)validInviteLink:(nullable NSString *)link;
/// The value to offer the inbox for one opened link: the URL text, "invalid", or nil to ignore.
+ (nullable NSString *)inboxValueForURL:(nullable NSURL *)url;
+ (NSString *)invalidLink;

+ (BOOL)validToken:(nullable NSString *)token;
+ (BOOL)validEpoch:(nullable NSString *)epoch;
+ (BOOL)validEventId:(nullable NSString *)eventId;
/// Accepts only the agreed hint schema. APNs and FCM keys ("aps", "gcm.*", "google.*") are
/// ignored; every remaining key must be one of the hint fields. Returns the canonical fields.
+ (nullable NSDictionary<NSString *, NSString *> *)notificationFromPayload:(NSDictionary *)payload;
/// A validated decimal amount with its thousands always grouped by commas ("4500" -> "4,500"), whatever the locale.
+ (NSString *)groupedAmount:(NSString *)digits;
/// A shared file's name as Android's ExportFiles.safeName makes it: lowercase letters, digits,
/// dot, dash and underscore, at most 96 characters, or nil.
+ (nullable NSString *)exportFileName:(NSString *)name;

/// What iCloud backup leaves out of the game's user files, relative to that folder: the same
/// folders Android's backup rules exclude (after_you_full_backup_rules.xml: device-bound room
/// state, photos, safety data, cloud save staging), Godot's own caches, and this phone's platform
/// games bookkeeping (it names the identity linked on this phone). Credentials are in the Keychain.
+ (NSArray<NSString *> *)backupExcludedFolders;
+ (NSArray<NSString *> *)backupExcludedFiles;
/// Lets iCloud back up the user folder (clearing the whole-folder exclusion older builds set) and
/// marks only the excluded items. Folders are made first so their mark holds; files are marked
/// when present and again on every call, as a rewrite replaces the file and drops its mark.
+ (void)applyBackupRulesAt:(NSURL *)root;

/// Public Firebase configuration from GoogleService-Info.plist, checked like Android's.
+ (BOOL)validFirebaseOptions:(NSDictionary *)options bundleId:(NSString *)bundleId;

@end

NS_ASSUME_NONNULL_END
