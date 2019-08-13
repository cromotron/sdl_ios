//
//  SDLPresentKeyboardOperation.h
//  SmartDeviceLink
//
//  Created by Joel Fischer on 5/24/18.
//  Copyright © 2018 smartdevicelink. All rights reserved.
//

#import "SDLAsynchronousOperation.h"
#import "NSNumber+NumberType.h"

@class SDLKeyboardProperties;

@protocol SDLConnectionManagerType;
@protocol SDLKeyboardDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface SDLPresentKeyboardOperation : SDLAsynchronousOperation

/**
 An operation to present a keyboard.

 @param connectionManager The connection manager
 @param originalKeyboardProperties The keyboard configuration
 @param initialText The initial text within the keyboard input field. It will disappear once the user selects the field in order to enter text
 @param keyboardDelegate The keyboard delegate called when the user interacts with the keyboard
 @param cancelID An ID for this specific keyboard to allow cancellation through the `CancelInteraction` RPC.
 @return A SDLPresentKeyboardOperation object
 */
- (instancetype)initWithConnectionManager:(id<SDLConnectionManagerType>)connectionManager keyboardProperties:(SDLKeyboardProperties *)originalKeyboardProperties initialText:(NSString *)initialText keyboardDelegate:(id<SDLKeyboardDelegate>)keyboardDelegate cancelID:(UInt16)cancelID;

/**
 Cancels a keyboard. If the keyboard is currently presented, it will be dismissed. If the keyboard has not yet been sent to Core, it will not be sent.

 @param cancelID The unique ID assigned to the keyboard
 */
- (void)dismissKeyboardWithCancelID:(NSNumber<SDLInt> *)cancelID;

@end

NS_ASSUME_NONNULL_END
