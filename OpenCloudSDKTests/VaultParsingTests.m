//
//  VaultParsingTests.m
//  OpenCloudSDKTests
//
//  Regression tests for https://github.com/opencloud-eu/ios/issues/78
//

#import <XCTest/XCTest.h>
#import <OpenCloudSDK/OpenCloudSDK.h>
#import "OCItem+OCXMLObjectCreation.h"
#import "OCXMLParser.h"
#import "GADrive.h"

@interface VaultParsingTests : XCTestCase
@end

@implementation VaultParsingTests

// First response recorded from demo.opencloud.eu (2026-11-06): PROPFIND of a folder created as vault by OpenCloud Web.
// Second response (regular folder) added by hand: the server lists the unknown property in the 404 propstat.
static NSString *kVaultFolderPropfindResponse = @"<d:multistatus xmlns:s=\"http://sabredav.org/ns\" xmlns:d=\"DAV:\" xmlns:oc=\"http://owncloud.org/ns\">"
	"<d:response>"
		"<d:href>/dav/spaces/d21381aa-01dc-45cb-a5b8-e6880c47c954$4a67caa3-cff0-4899-a69d-816848d23b9d/Neuer%20Ordner.vault/</d:href>"
		"<d:propstat><d:prop>"
			"<oc:permissions>RDNVCKZP</oc:permissions>"
			"<oc:favorite>0</oc:favorite>"
			"<oc:fileid>d21381aa-01dc-45cb-a5b8-e6880c47c954$4a67caa3-cff0-4899-a69d-816848d23b9d!d1b90740-78af-4f5e-bc35-7ba04a04d966</oc:fileid>"
			"<oc:file-parent>d21381aa-01dc-45cb-a5b8-e6880c47c954$4a67caa3-cff0-4899-a69d-816848d23b9d!4a67caa3-cff0-4899-a69d-816848d23b9d</oc:file-parent>"
			"<oc:name>Neuer Ordner.vault</oc:name>"
			"<oc:owner-id>alan</oc:owner-id>"
			"<oc:owner-display-name>Alan Turing</oc:owner-display-name>"
			"<oc:privatelink>https://demo.opencloud.eu/f/d21381aa-01dc-45cb-a5b8-e6880c47c954$4a67caa3-cff0-4899-a69d-816848d23b9d%21d1b90740-78af-4f5e-bc35-7ba04a04d966</oc:privatelink>"
			"<oc:size>0</oc:size>"
			"<d:getlastmodified>Fri, 06 Nov 2026 09:43:29 GMT</d:getlastmodified>"
			"<d:getetag>\"137340bf94d665aa48a209236c5e5246\"</d:getetag>"
			"<d:resourcetype><d:collection/></d:resourcetype>"
			"<oc:tags></oc:tags>"
			"<integrity-id xmlns=\"ocrclone\">UkNMT05FAACfQDChK3k6+BoVBNQIgayGqNhjvJ2254BsRcxPn2He3iQUiq9hFlY89aId6jz54Brnyodo3h3ADKJORPJbBsmE9ZOV0rf8VQaxydgb\n</integrity-id>"
		"</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>"
		"<d:propstat><d:prop>"
			"<d:getcontentlength></d:getcontentlength>"
			"<oc:share-types></oc:share-types>"
			"<oc:has-preview></oc:has-preview>"
		"</d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>"
	"</d:response>"
	"<d:response>"
		"<d:href>/dav/spaces/d21381aa-01dc-45cb-a5b8-e6880c47c954$4a67caa3-cff0-4899-a69d-816848d23b9d/Regular/</d:href>"
		"<d:propstat><d:prop>"
			"<oc:permissions>RDNVCKZP</oc:permissions>"
			"<oc:fileid>d21381aa-01dc-45cb-a5b8-e6880c47c954$4a67caa3-cff0-4899-a69d-816848d23b9d!aaaaaaaa-1111-2222-3333-444444444444</oc:fileid>"
			"<oc:name>Regular</oc:name>"
			"<d:getetag>\"0123456789abcdef0123456789abcdef\"</d:getetag>"
			"<d:resourcetype><d:collection/></d:resourcetype>"
		"</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>"
		"<d:propstat><d:prop>"
			"<integrity-id xmlns=\"ocrclone\"></integrity-id>"
		"</d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>"
	"</d:response>"
"</d:multistatus>";

- (NSArray<OCItem *> *)_parseItems
{
	OCXMLParser *parser = [[OCXMLParser alloc] initWithData:[kVaultFolderPropfindResponse dataUsingEncoding:NSUTF8StringEncoding]];

	parser.options[@"basePath"] = @"/dav/spaces/d21381aa-01dc-45cb-a5b8-e6880c47c954$4a67caa3-cff0-4899-a69d-816848d23b9d";
	[parser addObjectCreationClasses:@[ OCItem.class ]];

	XCTAssertTrue([parser parse]);

	NSMutableArray<OCItem *> *items = [NSMutableArray new];

	for (id object in parser.parsedObjects)
	{
		if ([object isKindOfClass:OCItem.class])
		{
			[items addObject:object];
		}
	}

	return (items);
}

- (OCItem *)_item:(NSArray<OCItem *> *)items withName:(NSString *)name
{
	for (OCItem *item in items)
	{
		if ([item.name isEqual:name])
		{
			return (item);
		}
	}

	return (nil);
}

#pragma mark - Folders
- (void)testVaultFolderIsDetected
{
	NSArray<OCItem *> *items = [self _parseItems];

	XCTAssertEqual(items.count, 2);

	OCItem *vaultFolder = [self _item:items withName:@"Neuer Ordner.vault"];

	XCTAssertNotNil(vaultFolder);
	XCTAssertEqual(vaultFolder.type, OCItemTypeCollection);
	XCTAssertTrue(vaultFolder.isVault);
}

- (void)testRegularFolderIsNotAVault
{
	// The property is also listed for folders without it - in the 404 propstat, which must be ignored
	OCItem *regularFolder = [self _item:[self _parseItems] withName:@"Regular"];

	XCTAssertNotNil(regularFolder);
	XCTAssertFalse(regularFolder.isVault);
}

- (void)testVaultFolderSurvivesArchiving
{
	// Items are stored archived in the database
	OCItem *vaultFolder = [self _item:[self _parseItems] withName:@"Neuer Ordner.vault"];
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:vaultFolder requiringSecureCoding:YES error:NULL];
	OCItem *unarchivedFolder = [NSKeyedUnarchiver unarchivedObjectOfClass:OCItem.class fromData:data error:NULL];

	XCTAssertNotNil(unarchivedFolder);
	XCTAssertTrue(unarchivedFolder.isVault);
}

#pragma mark - Spaces
// Drive JSON in the shape of the libre-graph Drive schema (not recorded): a vault space carries
// `@libre.graph.contentType` = `application/vnd.opencloud.vault` (see OpenCloud Web's web-app-rclone-crypt).
- (NSDictionary *)_driveJSONWithContentType:(NSString *)contentType
{
	NSMutableDictionary *driveJSON = [@{
		@"id" : @"d21381aa-01dc-45cb-a5b8-e6880c47c954$5fd14bf4-64ef-4592-aa34-07d74b376def",
		@"name" : @"Encrypted Space",
		@"driveType" : @"project",
		@"driveAlias" : @"project/encrypted-space",
		@"webUrl" : @"https://demo.opencloud.eu/f/d21381aa-01dc-45cb-a5b8-e6880c47c954$5fd14bf4-64ef-4592-aa34-07d74b376def",
		@"root" : @{
			@"id" : @"d21381aa-01dc-45cb-a5b8-e6880c47c954$5fd14bf4-64ef-4592-aa34-07d74b376def!5fd14bf4-64ef-4592-aa34-07d74b376def",
			@"eTag" : @"\"2b4fb7d4e1e3e0c9a6f7f7f07b2a2f7c\"",
			@"webDavUrl" : @"https://demo.opencloud.eu/dav/spaces/d21381aa-01dc-45cb-a5b8-e6880c47c954$5fd14bf4-64ef-4592-aa34-07d74b376def"
		}
	} mutableCopy];

	if (contentType != nil)
	{
		driveJSON[@"@libre.graph.contentType"] = contentType;
	}

	return (driveJSON);
}

- (OCDrive *)_driveWithContentType:(NSString *)contentType
{
	NSError *error = nil;
	GADrive *gaDrive = [GADrive decodeGraphData:[self _driveJSONWithContentType:contentType] context:nil error:&error];

	XCTAssertNil(error);
	XCTAssertNotNil(gaDrive);

	return ([OCDrive driveFromGADrive:gaDrive]);
}

- (void)testVaultSpaceIsDetected
{
	OCDrive *drive = [self _driveWithContentType:@"application/vnd.opencloud.vault"];

	XCTAssertNotNil(drive);
	XCTAssertTrue(drive.isVault);
	XCTAssertEqualObjects(drive.webURL.absoluteString, @"https://demo.opencloud.eu/f/d21381aa-01dc-45cb-a5b8-e6880c47c954$5fd14bf4-64ef-4592-aa34-07d74b376def");
}

- (void)testRegularSpaceIsNotAVault
{
	XCTAssertFalse([self _driveWithContentType:nil].isVault);
	XCTAssertFalse([self _driveWithContentType:@"application/vnd.opencloud.something-else"].isVault);
}

- (void)testVaultSpaceSurvivesArchiving
{
	// Drives are stored archived in the vault's drive list
	OCDrive *drive = [self _driveWithContentType:@"application/vnd.opencloud.vault"];
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:drive requiringSecureCoding:YES error:NULL];
	OCDrive *unarchivedDrive = [NSKeyedUnarchiver unarchivedObjectOfClass:OCDrive.class fromData:data error:NULL];

	XCTAssertNotNil(unarchivedDrive);
	XCTAssertTrue(unarchivedDrive.isVault);
}

@end
