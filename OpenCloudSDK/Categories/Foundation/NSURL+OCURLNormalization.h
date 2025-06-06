//
//  NSURL+OCURLNormalization.h
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 02.03.18.
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

NS_ASSUME_NONNULL_BEGIN

@interface NSURL (OCURLNormalization)

+ (nullable NSURL *)URLWithUsername:(NSString * _Nullable * _Nullable )outUserName password:(NSString * _Nullable * _Nullable )outPassword afterNormalizingURLString:(NSString *)urlString protocolWasPrepended:(BOOL * _Nullable)outProtocolWasPrepended;

@property(strong,nullable,readonly,nonatomic) NSNumber *effectivePort;

- (BOOL)hasSameSchemeHostAndPortAs:(NSURL *)otherURL;

@property(strong,nullable,readonly,nonatomic) NSString *standardizedFileURLPath;
- (BOOL)isIdenticalOrChildOf:(NSURL *)parentFileURL;

@end

NS_ASSUME_NONNULL_END
