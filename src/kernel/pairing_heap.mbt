///|
/// A pairing heap, following Core_kernel's. A plain sorted array would give the
/// same order except among equal elements, and the order of equally sized
/// ranges decides which of them `find_moves` considers first.
priv struct HeapNode[A] {
  value : A
  mut child : HeapNode[A]?
  mut sibling : HeapNode[A]?
}

///|
priv struct PairingHeap[A] {
  cmp : (A, A) -> Int
  mut root : HeapNode[A]?
  mut length : Int
}

///|
fn[A] PairingHeap::new(cmp : (A, A) -> Int) -> PairingHeap[A] {
  { cmp, root: None, length: 0 }
}

///|
fn[A] add_child(node : HeapNode[A], child : HeapNode[A]) -> HeapNode[A] {
  child.sibling = node.child
  node.child = Some(child)
  node
}

///|
fn[A] PairingHeap::merge(
  self : PairingHeap[A],
  root1 : HeapNode[A]?,
  root2 : HeapNode[A]?,
) -> HeapNode[A]? {
  match (root1, root2) {
    (None, root) | (root, None) => root
    (Some(r1), Some(r2)) =>
      if (self.cmp)(r1.value, r2.value) < 0 {
        Some(add_child(r1, r2))
      } else {
        Some(add_child(r2, r1))
      }
  }
}

///|
fn[A] PairingHeap::add(self : PairingHeap[A], value : A) -> Unit {
  self.root = self.merge(self.root, Some({ value, child: None, sibling: None }))
  self.length += 1
}

///|
fn[A] disconnect_sibling(node : HeapNode[A]) -> HeapNode[A]? {
  let sibling = node.sibling
  node.sibling = None
  sibling
}

///|
/// Merges consecutive pairs of siblings, and then the merged pairs into a single
/// heap from the end of the list to the beginning. `merge` isn't associative, so
/// this order matters.
fn[A] PairingHeap::merge_pairs(
  self : PairingHeap[A],
  depth : Int,
  head : HeapNode[A]?,
) -> HeapNode[A]? {
  if depth >= 1000 {
    return self.allocating_merge_pairs(head)
  }
  guard head is Some(first) else { return None }
  guard disconnect_sibling(first) is Some(second) else { return head }
  let next = disconnect_sibling(second)
  let pair = self.merge(Some(first), Some(second))
  self.merge(pair, self.merge_pairs(depth + 1, next))
}

///|
/// `merge_pairs` for when recursing further could exhaust the stack.
fn[A] PairingHeap::allocating_merge_pairs(
  self : PairingHeap[A],
  head : HeapNode[A]?,
) -> HeapNode[A]? {
  let pairs = []
  let mut current = head
  while current is Some(first) {
    match disconnect_sibling(first) {
      None => {
        pairs.push(Some(first))
        current = None
      }
      Some(second) => {
        let next = disconnect_sibling(second)
        pairs.push(self.merge(Some(first), Some(second)))
        current = next
      }
    }
  }
  match pairs.pop() {
    None => None
    Some(last) => pairs.rev_fold(init=last, (acc, heap) => self.merge(acc, heap))
  }
}

///|
fn[A] PairingHeap::pop(self : PairingHeap[A]) -> A? {
  guard self.root is Some(root) else { return None }
  self.root = self.merge_pairs(0, root.child)
  self.length -= 1
  Some(root.value)
}
