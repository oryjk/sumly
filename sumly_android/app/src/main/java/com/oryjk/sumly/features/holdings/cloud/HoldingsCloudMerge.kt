package com.oryjk.sumly.features.holdings.cloud

import java.util.UUID

enum class HoldingsConflictChoice { Local, Cloud }

internal data class HoldingsMergeResult(val document: HoldingsCloudDocument, val conflicts: Set<UUID>)

internal object HoldingsCloudMerge {
    fun merge(
        base: HoldingsCloudDocument,
        local: HoldingsCloudDocument,
        remote: HoldingsCloudDocument,
        choice: HoldingsConflictChoice?,
    ): HoldingsMergeResult {
        val records = base.records + local.records + remote.records
        val parents = mutableMapOf<UUID, UUID>()
        fun root(id: UUID): UUID {
            var current = id
            while (true) {
                val next = parents[current] ?: return current
                if (next == current) return current
                current = next
            }
        }

        // Connected purchase families span all versions, even if one device
        // rewrote a family link. A partial sale must never merge with both splits.
        for (record in records) {
            val related = record.holding.purchaseId ?: continue
            val child = root(record.id)
            val parent = root(related)
            if (child != parent) parents[child] = parent
        }

        fun groups(document: HoldingsCloudDocument) = document.records.groupBy { root(it.id) }
            .mapValues { (_, values) -> values.sortedBy { it.id.toString() } }

        val baseline = groups(base)
        val ours = groups(local)
        val theirs = groups(remote)
        val conflicts = mutableSetOf<UUID>()
        val allFamilies = baseline.keys + ours.keys + theirs.keys
        val resolved = allFamilies.flatMap { family ->
            val before = baseline[family].orEmpty()
            val left = ours[family].orEmpty()
            val right = theirs[family].orEmpty()
            when {
                left == right -> left
                left == before -> right
                right == before -> left
                else -> {
                    conflicts.addAll((before + left + right).map { it.id })
                    if (choice == HoldingsConflictChoice.Cloud) right else left
                }
            }
        }
        return HoldingsMergeResult(HoldingsCloudDocument(local.books + remote.books, resolved).normalized(), conflicts)
    }
}
