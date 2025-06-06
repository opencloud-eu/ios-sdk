//
//  OCDatabaseConsistentOperation.m
//  OpenCloudSDK
//
//  Created by Felix Schwarz on 02.05.18.
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

#import "OCDatabaseConsistentOperation.h"
#import "OCSQLiteDB.h"
#import "OCSQLiteTransaction.h"
#import "OCMacros.h"

@implementation OCDatabaseConsistentOperation

@synthesize database = _database;

@synthesize counterIdentifier = _counterIdentifier;

@synthesize preparationResult = _preparationResult;
@synthesize preparationError = _preparationError;
@synthesize preparationCounterValue = _preparationCounterValue;

@synthesize preparation = _preparation;

- (instancetype)initWithDatabase:(OCDatabase *)database counterIdentifier:(OCDatabaseCounterIdentifier)counterIdentifier preparation:(OCDatabaseConsistentOperationPreparationBlock)preparation
{
	if ((self = [super init]) != nil)
	{
		self.database = database;
		self.counterIdentifier = counterIdentifier;
		self.preparation = preparation;
	}

	return (self);
}

- (void)prepareWithCompletionHandler:(dispatch_block_t)completionHandler
{
	[self.database retrieveValueForCounter:self.counterIdentifier completionHandler:^(NSError *error, NSNumber *counterValue) {
		self.preparationCounterValue = counterValue;

		if (self.preparation != nil)
		{
			if (!self->_initialPreparationDidRun)
			{
				self->_initialPreparationDidRun = YES;

				self.preparation(self, OCDatabaseConsistentOperationActionInitial, nil, ^(NSError *error, id prepResult){
					self.preparationError = error;
					self.preparationResult = prepResult;

					if (completionHandler != nil)
					{
						completionHandler();
					}
				});
			}
		}
	}];
}

- (void)performOperation:(OCDatabaseConsistentOperationBlock)operation completionHandler:(OCDatabaseProtectedBlockCompletionHandler)completionHandler
{
	if (operation == nil) { return; }

	[self.database increaseValueForCounter:self.counterIdentifier withProtectedBlock:^(NSNumber *previousCounterValue, NSNumber *newCounterValue) {
		NSError *error = self.preparationError;

		if (error == nil)
		{
			if (self->_preparationCounterValue.unsignedIntegerValue < previousCounterValue.unsignedIntegerValue)
			{
				if (self.preparation != nil)
				{
					OCSyncExec(preparationCompletion, {
						self.preparation(self, (self->_initialPreparationDidRun ? OCDatabaseConsistentOperationActionRepeated : OCDatabaseConsistentOperationActionInitial), newCounterValue, ^(NSError *prepError, id prepResult){
							self.preparationError = prepError;
							self.preparationResult = prepResult;

							OCSyncExecDone(preparationCompletion);
						});

						self->_initialPreparationDidRun = YES;
					});

					error = self.preparationError;
				}

				if (error == nil)
				{
					error = operation(self, self.preparationResult, newCounterValue);
				}
			}
			else
			{
				error = operation(self, self.preparationResult, newCounterValue);
			}
		}

		return (error);
	} completionHandler:completionHandler];
}

@end
