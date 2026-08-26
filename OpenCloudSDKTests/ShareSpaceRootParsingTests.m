//
//  ShareSpaceRootParsingTests.m
//  OpenCloudSDKTests
//
//  Regression tests for https://github.com/opencloud-eu/ios/issues/68
//

#import <XCTest/XCTest.h>
#import <OpenCloudSDK/OpenCloudSDK.h>
#import "OCShare+OCXMLObjectCreation.h"
#import "OCXMLParser.h"

@interface ShareSpaceRootParsingTests : XCTestCase
@end

@implementation ShareSpaceRootParsingTests

// Recorded from OpenCloud 7.4.0: GET /ocs/v2.php/apps/files_sharing/api/v1/shares?state=all&shared_with_me=true
static NSString *kSharedWithMeResponse = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?><ocs><meta><status>ok</status><statuscode>200</statuscode><message>OK</message></meta><data><element><id>share-accepted-spaceroot</id><share_type>0</share_type><permissions>31</permissions><stime>1787655630</stime><uid_file_owner>owner</uid_file_owner><state>0</state><path>/Shares</path><item_type>folder</item_type><mimetype>httpd/unix-directory</mimetype><space_alias>project/webinars-&amp;-talks</space_alias><item_source>d21381aa-01dc-45cb-a5b8-e6880c47c954$36cc9706-e6fa-4aa5-8ac7-d617f94df6f7!36cc9706-e6fa-4aa5-8ac7-d617f94df6f7</item_source><file_source>d21381aa-01dc-45cb-a5b8-e6880c47c954$36cc9706-e6fa-4aa5-8ac7-d617f94df6f7!36cc9706-e6fa-4aa5-8ac7-d617f94df6f7</file_source><file_target>/Shares</file_target><share_with>dennis</share_with><share_with_displayname>Dennis Ritchie</share_with_displayname></element><element><id>share-pending-spaceroot</id><share_type>0</share_type><permissions>31</permissions><stime>1787655630</stime><uid_file_owner>owner</uid_file_owner><state>1</state><path>/</path><item_type>folder</item_type><mimetype>httpd/unix-directory</mimetype><space_alias>project/markus</space_alias><item_source>d21381aa-01dc-45cb-a5b8-e6880c47c954$46d07fa3-1353-4d8e-997b-665c307956e8!46d07fa3-1353-4d8e-997b-665c307956e8</item_source><file_source>d21381aa-01dc-45cb-a5b8-e6880c47c954$46d07fa3-1353-4d8e-997b-665c307956e8!46d07fa3-1353-4d8e-997b-665c307956e8</file_source><file_target>/Shares/markus</file_target><share_with>dennis</share_with><share_with_displayname>Dennis Ritchie</share_with_displayname></element><element><id>share-accepted-regular</id><share_type>0</share_type><permissions>31</permissions><stime>1787655630</stime><uid_file_owner>owner</uid_file_owner><state>0</state><path>/Documents/Reports</path><item_type>folder</item_type><mimetype>httpd/unix-directory</mimetype><space_alias>project/opencloud</space_alias><item_source>d21381aa-01dc-45cb-a5b8-e6880c47c954$5fd14bf4-64ef-4592-aa34-07d74b376def!aaaaaaaa-1111-2222-3333-444444444444</item_source><file_source>d21381aa-01dc-45cb-a5b8-e6880c47c954$5fd14bf4-64ef-4592-aa34-07d74b376def!aaaaaaaa-1111-2222-3333-444444444444</file_source><file_target>/Shares/Reports</file_target><share_with>dennis</share_with><share_with_displayname>Dennis Ritchie</share_with_displayname></element></data></ocs>";

- (NSArray<OCShare *> *)_parseShares
{
	OCXMLParser *parser = [[OCXMLParser alloc] initWithData:[kSharedWithMeResponse dataUsingEncoding:NSUTF8StringEncoding]];

	parser.options[@"_shareCategory"] = @(OCShareCategoryWithMe);
	[parser addObjectCreationClasses:@[ OCShare.class ]];

	XCTAssertTrue([parser parse]);

	NSMutableArray<OCShare *> *shares = [NSMutableArray new];

	for (id object in parser.parsedObjects)
	{
		if ([object isKindOfClass:OCShare.class])
		{
			[shares addObject:object];
		}
	}

	return (shares);
}

- (OCShare *)_share:(NSArray<OCShare *> *)shares withIdentifier:(NSString *)identifier
{
	for (OCShare *share in shares)
	{
		if ([share.identifier isEqual:identifier])
		{
			return (share);
		}
	}

	return (nil);
}

- (void)testSpaceRootSharesAreDetected
{
	NSArray<OCShare *> *shares = [self _parseShares];

	XCTAssertEqual(shares.count, 3);

	XCTAssertTrue([self _share:shares withIdentifier:@"share-accepted-spaceroot"].itemIsSpaceRoot);
	XCTAssertTrue([self _share:shares withIdentifier:@"share-pending-spaceroot"].itemIsSpaceRoot);
	XCTAssertFalse([self _share:shares withIdentifier:@"share-accepted-regular"].itemIsSpaceRoot);
}

- (void)testAcceptedSpaceRootShareKeepsItsOwnDrive
{
	// Before the fix, accepting a project space membership relocated it into the Shares Jail,
	// where a PROPFIND then returned 404 - so the entry could not be opened anymore.
	OCShare *share = [self _share:[self _parseShares] withIdentifier:@"share-accepted-spaceroot"];

	XCTAssertNotNil(share);
	XCTAssertNotEqualObjects(share.itemLocation.driveID, OCDriveIDSharesJail);
	XCTAssertEqualObjects(share.itemLocation.driveID, @"d21381aa-01dc-45cb-a5b8-e6880c47c954$36cc9706-e6fa-4aa5-8ac7-d617f94df6f7");
}

- (void)testPendingAndAcceptedSpaceRootSharesResolveConsistently
{
	// Accepting must not change where the space lives: the "opens only once" symptom was caused by
	// pending and accepted states resolving to two different drives.
	NSArray<OCShare *> *shares = [self _parseShares];

	OCShare *pending = [self _share:shares withIdentifier:@"share-pending-spaceroot"];

	XCTAssertEqualObjects(pending.itemLocation.driveID, @"d21381aa-01dc-45cb-a5b8-e6880c47c954$46d07fa3-1353-4d8e-997b-665c307956e8");
	XCTAssertNotEqualObjects(pending.itemLocation.driveID, OCDriveIDSharesJail);
}

- (void)testOrdinaryAcceptedShareStillUsesSharesJail
{
	// Regression guard: ordinary shares of files and folders MUST keep being mapped into the Shares Jail.
	OCShare *share = [self _share:[self _parseShares] withIdentifier:@"share-accepted-regular"];

	XCTAssertNotNil(share);
	XCTAssertEqualObjects(share.itemLocation.driveID, OCDriveIDSharesJail);
	XCTAssertEqualObjects(share.itemLocation.path, @"/Reports/"); // folder locations carry a trailing slash
}

@end
