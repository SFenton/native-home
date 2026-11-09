import HassCore
import HassDemoHouse
import Testing

/// A Swift Testing trait that runs each test of a suite inside `HouseConfigSource.$scoped.withValue(DemoHouse.source)`,
/// so every `*Config` facade the test reads answers with the demo house, and parallel tests never see each other's source.
///
/// ```swift
/// @Suite(.demoHouse) struct MyConfigTests { ... }
/// ```
///
/// The task-local does not cross a plain `DispatchQueue.main.async` hop; a test that hops the main queue injects
/// ``DemoHouse/source`` instead.
public struct DemoHouseTrait: SuiteTrait, TestTrait, TestScoping {
    public let isRecursive = true

    public init() {}

    public func provideScope(
        for test: Test, testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            try await function()
        }
    }
}

public extension Trait where Self == DemoHouseTrait {
    /// Scopes the test or suite to ``DemoHouse/source``.
    static var demoHouse: DemoHouseTrait { DemoHouseTrait() }
}
