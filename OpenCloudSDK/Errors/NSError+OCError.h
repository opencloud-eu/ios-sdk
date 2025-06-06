//
//  NSError+OCError.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 24.02.18.
//  Copyright © 2018 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2018, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, OCError)
{
	OCErrorInternal, 		//!< Internal error
	OCErrorInsufficientParameters, 	//!< Insufficient parameters
	OCErrorUnknown,			//!< Unknown error

	OCErrorAuthorizationFailed, 		//!< Authorization failed
	OCErrorAuthorizationRedirect, 		//!< Authorization failed because the server returned a redirect. Authorization may be successful when retried with the redirect URL. The userInfo of the error contains the alternative server URL as value for the key OCAuthorizationMethodAlternativeServerURLKey
	OCErrorAuthorizationNoMethodData, 	//!< Authorization failed because no secret data was set for the authentication method
	OCErrorAuthorizationMissingData, 	//!< Authorization failed because data was missing from the secret data for the authentication method
	OCErrorAuthorizationCancelled,		//!< Authorization was cancelled by the user

	OCErrorRequestURLSessionTaskConstructionFailed, //!< Construction of URL Session Task failed
	OCErrorRequestCancelled, 			//!< Request was cancelled
	OCErrorRequestRemovedBeforeScheduling, 		//!< Request was removed before scheduling
	OCErrorRequestServerCertificateRejected,	//!< Request was cancelled because the server certificate was rejected
	OCErrorRequestDroppedByURLSession,		//!< Request was dropped by the NSURLSession
	OCErrorRequestCompletedWithError,		//!< Request completed with error
	OCErrorRequestURLSessionInvalidated,		//!< Request couldn't be scheduled because the underlying NSURLSession has been invalidated

	OCErrorException,		//!< An exception occured

	OCErrorResponseUnknownFormat,	//!< Response was in an unknown format
	
	OCErrorServerDetectionFailed,	//!< Server detection failed, i.e. when the server at a URL is not an OpenCloud instance
	OCErrorServerTooManyRedirects,	//!< Server detection failed because of too many redirects
	OCErrorServerBadRedirection,	//!< Server redirection to bad/invalid URL
	OCErrorServerVersionNotSupported,    //!< This server version is not supported.
	OCErrorServerNoSupportedAuthMethods, //!< This server doesn't offer any supported auth methods
	OCErrorServerInMaintenanceMode,	//!< Server is in maintenance mode

	OCErrorCertificateInvalid,	//!< The certificate is invalid or contains errors
	OCErrorCertificateMissing,	//!< No certificate was returned for a request despite this being a HTTPS connection (should never occur in production, but only if you forgot to provide a certificate during simulated responses to HTTPS requests)

	OCErrorFeatureNotSupportedForItem,  //!< This feature is not supported for this item.
	OCErrorFeatureNotSupportedByServer, //!< This feature is not supported for this server (version).
	OCErrorFeatureNotImplemented,	    //!< This feature is currently not implemented

	OCErrorItemNotFound, //!< The targeted item has not been found.
	OCErrorItemDestinationNotFound, //!< The destination item has not been found.
	OCErrorItemChanged, //!< The targeted item has changed.
	OCErrorItemInsufficientPermissions, //!< The action couldn't be performed on the targeted item because the client lacks permissions
	OCErrorItemOperationForbidden, //!< The operation on the targeted item is not allowed
	OCErrorItemAlreadyExists, //!< There already is an item at the destination of this action
	OCErrorItemNotAvailableOffline, //!< This item is not available offline

	OCErrorFileNotFound, //!< The file was not found.

	OCErrorSyncRecordNotFound, //!< The referenced sync record could not be found.

	OCErrorNewerVersionExists, //!< A newer version already exists

	OCErrorCancelled, //!< The operation was cancelled

	OCErrorOutdatedCache, //!< An operation failed due to outdated cache information

	OCErrorRunningOperation, //!< A running operation prevents execution

	OCErrorInvalidProcess, //!< Invalid process.

	OCErrorShareUnauthorized, //!< Not authorized to access shares
	OCErrorShareUnavailable,  //!< Shares are unavailable.
	OCErrorShareItemNotADirectory, //!< Item is not a directory.
	OCErrorShareItemNotFound,  //!< Item not found.
	OCErrorShareNotFound,  	   //!< Share not found.
	OCErrorShareUnknownType,   //!< Unknown share type.
	OCErrorSharePublicUploadDisabled, //!< Public upload was disabled by the administrator.

	OCErrorInsufficientStorage, //!< Insufficient storage

	OCErrorNotAvailableOffline, //!< API not available offline.

	OCErrorAuthorizationRetry, //!< Authorization failed. Retry the request.

	OCErrorItemPolicyRedundant, //!< Another item policy of the same kind already includes the item, making the addition of this item policy redundant. Item policy(s) are passed as error.userInfo[OCErrorItemPoliciesKey].
	OCErrorItemPolicyMakesRedundant, //!< Other item policies of the same kind covering subsets of this item policy become redundant by the addition of this item policy. Item policy(s) are passed as error.userInfo[OCErrorItemPoliciesKey].

	OCErrorUnnormalizedPath, //!< The provided path is not normalized.

	OCErrorPrivateLinkInvalidFormat, //!< Private link format invalid.
	OCErrorPrivateLinkResolutionFailed, //!< Resolution of private link failed

	OCErrorAuthorizationMethodNotAllowed, //!< Authentication method not allowed. Re-authentication needed.
	OCErrorAuthorizationMethodUnknown, //!< Authentication method unknown.

	OCErrorServerConnectionValidationFailed, //!< Validation of connection failed.

	OCErrorAuthorizationClientRegistrationFailed, //!< Client registration failed
	OCErrorAuthorizationNotMatchingRequiredUserID, //!< The logged in user is not matching the required user ID.

	OCErrorDatabaseMigrationRequired, //!< Database upgrade required. Please open the app to perform the upgrade.
	OCErrorHostUpdateRequired, //!< Bookmark created with a newer app version. Please update the app.

	OCErrorAuthorizationCantOpenCustomSchemeURL, //!< Can't open authorization URL with custom scheme.

	OCErrorLockInvalidated, //!< Lock invalidated.

	OCErrorWebFingerLacksServerInstanceRelation, //!< Web finger response lacks server instance relation.
	OCErrorUnknownUser, //!< Unknown user

	OCErrorRequestTimeout, //!< Request timed out

	OCErrorResourceDoesNotExist, //!< Resource does not exist

	OCErrorInvalidType, //!< Invalid type
	OCErrorRequiredValueMissing, //!< Required value missing

	OCErrorGraphError, //!< Generic graph error

	OCErrorDataItemTypeUnavailable, //!< Object does not return DataItemType.
	OCErrorDataConverterUnavailable,//!< No data converter available for conversion.

	OCErrorMissingDriveID, //!< Missing Drive ID.

	OCErrorResourceNotFound, //!< Resource not found.
	OCErrorInvalidParameter, //!< Invalid parameter.

	OCErrorItemProcessing, //!< Item is currently processing.

	OCErrorRequestResponseCorruptedOrDropped, //!< Response to request dropped or corrupted.
	OCErrorRequestDroppedByOriginalProcessTermination //!< Request was dropped by the originally responsible process terminating.
};

@class OCIssue;

NS_ASSUME_NONNULL_BEGIN

@interface NSError (OCError)

+ (instancetype)errorWithOCError:(OCError)errorCode;

+ (instancetype)errorWithOCError:(OCError)errorCode userInfo:(nullable NSDictionary<NSErrorUserInfoKey,id> *)userInfo;

- (BOOL)isOCError;

- (BOOL)isOCErrorWithCode:(OCError)errorCode;

- (nullable NSDictionary *)ocErrorInfoDictionary;

#pragma mark - Embedding issues
- (NSError *)errorByEmbeddingIssue:(OCIssue *)issue;
- (nullable OCIssue *)embeddedIssue;

#pragma mark - Error dating
- (NSError *)withErrorDate:(nullable NSDate *)errorDate;
- (nullable NSDate *)errorDate;

@end

#define OCError(errorCode) [NSError errorWithOCError:errorCode userInfo:@{ NSDebugDescriptionErrorKey : [NSString stringWithFormat:@"%s [%@:%d]", __PRETTY_FUNCTION__, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__], OCErrorDateKey : [NSDate new] }] //!< Macro that creates an OCError from an OCErrorCode, but also adds method name, source file and line number)

#define OCErrorWithDescription(errorCode,description) [NSError errorWithOCError:errorCode userInfo:[[NSDictionary alloc] initWithObjectsAndKeys: [NSString stringWithFormat:@"%s [%@:%d]", __PRETTY_FUNCTION__, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__], NSDebugDescriptionErrorKey, [NSDate new], OCErrorDateKey, description, NSLocalizedDescriptionKey, nil]] //!< Macro that creates an OCError from an OCErrorCode and optional description, but also adds method name, source file and line number)

#define OCErrorWithDescriptionAndUserInfo(errorCode,description,userInfoKey,userInfoValue) [NSError errorWithOCError:errorCode userInfo:[[NSDictionary alloc] initWithObjectsAndKeys: [NSString stringWithFormat:@"%s [%@:%d]", __PRETTY_FUNCTION__, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__], NSDebugDescriptionErrorKey, userInfoValue, userInfoKey, description, NSLocalizedDescriptionKey, nil]] //!< Macro that creates an OCError from an OCErrorCode and optional description, but also adds method name, source file and line number)

#define OCErrorWithInfo(errorCode,errorInfo) [NSError errorWithOCError:errorCode userInfo:@{ NSDebugDescriptionErrorKey : [NSString stringWithFormat:@"%s [%@:%d]", __PRETTY_FUNCTION__, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__], OCErrorInfoKey : errorInfo, OCErrorDateKey : [NSDate new] }] //!< Like the OCError macro, but allows for an error specific info value

#define OCErrorFromError(errorCode,underlyingError) [NSError errorWithOCError:errorCode userInfo:@{ NSDebugDescriptionErrorKey : [NSString stringWithFormat:@"%s [%@:%d]", __PRETTY_FUNCTION__, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__], NSUnderlyingErrorKey : underlyingError, OCErrorDateKey : ((underlyingError.errorDate != nil) ? underlyingError.errorDate : [NSDate new]) }] //!< Like the OCError macro, but allows to specifiy an underlying error, too

#define OCErrorWithDescriptionFromError(errorCode,description,underlyingError) [NSError errorWithOCError:errorCode userInfo:[[NSDictionary alloc] initWithObjectsAndKeys: [NSString stringWithFormat:@"%s [%@:%d]", __PRETTY_FUNCTION__, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__], NSDebugDescriptionErrorKey, [NSDate new], OCErrorDateKey, underlyingError, NSUnderlyingErrorKey, description, NSLocalizedDescriptionKey, nil]] //!< Like the OCErrorWithDescription macro, but allows to specifiy an underlying error, too

#define OCErrorAddDateFromResponse(error,response) if (response.date != nil) \
	{ \
		error = [error withErrorDate:response.date]; \
	}

extern NSErrorDomain OCErrorDomain;

extern NSErrorUserInfoKey OCErrorInfoKey;
extern NSErrorUserInfoKey OCErrorDateKey;

NS_ASSUME_NONNULL_END

#define OCFRelease(obj) OCLogDebug(@"CFRelease %s [%@:%d]", __PRETTY_FUNCTION__, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__); CFRelease(obj);
#define OCFRetain(obj) OCLogDebug(@"CFRetain %s [%@:%d]", __PRETTY_FUNCTION__, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__); CFRetain(obj);
