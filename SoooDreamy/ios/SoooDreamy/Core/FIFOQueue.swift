import Foundation

/// Small pure FIFO used for ceremonies that may arrive in one server write
/// (for example a level-up plus multiple badges). It intentionally exposes no
/// random removal, so callers cannot accidentally reorder celebrations.
struct FIFOQueue<Element> {
    private var storage: [Element] = []

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }

    mutating func enqueue(_ element: Element) {
        storage.append(element)
    }

    mutating func dequeue() -> Element? {
        guard !storage.isEmpty else { return nil }
        return storage.removeFirst()
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepingCapacity)
    }
}
