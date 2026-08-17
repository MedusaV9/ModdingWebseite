import XCTest
@testable import SoooDreamyLogic

final class FIFOQueueTests: XCTestCase {
    func testDequeuesEveryCelebrationInArrivalOrder() {
        var queue = FIFOQueue<String>()
        queue.enqueue("level-2")
        queue.enqueue("badge-first-touch")
        queue.enqueue("badge-level-2")

        XCTAssertEqual(queue.dequeue(), "level-2")
        XCTAssertEqual(queue.dequeue(), "badge-first-touch")
        XCTAssertEqual(queue.dequeue(), "badge-level-2")
        XCTAssertNil(queue.dequeue())
    }

    func testRemoveAllClearsPendingItems() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        XCTAssertEqual(queue.count, 2)
        queue.removeAll()
        XCTAssertTrue(queue.isEmpty)
    }
}
