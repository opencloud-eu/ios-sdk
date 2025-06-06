//
//  OCFile.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 21.06.18.
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
#import "OCChecksum.h"
#import "OCItem.h"
#import "OCTypes.h"
#import "OCClaim.h"

NS_ASSUME_NONNULL_BEGIN

@interface OCFile : NSObject <NSSecureCoding>

@property(nullable,strong) OCFileID fileID;
@property(nullable,strong) OCFileETag eTag;

@property(nullable,strong) OCItem *item;
@property(nullable,strong) NSURL *url;
@property(nullable,strong) OCChecksum *checksum;

@property(nullable,strong) OCClaim *claim;

@end

NS_ASSUME_NONNULL_END
