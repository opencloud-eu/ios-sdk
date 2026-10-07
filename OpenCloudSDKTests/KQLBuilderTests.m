//
//  KQLBuilderTests.m
//  OpenCloudSDKTests
//
//  Created by Markus Goetz on 29.09.26.
//  Copyright © 2026 OpenCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2026, OpenCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import <XCTest/XCTest.h>

#import <OpenCloudSDK/OpenCloudSDK.h>
#import "OCQueryCondition+KQLBuilder.h"

// Tests for OCQueryCondition+KQLBuilder: pure string in, string out. Nothing in here touches the
// network or the filesystem, so the whole class is safe to run unattended (f.ex. from CI).
@interface KQLBuilderTests : XCTestCase
@end

@implementation KQLBuilderTests

#pragma mark - Helpers

- (NSString *)kqlForCondition:(OCQueryCondition *)condition targetContent:(OCKQLSearchedContent)targetContent
{
	return ([condition kqlStringWithTypeAliasToKQLTypeMap:@{
		@"image" : @"image",
		@"x-office/document" : @"document"
	} targetContent:targetContent]);
}

- (NSString *)kqlForSearchTerm:(NSString *)searchTerm targetContent:(OCKQLSearchedContent)targetContent
{
	return ([self kqlForCondition:[OCQueryCondition where:OCItemPropertyNameName contains:searchTerm] targetContent:targetContent]);
}

#pragma mark - name: / content: wildcarding (ios#79)

- (void)testNameOnlySearchIsWildcardWrapped
{
	// name: is a wildcard query server-side and needs the wildcards to match substrings
	XCTAssertEqualObjects([self kqlForSearchTerm:@"invoice" targetContent:OCKQLSearchedContentItemName], @"(name:\"*invoice*\")");
}

- (void)testContentOnlySearchIsNotWildcardWrapped
{
	// ios#79: content: must NOT be wildcard-wrapped. The server only runs the value through the
	// field's analyzer when it contains no wildcards, and the content field is indexed tokenized +
	// lowercased, so a wildcard value never matches an indexed term.
	XCTAssertEqualObjects([self kqlForSearchTerm:@"invoice" targetContent:OCKQLSearchedContentContents], @"(content:\"invoice\")");
}

- (void)testNameAndContentSearchWildcardsOnlyTheName
{
	// Matches the form the web client sends: (name:"*term*" OR content:"term")
	NSString *kql = [self kqlForSearchTerm:@"invoice" targetContent:(OCKQLSearchedContentItemName | OCKQLSearchedContentContents)];

	XCTAssertEqualObjects(kql, @"((name:\"*invoice*\") OR (content:\"invoice\"))");

	// The distinguishing property, stated independently of the exact parenthesisation above, so this
	// still guards the fix if the grouping is ever tidied up to match web verbatim
	XCTAssertTrue([kql containsString:@"name:\"*invoice*\""], @"name: should be wildcard-wrapped, got %@", kql);
	XCTAssertTrue([kql containsString:@"content:\"invoice\""], @"content: should not be wildcard-wrapped, got %@", kql);
	XCTAssertFalse([kql containsString:@"content:\"*"], @"content: must not carry wildcards, got %@", kql);
}

- (void)testNoTargetContentYieldsNoNameQuery
{
	XCTAssertNil([self kqlForSearchTerm:@"invoice" targetContent:0]);
}

#pragma mark - Escaping

- (void)testQuotesInSearchTermAreEscapedForBothFields
{
	NSString *kql = [self kqlForSearchTerm:@"say \"hi\"" targetContent:(OCKQLSearchedContentItemName | OCKQLSearchedContentContents)];

	XCTAssertTrue([kql containsString:@"name:\"*say \\\"hi\\\"*\""], @"got %@", kql);
	XCTAssertTrue([kql containsString:@"content:\"say \\\"hi\\\"\""], @"got %@", kql);
}

#pragma mark - Other operators

- (void)testPrefixAndSuffixOperators
{
	OCQueryCondition *prefix = [OCQueryCondition where:OCItemPropertyNameName startsWith:@"inv"];
	OCQueryCondition *suffix = [OCQueryCondition where:OCItemPropertyNameName endsWith:@"pdf"];

	XCTAssertEqualObjects([self kqlForCondition:prefix targetContent:OCKQLSearchedContentItemName], @"(name:\"inv*\")");
	XCTAssertEqualObjects([self kqlForCondition:suffix targetContent:OCKQLSearchedContentItemName], @"(name:\"*pdf\")");
}

- (void)testNumericComparisonIsNotQuoted
{
	OCQueryCondition *biggerThan = [OCQueryCondition where:OCItemPropertyNameSize isGreaterThan:@(1024)];

	XCTAssertEqualObjects([self kqlForCondition:biggerThan targetContent:OCKQLSearchedContentItemName], @"(size:>1024)");
}

- (void)testTypeAliasIsMappedToMediatype
{
	OCQueryCondition *isImage = [OCQueryCondition where:OCItemPropertyNameTypeAlias isEqualTo:@"image"];

	XCTAssertEqualObjects([self kqlForCondition:isImage targetContent:OCKQLSearchedContentItemName], @"(mediatype:\"image\")");
}

@end
