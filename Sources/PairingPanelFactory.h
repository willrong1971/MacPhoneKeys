#pragma once

#import <Foundation/Foundation.h>
#import <IOBluetoothUI/IOBluetoothUI.h>

NS_ASSUME_NONNULL_BEGIN

/// Call the documented Objective-C factory rather than an inherited -init.
/// ARC and the importer transfer an ordinary, optional Objective-C object to Swift.
FOUNDATION_EXPORT IOBluetoothPairingController * _Nullable MPKCreatePairingPanelController(void) NS_RETURNS_RETAINED;

NS_ASSUME_NONNULL_END
