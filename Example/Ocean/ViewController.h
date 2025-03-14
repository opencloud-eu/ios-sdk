//
//  ViewController.h
//  Ocean
//
//  Created by Felix Schwarz on 16.02.18.
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

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property(strong) IBOutlet UITextField *serverURLField;
@property(strong) IBOutlet UITextView *logTextView;

- (IBAction)connectAndGetInfo:(id)sender;
- (IBAction)showCertificate:(id)sender;

@end

