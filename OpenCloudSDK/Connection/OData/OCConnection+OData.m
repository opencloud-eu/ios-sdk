//
//  OCConnection+OData.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 10.02.22.
//  Copyright © 2022 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2022, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import "OCConnection+OData.h"
#import "GAODataError.h"
#import "NSError+OCError.h"
#import "OCHTTPStatus.h"

@implementation OCConnection (OData)

- (NSProgress *)requestODataAtURL:(NSURL *)url requireSignals:(nullable NSSet<OCConnectionSignalID> *)requiredSignals selectEntityID:(nullable OCODataEntityID)selectEntityID selectProperties:(nullable NSArray<OCODataProperty> *)selectProperties filterString:(nullable OCODataFilterString)filterString entityClass:(Class)entityClass completionHandler:(OCConnectionODataRequestCompletionHandler)completionHandler
{
	OCHTTPRequest *request;
	NSProgress *progress = nil;
	NSString *urlSuffix = nil;
	OCHTTPRequestParameters requestParameters = [NSMutableDictionary new];

	// Select entity: "…/endpoint('entityID')"
	if ((selectEntityID != nil) && (selectEntityID.length > 0))
	{
		// urlSuffix = [NSString stringWithFormat:@"('%@')", selectEntityID]; // as per OData specification
		urlSuffix = [NSString stringWithFormat:@"/%@", selectEntityID]; // practically supported
	}

	if (urlSuffix != nil)
	{
		url = [NSURL URLWithString:[url.absoluteString stringByAppendingString:urlSuffix]];
	}

	// Select properties: "…/endpoint?$select=PropertyName1, PropertyName2"
	if ((selectProperties != nil) && (selectProperties.count > 0))
	{
		requestParameters[@"$select"] = [selectProperties componentsJoinedByString:@", "];
	}

	// Filter string: "…/endpoint?$filter=FirstName eq 'Scott'"
	if (filterString.length > 0)
	{
		requestParameters[@"$filter"] = filterString;
	}

	// Compose HTTP request
	request = [OCHTTPRequest requestWithURL:url];
	request.requiredSignals = requiredSignals; // self.actionSignals;
	if (requestParameters.count > 0)
	{
		request.parameters = requestParameters;
	}

	progress = [self sendRequest:request ephermalCompletionHandler:^(OCHTTPRequest *request, OCHTTPResponse *response, NSError *error) {
		NSDictionary <NSString *, id> *jsonDictionary = nil;
		NSError *returnError = error;
		id returnResult = nil;

		if (error == nil)
		{
			NSError *jsonError = nil;

			if (!response.status.isSuccess)
			{
				// An error status code is a completed HTTP transaction, so it arrives here with error == nil.
				// Its body is typically empty or not OData at all (f.ex. a 502 from a reverse proxy whose
				// upstream is down), which would otherwise be indistinguishable from an empty result.
				returnError = [response.status error];
			}
			else if ((jsonDictionary = [response bodyConvertedDictionaryFromJSONWithError:&jsonError]) != nil)
			{
				if (jsonDictionary[@"error"])
				{
					NSError *decodeError = nil;

					GAODataError *dataError = [jsonDictionary objectForKey:@"error" ofClass:GAODataError.class inCollection:Nil required:NO context:nil error:&decodeError];
					returnError = dataError.nativeError;
				}
				else if (jsonDictionary[@"value"])
				{
					if ([jsonDictionary[@"value"] isKindOfClass:NSArray.class])
					{
						returnResult = [jsonDictionary objectForKey:@"value" ofClass:entityClass inCollection:NSArray.class required:NO context:nil error:&returnError];
					}
					else
					{
						returnResult = [jsonDictionary objectForKey:@"value" ofClass:entityClass inCollection:Nil required:NO context:nil error:&returnError];
					}
				}
			}
			else if (jsonError != nil)
			{
				returnError = jsonError;
			}

		}

		if ((returnError == nil) && (returnResult == nil))
		{
			// Never report success without a result: a response that yields neither an error nor a value
			// is not an empty collection - an empty collection decodes into an empty, non-nil array.
			returnError = OCError(OCErrorResponseUnknownFormat);
		}

		OCLogDebug(@"OData response: returnResult=%@, error=%@, json: %@", returnResult, returnError, jsonDictionary);

		completionHandler(returnError, returnResult);
	}];

	return (progress);
}

@end
