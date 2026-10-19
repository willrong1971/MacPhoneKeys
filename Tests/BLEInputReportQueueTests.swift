import Foundation

@main
enum BLEInputReportQueueTests {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            guard condition else { fatalError(message) }
        }
        let release = Data(repeating: 0, count: 8)
        let downA = Data([0, 0, 0x04, 0, 0, 0, 0, 0])
        let downB = Data([0, 0, 0x05, 0, 0, 0, 0, 0])
        let downC = Data([0, 0, 0x06, 0, 0, 0, 0, 0])
        var queue = BLEInputReportQueue(capacity: 4)

        // A full Bluetooth buffer must leave the head intact for the ready callback.
        expect(queue.enqueue(downA), "accept A press")
        expect(queue.enqueue(release), "accept ordinary A release without cancellation")
        expect(queue.enqueue(downB), "accept B behind A release")
        expect(queue.nextReport == downA, "first attempt is A press")
        expect(queue.nextReport == downA, "failed attempt must preserve the same head")
        queue.didSubmitNext()
        expect(queue.nextReport == release, "ordinary release keeps its FIFO position")
        queue.didSubmitNext()
        expect(queue.nextReport == downB, "next key follows the earlier release")

        // Focus loss or stop must eliminate all unsent old text. New input must
        // wait behind the cancellation release even when that release is blocked.
        queue.cancel()
        expect(queue.count == 0, "cancellation drops unsent B")
        expect(queue.nextReport == release, "cancellation prioritizes release")
        expect(queue.enqueue(downC), "new session may queue C")
        expect(queue.nextReport == release, "C cannot overtake blocked release")
        queue.didSubmitNext()
        expect(queue.nextReport == downC, "only new-session C remains after release")
        queue.didSubmitNext()
        expect(queue.nextReport == nil, "cancelled B must never reappear")

        // Overflow is fail-closed: no accepted old text can drain afterward.
        var bounded = BLEInputReportQueue(capacity: 2)
        expect(bounded.enqueue(downA), "bounded accepts first report")
        expect(bounded.enqueue(release), "bounded accepts second report")
        expect(!bounded.enqueue(downB), "overflow is rejected")
        expect(bounded.count == 0, "overflow clears previous text")
        expect(bounded.nextReport == release, "overflow retains release only")
        bounded.didSubmitNext()
        expect(bounded.nextReport == nil, "overflow leaves no delayed keydown")

        // Repeated cancellation stays idempotent and never removes its release.
        bounded.cancel()
        bounded.cancel()
        expect(bounded.nextReport == release, "repeated cancellation retains release")
        bounded.didSubmitNext()
        expect(bounded.nextReport == nil, "one submitted release satisfies cancellation")
        print("PASS: \(checks) BLE FIFO/backpressure safety checks")
    }
}
