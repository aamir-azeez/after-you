#import "AYNotificationStore.h"

#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>

#import "AYPolicy.h"

static const int64_t AYRetentionMs = 7LL * 24 * 60 * 60 * 1000;
static const int AYMaxEvents = 256;
static const int AYMaxRooms = 128;

@implementation AYNotificationRegistration
- (BOOL)pending {
	return self.optedIn && (self.tokenHash.length == 0 || ![self.registeredHash isEqualToString:self.tokenHash] || self.epoch.length == 0);
}
@end

/// The stored form of one hint: the same six values as Android's TurnNotification.
@interface AYStoredEvent : NSObject
@property(nonatomic, copy) NSString *eventId;
@property(nonatomic, copy) NSString *kind;
@property(nonatomic, copy) NSString *roomId;
@property(nonatomic, copy) NSString *family;
@property(nonatomic) int64_t revision;
@property(nonatomic, copy) NSString *epoch;
@end

@implementation AYStoredEvent

+ (instancetype)fromFields:(NSDictionary<NSString *, NSString *> *)fields {
	AYStoredEvent *event = [AYStoredEvent new];
	event.eventId = fields[@"event_id"];
	event.kind = fields[@"kind"];
	event.roomId = fields[@"room_id"];
	event.family = fields[@"room_family"];
	BOOL hosting = [event.kind isEqualToString:@"friend_room_available"];
	event.revision = [fields[hosting ? @"publication_epoch" : @"revision"] longLongValue];
	event.epoch = fields[@"binding_epoch"];
	return event;
}

- (NSDictionary<NSString *, NSString *> *)fields {
	NSString *revision = [NSString stringWithFormat:@"%lld", self.revision];
	if ([self.kind isEqualToString:@"friend_room_available"]) {
		NSRange last = [self.eventId rangeOfString:@"_" options:NSBackwardsSearch];
		NSString *host = last.location == NSNotFound ? self.eventId : [self.eventId substringToIndex:last.location];
		return @{ @"schema_version" : @"1", @"event_id" : self.eventId, @"kind" : self.kind, @"host_id" : host, @"room_id" : self.roomId,
			@"room_family" : self.family, @"publication_epoch" : revision, @"binding_epoch" : self.epoch };
	}
	return @{ @"schema_version" : @"1", @"event_id" : self.eventId, @"kind" : self.kind, @"room_id" : self.roomId,
		@"room_family" : self.family, @"revision" : revision, @"binding_epoch" : self.epoch };
}

- (BOOL)isEqualToEvent:(AYStoredEvent *)other {
	return [self.eventId isEqualToString:other.eventId] && [self.kind isEqualToString:other.kind] && [self.roomId isEqualToString:other.roomId] &&
			[self.family isEqualToString:other.family] && self.revision == other.revision && [self.epoch isEqualToString:other.epoch];
}

@end

@implementation AYNotificationStore {
	sqlite3 *_db;
}

+ (NSString *)sha256:(NSString *)value {
	NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
		[hex appendFormat:@"%02x", digest[i]];
	}
	return hex;
}

+ (instancetype)openInDirectory:(NSURL *)directory {
	NSFileManager *files = [NSFileManager defaultManager];
	if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]) {
		return nil;
	}
	[directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
	AYNotificationStore *store = [AYNotificationStore new];
	NSString *path = [directory URLByAppendingPathComponent:@"events.db"].path;
	if (sqlite3_open_v2(path.fileSystemRepresentation, &store->_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
		return nil;
	}
	return [store migrate] ? store : nil;
}

- (void)dealloc {
	if (_db) {
		sqlite3_close(_db);
	}
}

// MARK: SQL helpers

- (sqlite3_stmt *)prepare:(NSString *)sql arguments:(NSArray *)arguments {
	sqlite3_stmt *statement = NULL;
	if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) {
		return NULL;
	}
	for (int i = 0; i < (int)arguments.count; i++) {
		id value = arguments[i];
		if ([value isKindOfClass:[NSNumber class]]) {
			sqlite3_bind_int64(statement, i + 1, [value longLongValue]);
		} else {
			sqlite3_bind_text(statement, i + 1, [value UTF8String], -1, SQLITE_TRANSIENT);
		}
	}
	return statement;
}

- (BOOL)run:(NSString *)sql arguments:(NSArray *)arguments {
	sqlite3_stmt *statement = [self prepare:sql arguments:arguments];
	if (statement == NULL) {
		return NO;
	}
	int status = sqlite3_step(statement);
	sqlite3_finalize(statement);
	return status == SQLITE_DONE || status == SQLITE_ROW;
}

- (NSArray<NSArray *> *)rows:(NSString *)sql arguments:(NSArray *)arguments {
	sqlite3_stmt *statement = [self prepare:sql arguments:arguments];
	if (statement == NULL) {
		return nil;
	}
	NSMutableArray *rows = [NSMutableArray array];
	while (sqlite3_step(statement) == SQLITE_ROW) {
		NSMutableArray *row = [NSMutableArray array];
		for (int column = 0; column < sqlite3_column_count(statement); column++) {
			if (sqlite3_column_type(statement, column) == SQLITE_INTEGER) {
				[row addObject:@(sqlite3_column_int64(statement, column))];
			} else {
				const unsigned char *text = sqlite3_column_text(statement, column);
				[row addObject:text ? [NSString stringWithUTF8String:(const char *)text] : @""];
			}
		}
		[rows addObject:row];
	}
	sqlite3_finalize(statement);
	return rows;
}

- (BOOL)transaction:(BOOL (^)(void))work {
	if (![self run:@"BEGIN IMMEDIATE" arguments:@[]]) {
		return NO;
	}
	if (work()) {
		return [self run:@"COMMIT" arguments:@[]];
	}
	[self run:@"ROLLBACK" arguments:@[]];
	return NO;
}

- (BOOL)migrate {
	NSArray *version = [self rows:@"PRAGMA user_version" arguments:@[]];
	int64_t current = version.count ? [version[0][0] longLongValue] : -1;
	if (current == 1) {
		return YES;
	}
	if (current != 0) {
		// Never silently discard an unknown local schema.
		return NO;
	}
	return [self transaction:^BOOL {
		return [self run:@"CREATE TABLE registration (id INTEGER PRIMARY KEY CHECK(id=1), opted INTEGER NOT NULL, epoch TEXT NOT NULL, token_hash TEXT NOT NULL, registered_hash TEXT NOT NULL, generation INTEGER NOT NULL)" arguments:@[]] &&
				[self run:@"INSERT INTO registration VALUES (1,0,'','','',0)" arguments:@[]] &&
				[self run:@"CREATE TABLE events (event_id TEXT PRIMARY KEY, kind TEXT NOT NULL, room_id TEXT NOT NULL, family TEXT NOT NULL, revision INTEGER NOT NULL, epoch TEXT NOT NULL, received INTEGER NOT NULL, posted INTEGER NOT NULL DEFAULT 0, tapped INTEGER NOT NULL DEFAULT 0, acked INTEGER NOT NULL DEFAULT 0)" arguments:@[]] &&
				[self run:@"CREATE TABLE watermark (kind TEXT NOT NULL, room_id TEXT NOT NULL, family TEXT NOT NULL, revision INTEGER NOT NULL, event_id TEXT NOT NULL, received INTEGER NOT NULL, PRIMARY KEY(kind,room_id,family))" arguments:@[]] &&
				// Android keeps these switches in SharedPreferences; here they share the database.
				[self run:@"CREATE TABLE categories (id INTEGER PRIMARY KEY CHECK(id=1), turns INTEGER NOT NULL, hosting INTEGER NOT NULL, requests INTEGER NOT NULL, saved INTEGER NOT NULL)" arguments:@[]] &&
				[self run:@"INSERT INTO categories VALUES (1,1,0,0,0)" arguments:@[]] &&
				[self run:@"PRAGMA user_version=1" arguments:@[]];
	}];
}

// MARK: Registration

- (AYNotificationRegistration *)registration {
	NSArray *rows = [self rows:@"SELECT opted,epoch,token_hash,registered_hash,generation FROM registration WHERE id=1" arguments:@[]];
	if (rows.count != 1) {
		return nil;
	}
	NSArray *row = rows[0];
	AYNotificationRegistration *state = [AYNotificationRegistration new];
	state.optedIn = [row[0] longLongValue] != 0;
	state.epoch = row[1];
	state.tokenHash = row[2];
	state.registeredHash = row[3];
	state.generation = [row[4] longLongValue];
	return state;
}

- (AYNotificationRegistration *)setOptedIn:(BOOL)enabled {
	BOOL done = [self transaction:^BOOL {
		if (!enabled) {
			return [self run:@"UPDATE registration SET opted=0,epoch='',registered_hash='',generation=generation+1 WHERE id=1" arguments:@[]] &&
					[self run:@"DELETE FROM events" arguments:@[]] && [self run:@"DELETE FROM watermark" arguments:@[]];
		}
		return [self run:@"UPDATE registration SET opted=1,generation=generation+1 WHERE id=1 AND opted=0" arguments:@[]];
	}];
	return done ? [self registration] : nil;
}

- (BOOL)noteToken:(NSString *)token {
	if (![AYPolicy validToken:token]) {
		return NO;
	}
	NSString *digest = [AYNotificationStore sha256:token];
	return [self run:@"UPDATE registration SET token_hash=? WHERE id=1 AND token_hash<>?" arguments:@[ digest, digest ]];
}

- (AYNotificationRegistration *)clearBinding {
	BOOL done = [self transaction:^BOOL {
		return [self run:@"UPDATE registration SET epoch='',registered_hash='',generation=generation+1 WHERE id=1" arguments:@[]] &&
				[self run:@"DELETE FROM events" arguments:@[]] && [self run:@"DELETE FROM watermark" arguments:@[]];
	}];
	return done ? [self registration] : nil;
}

- (BOOL)bindEpoch:(NSString *)epoch token:(NSString *)token generation:(int64_t)generation {
	if (![AYPolicy validEpoch:epoch] || ![AYPolicy validToken:token]) {
		return NO;
	}
	AYNotificationRegistration *state = [self registration];
	NSString *digest = [AYNotificationStore sha256:token];
	if (state == nil || !state.optedIn || state.generation != generation || ![state.tokenHash isEqualToString:digest]) {
		return NO;
	}
	return [self transaction:^BOOL {
		if (![state.epoch isEqualToString:epoch] && !([self run:@"DELETE FROM events" arguments:@[]] && [self run:@"DELETE FROM watermark" arguments:@[]])) {
			return NO;
		}
		return [self run:@"UPDATE registration SET epoch=?,registered_hash=? WHERE id=1" arguments:@[ epoch, digest ]];
	}];
}

// MARK: Events

- (AYStoredEvent *)eventFromRow:(NSArray *)row {
	AYStoredEvent *event = [AYStoredEvent new];
	event.eventId = row[0];
	event.kind = row[1];
	event.roomId = row[2];
	event.family = row[3];
	event.revision = [row[4] longLongValue];
	event.epoch = row[5];
	return event;
}

- (BOOL)isLatest:(AYStoredEvent *)event {
	NSArray *rows = [self rows:@"SELECT event_id FROM watermark WHERE kind=? AND room_id=? AND family=?" arguments:@[ event.kind, event.roomId, event.family ]];
	return rows.count > 0 && [rows[0][0] isEqualToString:event.eventId];
}

- (BOOL)prune:(int64_t)now {
	NSNumber *cutoff = @(now - AYRetentionMs);
	return [self run:@"DELETE FROM events WHERE received<?" arguments:@[ cutoff ]] &&
			[self run:@"DELETE FROM watermark WHERE received<?" arguments:@[ cutoff ]] &&
			[self run:[NSString stringWithFormat:@"DELETE FROM events WHERE event_id IN (SELECT event_id FROM events ORDER BY received DESC,event_id LIMIT -1 OFFSET %d)", AYMaxEvents] arguments:@[]] &&
			[self run:[NSString stringWithFormat:@"DELETE FROM watermark WHERE rowid IN (SELECT rowid FROM watermark ORDER BY received DESC,rowid DESC LIMIT -1 OFFSET %d)", AYMaxRooms] arguments:@[]];
}

- (BOOL)receive:(NSDictionary<NSString *, NSString *> *)fields now:(int64_t)now {
	AYStoredEvent *event = [AYStoredEvent fromFields:fields];
	AYNotificationRegistration *state = [self registration];
	if (state == nil || !state.optedIn || ![state.epoch isEqualToString:event.epoch]) {
		return NO;
	}
	__block BOOL accepted = NO;
	BOOL committed = [self transaction:^BOOL {
		if (![self prune:now]) {
			return NO;
		}
		NSArray *existing = [self rows:@"SELECT event_id,kind,room_id,family,revision,epoch,posted FROM events WHERE event_id=?" arguments:@[ event.eventId ]];
		if (existing.count > 0) {
			accepted = [[self eventFromRow:existing[0]] isEqualToEvent:event] && [existing[0][6] longLongValue] == 0 && [self isLatest:event];
			return YES;
		}
		NSArray *mark = [self rows:@"SELECT revision FROM watermark WHERE kind=? AND room_id=? AND family=?" arguments:@[ event.kind, event.roomId, event.family ]];
		if (mark.count > 0 && [mark[0][0] longLongValue] >= event.revision) {
			return YES;
		}
		if (![self run:@"INSERT INTO events (event_id,kind,room_id,family,revision,epoch,received) VALUES (?,?,?,?,?,?,?)" arguments:@[ event.eventId, event.kind, event.roomId, event.family, @(event.revision), event.epoch, @(now) ]] ||
				![self run:@"INSERT OR REPLACE INTO watermark (kind,room_id,family,revision,event_id,received) VALUES (?,?,?,?,?,?)" arguments:@[ event.kind, event.roomId, event.family, @(event.revision), event.eventId, @(now) ]] ||
				![self prune:now]) {
			return NO;
		}
		accepted = YES;
		return YES;
	}];
	return committed && accepted;
}

- (void)markPosted:(NSDictionary<NSString *, NSString *> *)fields {
	[self run:@"UPDATE events SET posted=1 WHERE event_id=? AND epoch=?" arguments:@[ fields[@"event_id"], fields[@"binding_epoch"] ]];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)pendingPosts:(int64_t)now {
	[self prune:now];
	AYNotificationRegistration *state = [self registration];
	if (state == nil || !state.optedIn || state.epoch.length == 0) {
		return @[];
	}
	NSMutableArray *result = [NSMutableArray array];
	for (NSArray *row in [self rows:@"SELECT event_id,kind,room_id,family,revision,epoch FROM events WHERE posted=0 AND epoch=? ORDER BY received DESC,event_id LIMIT 32" arguments:@[ state.epoch ]]) {
		AYStoredEvent *event = [self eventFromRow:row];
		if ([self isLatest:event]) {
			[result addObject:event.fields];
		}
	}
	return result;
}

- (BOOL)markTapped:(NSString *)eventId {
	if (![AYPolicy validEventId:eventId]) {
		return NO;
	}
	AYNotificationRegistration *state = [self registration];
	if (state == nil || !state.optedIn || state.epoch.length == 0) {
		return NO;
	}
	return [self run:@"UPDATE events SET tapped=1 WHERE event_id=? AND epoch=? AND acked=0" arguments:@[ eventId, state.epoch ]] && sqlite3_changes(_db) == 1;
}

- (NSDictionary<NSString *, NSString *> *)pendingRoute:(int64_t)now {
	[self prune:now];
	AYNotificationRegistration *state = [self registration];
	if (state == nil || !state.optedIn || state.epoch.length == 0) {
		return nil;
	}
	NSArray *rows = [self rows:@"SELECT event_id,kind,room_id,family,revision,epoch FROM events WHERE tapped=1 AND acked=0 AND epoch=? ORDER BY received DESC,event_id LIMIT 1" arguments:@[ state.epoch ]];
	return rows.count ? [self eventFromRow:rows[0]].fields : nil;
}

- (BOOL)acknowledge:(NSString *)eventId {
	if (![AYPolicy validEventId:eventId]) {
		return NO;
	}
	AYNotificationRegistration *state = [self registration];
	if (state == nil) {
		return NO;
	}
	return [self run:@"UPDATE events SET acked=1 WHERE event_id=? AND epoch=? AND tapped=1" arguments:@[ eventId, state.epoch ]] && sqlite3_changes(_db) == 1;
}

// MARK: Categories

- (BOOL)categoryEnabled:(NSString *)kind {
	NSArray *rows = [self rows:@"SELECT turns,hosting,requests,saved FROM categories WHERE id=1" arguments:@[]];
	if (rows.count != 1) {
		return NO;
	}
	NSArray *row = rows[0];
	BOOL saved = [row[3] longLongValue] != 0;
	if ([kind isEqualToString:@"friend_room_available"]) {
		return saved && [row[1] longLongValue] != 0;
	}
	if ([kind isEqualToString:@"redo_requested"]) {
		return saved && [row[2] longLongValue] != 0;
	}
	// Before the first save, Android defaults turns to on for turn_ready only.
	return saved ? [row[0] longLongValue] != 0 : [kind isEqualToString:@"turn_ready"];
}

- (BOOL)setCategoriesTurns:(BOOL)turns hosting:(BOOL)hosting requests:(BOOL)requests {
	return [self run:@"UPDATE categories SET turns=?,hosting=?,requests=?,saved=1 WHERE id=1" arguments:@[ @(turns ? 1 : 0), @(hosting ? 1 : 0), @(requests ? 1 : 0) ]];
}

@end
