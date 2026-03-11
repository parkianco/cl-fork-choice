;;;; test/tree-tests.lisp - Tests for block tree operations

(in-package #:cl-fork-choice.tests)

(defun make-test-hash (n)
  "Create a test hash from an integer."
  (let ((hash (make-array 32 :element-type '(unsigned-byte 8) :initial-element 0)))
    (setf (aref hash 0) (mod n 256))
    (setf (aref hash 1) (mod (floor n 256) 256))
    hash))

(deftest test-make-block-tree
  (let ((genesis-hash (make-test-hash 0)))
    (let ((tree (make-block-tree :genesis-hash genesis-hash)))
      (assert-true tree "Tree should be created")
      (assert-equal 1 (block-tree-node-count tree) "Should have genesis node")
      (assert-true (hash-equal-p genesis-hash (block-tree-root tree))
                   "Root should be genesis"))))

(deftest test-tree-add-node
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1)))
    (let ((node (tree-add-node tree block1-hash genesis-hash 1 :weight 10)))
      (assert-true node "Node should be added")
      (assert-equal 2 (block-tree-node-count tree) "Should have 2 nodes")
      (assert-equal 1 (tree-node-height node) "Height should be 1")
      (assert-equal 10 (tree-node-weight node) "Weight should be 10"))))

(deftest test-tree-add-duplicate
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1)))
    (tree-add-node tree block1-hash genesis-hash 1)
    (let ((dup (tree-add-node tree block1-hash genesis-hash 2)))
      (assert-nil dup "Duplicate should not be added"))))

(deftest test-tree-remove-node
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1)))
    (tree-add-node tree block1-hash genesis-hash 1)
    (assert-true (tree-remove-node tree block1-hash) "Should remove leaf")
    (assert-equal 1 (block-tree-node-count tree) "Should have 1 node")))

(deftest test-tree-cannot-remove-root
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash)))
    (assert-nil (tree-remove-node tree genesis-hash) "Cannot remove root")))

(deftest test-tree-get-ancestors
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1))
         (block2-hash (make-test-hash 2)))
    (tree-add-node tree block1-hash genesis-hash 1)
    (tree-add-node tree block2-hash block1-hash 2)
    (let ((ancestors (tree-get-ancestors tree block2-hash)))
      (assert-equal 2 (length ancestors) "Should have 2 ancestors"))))

(deftest test-tree-common-ancestor
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1))
         (block2-hash (make-test-hash 2)))
    (tree-add-node tree block1-hash genesis-hash 1)
    (tree-add-node tree block2-hash genesis-hash 2)
    (let ((ancestor (tree-common-ancestor tree block1-hash block2-hash)))
      (assert-true (hash-equal-p genesis-hash ancestor)
                   "Common ancestor should be genesis"))))

(deftest test-hash-utilities
  (let ((hash (make-test-hash 42)))
    (let ((hex (hash-to-hex hash)))
      (assert-true (stringp hex) "Should return string")
      (assert-equal 64 (length hex) "Should be 64 chars")
      (let ((back (hex-to-hash hex)))
        (assert-true (hash-equal-p hash back) "Round-trip should work")))))

(deftest test-tree-is-ancestor-p
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1))
         (block2-hash (make-test-hash 2)))
    (tree-add-node tree block1-hash genesis-hash 1)
    (tree-add-node tree block2-hash block1-hash 2)
    (assert-true (tree-is-ancestor-p tree genesis-hash block2-hash)
                 "Genesis is ancestor of block2")
    (assert-true (tree-is-ancestor-p tree block1-hash block2-hash)
                 "Block1 is ancestor of block2")
    (assert-nil (tree-is-ancestor-p tree block2-hash genesis-hash)
                "Block2 is not ancestor of genesis")))

(deftest test-weight-propagation
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1)))
    (tree-add-node tree block1-hash genesis-hash 1 :weight 100)
    (let ((genesis-node (tree-get-node tree genesis-hash)))
      (assert-true (>= (tree-node-cumulative-weight genesis-node) 100)
                   "Genesis should have accumulated weight"))))

(deftest test-tree-tip-count
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash)))
    (assert-equal 1 (tree-tip-count tree) "Should have 1 tip (genesis)")
    (tree-add-node tree (make-test-hash 1) genesis-hash 1)
    (assert-equal 1 (tree-tip-count tree) "Still 1 tip after linear chain")
    (tree-add-node tree (make-test-hash 2) genesis-hash 2)
    (assert-equal 2 (tree-tip-count tree) "2 tips after fork")))
