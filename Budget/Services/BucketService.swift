import Foundation
import SwiftData

/// Operations on the intent layer: allocations, bucket moves, Unallocated math.
@MainActor
struct BucketService {
    let context: ModelContext

    // MARK: - Allocations

    /// Move `amount` from Unallocated → bucket. Negative goes the other way.
    /// Used by the +/- buttons on the Plan canvas.
    func allocate(
        _ amount: Decimal,
        to bucket: Bucket,
        reason: AllocationReason = .manualMove,
        note: String? = nil
    ) throws {
        bucket.allocatedAmount += amount
        let alloc = Allocation(
            bucket: bucket,
            amount: amount,
            reason: reason,
            occurredAt: Date(),
            note: note
        )
        context.insert(alloc)
        try context.save()
    }

    /// Move `amount` between two buckets. Records two paired Allocation rows so
    /// either side can be audited.
    func move(_ amount: Decimal, from source: Bucket, to destination: Bucket) throws {
        source.allocatedAmount -= amount
        destination.allocatedAmount += amount
        context.insert(Allocation(
            bucket: source, amount: -amount,
            reason: .manualMove, relatedBucket: destination,
            occurredAt: Date()
        ))
        context.insert(Allocation(
            bucket: destination, amount: amount,
            reason: .manualMove, relatedBucket: source,
            occurredAt: Date()
        ))
        try context.save()
    }

    /// Auto-allocation hook: when a transaction is logged with a category that
    /// matches a bucket's `linkedCategory`, the bucket's allocated_amount is
    /// reduced by the transaction amount and an Allocation row is recorded
    /// with reason=.transaction.
    func recordTransactionAllocation(transaction: Transaction) throws -> Bucket? {
        guard let category = transaction.category else { return nil }
        guard let bucket = try findActiveBucket(for: category) else { return nil }

        // Outflow → reduce allocation. Inflow → increase (rare; e.g. refund into bucket).
        let signed = transaction.direction == .outflow ? -transaction.amount : transaction.amount
        bucket.allocatedAmount += signed

        let alloc = Allocation(
            bucket: bucket,
            amount: signed,
            reason: .transaction,
            transaction: transaction,
            occurredAt: transaction.occurredAt
        )
        context.insert(alloc)

        // Link the transaction back to the bucket for easier queries.
        transaction.bucket = bucket

        try context.save()
        return bucket
    }

    // MARK: - Lookups

    /// First active, non-deleted bucket whose linkedCategory matches.
    /// Personal-scale data; in-memory filter is fine.
    func findActiveBucket(for category: Category) throws -> Bucket? {
        let buckets = try context.fetch(
            FetchDescriptor<Bucket>(predicate: #Predicate { !$0.isDeleted })
        )
        let catID = category.id
        return buckets.first { $0.linkedCategory?.id == catID }
    }

    // MARK: - Unallocated math

    /// Sum of all active accounts minus sum of all non-deleted buckets'
    /// allocated_amount. This is the "Unallocated" pool shown atop the canvas.
    func unallocatedTotal() throws -> Decimal {
        let accounts = try context.fetch(
            FetchDescriptor<Account>(predicate: #Predicate { $0.isActive })
        )
        let totalCash = accounts.map(\.realBalance).reduce(Decimal(0), +)

        let buckets = try context.fetch(
            FetchDescriptor<Bucket>(predicate: #Predicate { !$0.isDeleted })
        )
        let totalAlloc = buckets.map(\.allocatedAmount).reduce(Decimal(0), +)

        return totalCash - totalAlloc
    }

    // MARK: - Lifecycle

    /// Soft-delete a bucket. Used for goals (per design, deletion is the
    /// abandon/complete action; we keep the row so history can be queried).
    func softDelete(_ bucket: Bucket) throws {
        bucket.isDeleted = true
        bucket.deletedAt = Date()
        try context.save()
    }
}
