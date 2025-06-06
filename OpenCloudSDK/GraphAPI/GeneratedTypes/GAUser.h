//
// GAUser.h
// Autogenerated / Managed by ocapigen
// Copyright (C) 2024 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2024, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://opencloud.eu/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

// occgen: includes
#import <Foundation/Foundation.h>
#import "GAGraphObject.h"
#import "GALanguage.h"

// occgen: forward declarations
@class GAAppRoleAssignment;
@class GADrive;
@class GAGroup;
@class GAObjectIdentity;
@class GAPasswordProfile;
@class GASignInActivity;

// occgen: type start
NS_ASSUME_NONNULL_BEGIN
@interface GAUser : NSObject <GAGraphObject, NSSecureCoding>

// occgen: type properties
@property(strong, nullable) NSString *identifier; //!< Read-only.
@property(strong, nullable) NSNumber *accountEnabled; //!< [boolean] Set to "true" when the account is enabled.
@property(strong, nullable) NSArray<GAAppRoleAssignment *> *appRoleAssignments; //!< The apps and app roles which this user has been assigned.
@property(strong) NSString *displayName; //!< The name displayed in the address book for the user. This value is usually the combination of the user''s first name, middle initial, and last name. This property is required when a user is created and it cannot be cleared during updates. Returned by default. Supports $orderby.
@property(strong, nullable) NSArray<GADrive *> *drives; //!< A collection of drives available for this user. Read-only.
@property(strong, nullable) GADrive *drive; //!< The personal drive of this user. Read-only.
@property(strong, nullable) NSArray<GAObjectIdentity *> *identities; //!< Identities associated with this account.
@property(strong, nullable) NSString *mail; //!< The SMTP address for the user, for example, ''jeff@contoso.onopencloud.eu''. Returned by default.
@property(strong, nullable) NSArray<GAGroup *> *memberOf; //!< Groups that this user is a member of. HTTP Methods: GET (supported for all groups). Read-only. Nullable. Supports $expand.
@property(strong) NSString *onPremisesSamAccountName; //!< Contains the on-premises SAM account name synchronized from the on-premises directory.
@property(strong, nullable) GAPasswordProfile *passwordProfile;
@property(strong, nullable) NSString *surname; //!< The user's surname (family name or last name). Returned by default.
@property(strong, nullable) NSString *givenName; //!< The user's givenName. Returned by default.
@property(strong, nullable) NSString *userType; //!< The user`s type. This can be either "Member" for regular user, "Guest" for guest users or "Federated" for users imported from a federated instance.
@property(strong, nullable) GALanguage preferredLanguage;
@property(strong, nullable) GASignInActivity *signInActivity;

// occgen: type protected {"locked":true}


// occgen: type end
@end
NS_ASSUME_NONNULL_END

