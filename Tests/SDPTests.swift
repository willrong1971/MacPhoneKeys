import Foundation
import IOBluetooth

/// Offline, deterministic schema/descriptor validation. Does not start Bluetooth.
/// xcrun swiftc -D HID_SDP_TESTS -parse-as-library Sources/BluetoothKeyboard.swift \
///   Tests/SDPTests.swift -o build/SDPTests -framework Foundation -framework IOBluetooth
/// build/SDPTests
@main struct SDPTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func l2capPSMs(_ element: IOBluetoothSDPDataElement?) -> [UInt16] {
        guard let array = element?.getArrayValue() as? [IOBluetoothSDPDataElement] else { return [] }
        if array.count >= 2, let uuid = array[0].getUUIDValue(),
           uuid.isEqual(to: IOBluetoothSDPUUID(uuid16: 0x0100)), let number = array[1].getNumberValue() {
            return [number.uint16Value]
        }
        return array.flatMap { l2capPSMs($0) }
    }

    static func main() {
        let dictionary = BluetoothKeyboard.sdpDictionaryForTests()
        let local = dictionary["LocalAttributes"] as? [String: Any]
        require(local?["Persistent"] as? Bool == false, "SDP must be temporary")
        var elements: [UInt16: IOBluetoothSDPDataElement] = [:]
        for (key, value) in dictionary where key != "LocalAttributes" {
            guard let attribute = UInt16(key.prefix(4), radix: 16),
                  let object = value as AnyObject as? NSObject,
                  let element = IOBluetoothSDPDataElement(elementValue: object) else {
                require(false, "Apple SDP parser rejected \(key)")
                return
            }
            elements[attribute] = element
        }
        require(elements.count == 24, "Expected 24 SDP attributes")
        require(l2capPSMs(elements[0x0004]) == [0x11], "HID control PSM")
        require(l2capPSMs(elements[0x000D]) == [0x13], "HID interrupt PSM")
        guard let descriptors = elements[0x0206]?.getArrayValue() as? [IOBluetoothSDPDataElement],
              let pair = descriptors.first?.getArrayValue() as? [IOBluetoothSDPDataElement], pair.count == 2,
              let descriptor = pair[1].getValue() as? Data else {
            require(false, "HID report descriptor must preserve binary bytes")
            return
        }
        require(pair[0].getNumberValue()?.uint8Value == 0x22, "Descriptor type must be Report")
        require(pair[1].getTypeDescriptor() == 4, "Descriptor SDP element type must be text/binary string")
        require(descriptor.count == 63, "Boot keyboard descriptor length")
        require(descriptor == Data(BluetoothKeyboard.descriptorForTests), "SDP must preserve every descriptor byte")
        let bytes = Array(descriptor)
        require(bytes.containsSubsequence([0x25, 0x67]), "Logical maximum must cover keypad equals (0x67)")
        require(bytes.containsSubsequence([0x29, 0x67]), "Usage maximum must cover keypad equals (0x67)")
        require(!bytes.contains(0x85), "Descriptor must have no Report ID")
        let keyboard = BluetoothKeyboard()
        require(keyboard.responds(to: NSSelectorFromString("l2capChannelOpenComplete:status:")), "Open callback Objective-C selector")
        require(keyboard.responds(to: NSSelectorFromString("l2capChannelData:data:length:")), "Data callback Objective-C selector")
        require(keyboard.responds(to: NSSelectorFromString("l2capChannelClosed:")), "Close callback Objective-C selector")
        print("PASS: 24 SDP attributes; temporary service; PSM 0x11/0x13; 63-byte descriptor preserved; usage/logical max 0x67; no Report ID; delegate selectors exported.")
    }
}

private extension Array where Element: Equatable {
    func containsSubsequence(_ sequence: [Element]) -> Bool {
        guard !sequence.isEmpty, count >= sequence.count else { return false }
        return (0...(count - sequence.count)).contains { Array(self[$0..<($0 + sequence.count)]) == sequence }
    }
}
