//
//  TaskCoalescer.swift
//  Wishlist
//
//  Two rows asking for the same image, or a refresh landing on an item that is
//  already refreshing, should cost one network request, not two. Callers with
//  the same key share a single in-flight task.
//

import Foundation

actor TaskCoalescer<Value: Sendable> {
    private var inFlight: [String: Task<Value, Error>] = [:]

    func run(
        key: String,
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task.detached(priority: priority) {
            try await operation()
        }
        inFlight[key] = task
        do {
            let value = try await task.value
            inFlight[key] = nil
            return value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func cancelAll() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }
}
