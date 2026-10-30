#import "PairingPanelFactory.h"

IOBluetoothPairingController * _Nullable MPKCreatePairingPanelController(void) {
    // This is a public IOBluetoothUI class method. Swift's zero-argument init
    // imports as alloc/init, so it must not be assumed equivalent to this factory.
    return [IOBluetoothPairingController pairingController];
}
