package ulist

// Compaction: turning soft deletes back into refunded storage.
//
// Delete is a soft delete. It clears the element's data but leaves the tree
// node in place, because the node's position IS the index: indices are the
// public addressing scheme, and moving a live element would silently
// invalidate an index some other realm is holding.
//
// That leaves reclaimable storage behind. On gno.land every byte of realm
// state locks GNOT, refunded to whoever signs the transaction that frees it,
// so those dead nodes are money sitting in the structure.
//
// Compact reclaims them without moving anything live, by dropping whole
// subtrees that contain no live element. Nothing live moves, so every index
// stays valid.
//
// # Which deletions can actually be compacted
//
// This is the counterintuitive part, and it decides whether compaction is
// worth anything at all. Index 0 is the root and index i sits at depth
// bitlen(i+1)-1, so the OLDEST indices are the ANCESTORS of the newest. A node
// is only freeable when its whole subtree is dead. Therefore:
//
//   - Deleting the oldest entries frees no nodes at all, however many you
//     delete, because every newer entry keeps their ancestors alive. An expiry
//     queue reaping oldest-first is exactly this case.
//   - Deleting the newest entries frees nodes immediately, because they are
//     the leaves.
//
// Measured on chain, 32 entries of 512 bytes each: deleting the oldest 16
// refunded 8,896 bytes and left Compactable at zero. Deleting the newest 16
// instead refunded the same 8,896 bytes and then Compact returned a further
// 27,679, because a ulist node costs far more than the payload it holds. The
// structure is roughly two thirds of the total cost, so being unable to
// compact leaves most of the money on the table.
//
// The practical rule: compaction pays in proportion to how much of the
// deepest layer is dead. Delete from the top down, or wait until a run of
// deletions reaches the leaves.
//
// Whether it is worth doing is not a question this package can answer, since
// it depends on the gas price of the day. Compactable reports the size of the
// prize as a free read so a caller can decide; gno.land/p/moul/x/storagecost/v0
// turns that count into a verdict in GNOT.

// Compactable reports how many tree nodes Compact would free right now.
//
// It reads and mutates nothing, so a caller can poll it to decide whether
// compaction is worth its gas before paying for it. Zero means every dead node
// still shares a subtree with a live element, and compacting would cost gas to
// free nothing.
func (l *List) Compactable() int {
	if l == nil || l.root == nil {
		return 0
	}
	// The root is never freed, so only its subtrees are counted.
	n, _ := prunableNodes(l.root)
	return n
}

// Compact frees every tree node whose subtree holds no live element, and
// returns the number of nodes freed.
//
// Indices are preserved exactly: TotalSize is unchanged, Size is unchanged,
// and every live element keeps the index it had. Appends continue from the
// same number.
//
// Deleted elements swept up by a Compact become permanently unrestorable:
// Set on such an index returns ErrOutOfBounds where before it would have
// restored the value. That is the trade the refund pays for, and it is the
// reason this behaviour is v1 rather than an addition to v0.
func (l *List) Compact() int {
	if l == nil || l.root == nil {
		return 0
	}
	// The root is deliberately never freed. findNode treats a nil root as an
	// empty list and returns the root for every index, so a tree that still
	// has a totalSize but no root would write index 0 on the next append.
	// Keeping one node costs a few dozen bytes and keeps that unreachable.
	freed, _ := pruneDead(l.root)
	return freed
}

// pruneDead drops n's fully dead subtrees, returning how many nodes were freed
// and whether n's own subtree is now dead. A dead subtree is one in which no
// node holds data.
func pruneDead(n *treeNode) (freed int, dead bool) {
	if n == nil {
		return 0, true
	}
	leftFreed, leftDead := pruneDead(n.left)
	rightFreed, rightDead := pruneDead(n.right)
	freed = leftFreed + rightFreed

	// A dead child's own descendants have already been counted and unlinked by
	// the recursive call, so the child itself is the one node left to free.
	if leftDead && n.left != nil {
		n.left = nil
		freed++
	}
	if rightDead && n.right != nil {
		n.right = nil
		freed++
	}
	return freed, n.data == nil && n.left == nil && n.right == nil
}

// prunableNodes is pruneDead without the mutation, so Compactable and Compact
// can never disagree about the count.
func prunableNodes(n *treeNode) (prunable int, dead bool) {
	if n == nil {
		return 0, true
	}
	leftPrunable, leftDead := prunableNodes(n.left)
	rightPrunable, rightDead := prunableNodes(n.right)
	prunable = leftPrunable + rightPrunable

	if leftDead && n.left != nil {
		prunable++
	}
	if rightDead && n.right != nil {
		prunable++
	}
	return prunable, n.data == nil &&
		(n.left == nil || leftDead) &&
		(n.right == nil || rightDead)
}
