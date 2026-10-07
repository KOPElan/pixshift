import XCTest
@testable import PicTool

final class BoundedTaskGroupTests: XCTestCase {
    func testPolicyAlwaysReturnsTwoThroughFourWorkers() {
        let gibibyte = UInt64(1_073_741_824)
        XCTAssertEqual(BatchConcurrencyPolicy.recommended(processorCount: 2, physicalMemory: 8 * gibibyte), 2)
        XCTAssertEqual(BatchConcurrencyPolicy.recommended(processorCount: 8, physicalMemory: 16 * gibibyte), 3)
        XCTAssertEqual(BatchConcurrencyPolicy.recommended(processorCount: 12, physicalMemory: 32 * gibibyte), 4)
        XCTAssertEqual(BatchConcurrencyPolicy.recommended(processorCount: 32, physicalMemory: 8 * gibibyte), 2)
    }

    func testRunnerNeverExceedsConfiguredLimit() async {
        let probe = ConcurrencyProbe()

        await BoundedTaskGroup.run(
            inputs: Array(0..<12),
            maxConcurrentTasks: 3,
            operation: { _, value in
                await probe.started()
                try? await Task.sleep(for: .milliseconds(20))
                await probe.finished()
                return value
            },
            onResult: { value in
                await probe.received(value)
            }
        )

        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.maximumActive, 3)
        XCTAssertEqual(snapshot.received.sorted(), Array(0..<12))
    }

    func testCancellationStopsSchedulingNewInputs() async {
        let probe = ConcurrencyProbe()
        let task = Task {
            await BoundedTaskGroup.run(
                inputs: Array(0..<20),
                maxConcurrentTasks: 2,
                operation: { _, value in
                    await probe.started()
                    try? await Task.sleep(for: .seconds(5))
                    await probe.finished()
                    return value
                },
                onResult: { value in
                    await probe.received(value)
                }
            )
        }

        while await probe.startedCount < 2 {
            await Task.yield()
        }
        task.cancel()
        await task.value

        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.startedCount, 2)
        XCTAssertLessThanOrEqual(snapshot.maximumActive, 2)
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private var maximumActive = 0
    private(set) var startedCount = 0
    private var values: [Int] = []

    func started() {
        active += 1
        startedCount += 1
        maximumActive = max(maximumActive, active)
    }

    func finished() {
        active -= 1
    }

    func received(_ value: Int) {
        values.append(value)
    }

    func snapshot() -> (maximumActive: Int, startedCount: Int, received: [Int]) {
        (maximumActive, startedCount, values)
    }
}
