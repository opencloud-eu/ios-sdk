//
//  OCSQLiteMigration.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 02.04.18.
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
#import "OCSQLiteDB.h"
#import "OCLogTag.h"

@class OCSQLiteTableSchema;
@class OCSQLiteDB;

NS_ASSUME_NONNULL_BEGIN

@interface OCSQLiteMigration : NSObject <OCLogTagging>
{
	NSUInteger _appliedSchemas;
}

@property(strong) NSMutableDictionary<NSString *,NSNumber *> *versionsByTableName;

@property(strong) NSMutableArray<OCSQLiteTableSchema *> *applicableSchemas;

@property(nullable,strong) NSProgress *progress;
@property(nullable,strong) NSError *error;

- (void)applySchemasToDatabase:(OCSQLiteDB *)database completionHandler:(nullable OCSQLiteDBCompletionHandler)completionHandler;

@end

NS_ASSUME_NONNULL_END
