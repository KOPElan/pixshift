import Foundation

enum BatchConcurrencyPolicy {
    static func recommended(
        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Int {
        let cpuLimit: Int
        switch processorCount {
        case ..<6: cpuLimit = 2
        case 6..<10: cpuLimit = 3
        default: cpuLimit = 4
        }

        let gibibyte = UInt64(1_073_741_824)
        let memoryLimit: Int
        switch physicalMemory {
        case ..<(12 * gibibyte): memoryLimit = 2
        case ..<(24 * gibibyte): memoryLimit = 3
        default: memoryLimit = 4
        }
        return min(cpuLimit, memoryLimit)
    }
}

enum BoundedTaskGroup {
    static func run<Input: Sendable, Output: Sendable>(
        inputs: [Input],
        maxConcurrentTasks: Int,
        operation: @escaping @Sendable (_ workerIndex: Int, _ input: Input) async -> Output,
        onResult: @escaping @Sendable (Output) async -> Void
    ) async {
        guard !inputs.isEmpty else { return }
        let limit = min(inputs.count, max(1, maxConcurrentTasks))
        let queue = BoundedInputQueue(inputs)

        await withTaskGroup(of: Void.self) { group in
            for workerIndex in 0..<limit {
                group.addTask {
                    while !Task.isCancelled, let input = await queue.next() {
                        guard !Task.isCancelled else { break }
                        let result = await operation(workerIndex, input)
                        await onResult(result)
                    }
                }
            }
        }
    }
}

private actor BoundedInputQueue<Element: Sendable> {
    private let elements: [Element]
    private var nextIndex = 0

    init(_ elements: [Element]) {
        self.elements = elements
    }

    func next() -> Element? {
        guard nextIndex < elements.count else { return nil }
        defer { nextIndex += 1 }
        return elements[nextIndex]
    }
}
