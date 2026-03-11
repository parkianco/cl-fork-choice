;;;; tree.lisp - Block tree data structure for fork choice
;;;;
;;;; Implements the block tree representation for fork choice.
;;;; The block tree represents all known blocks organized by parent-child
;;;; relationships, enabling efficient fork choice rule evaluation.

(in-package #:cl-fork-choice)

;;; ============================================================================
;;; Tree Node Structure
;;; ============================================================================

(defstruct (tree-node
            (:constructor %make-tree-node)
            (:copier nil)
            (:print-function print-tree-node))
  "A node in the block tree representing a single block."
  ;; Block identification
  (block-hash nil :type (or null (simple-array (unsigned-byte 8) (32))))
  (parent-hash nil :type (or null (simple-array (unsigned-byte 8) (32))))
  (slot 0 :type (unsigned-byte 64))
  (height 0 :type (unsigned-byte 64))
  ;; Weight for fork choice
  (weight 0 :type integer)
  (cumulative-weight 0 :type integer)
  ;; Tree structure
  (children nil :type list)
  (best-descendant nil :type (or null (simple-array (unsigned-byte 8) (32))))
  ;; Finality status
  (justified-p nil :type boolean)
  (finalized-p nil :type boolean)
  ;; Proposer boost (ephemeral)
  (proposer-boost 0 :type integer)
  ;; Cached data
  (state-root nil :type (or null (simple-array (unsigned-byte 8) (32))))
  (timestamp 0 :type (unsigned-byte 64))
  (validity :unknown :type (member :unknown :valid :invalid)))

(defun make-tree-node (&key block-hash parent-hash slot height weight
                         state-root timestamp)
  "Create a new tree node with the given parameters."
  (%make-tree-node
   :block-hash block-hash
   :parent-hash parent-hash
   :slot slot
   :height height
   :weight (or weight 0)
   :cumulative-weight (or weight 0)
   :state-root state-root
   :timestamp (or timestamp 0)))

(defun print-tree-node (node stream depth)
  "Print a tree node summary."
  (declare (ignore depth))
  (format stream "#<TREE-NODE slot=~D height=~D weight=~D children=~D~A>"
          (tree-node-slot node)
          (tree-node-height node)
          (tree-node-cumulative-weight node)
          (length (tree-node-children node))
          (cond ((tree-node-finalized-p node) " FINAL")
                ((tree-node-justified-p node) " JUST")
                (t ""))))

;;; ============================================================================
;;; Block Tree Structure
;;; ============================================================================

(defstruct (block-tree
            (:constructor %make-block-tree)
            (:copier nil)
            (:print-function print-block-tree))
  "The complete block tree for fork choice."
  ;; Core data
  (root nil :type (or null (simple-array (unsigned-byte 8) (32))))
  (nodes (make-hash-table :test 'equalp) :type hash-table)
  ;; Checkpoints
  (justified-checkpoint nil :type (or null finality-checkpoint))
  (finalized-checkpoint nil :type (or null finality-checkpoint))
  ;; Ephemeral state
  (proposer-boost-root nil :type (or null (simple-array (unsigned-byte 8) (32))))
  (head-cache nil :type (or null (simple-array (unsigned-byte 8) (32))))
  (head-cache-valid nil :type boolean)
  ;; Synchronization
  (lock (make-tree-lock) :type t)
  ;; Statistics
  (node-count 0 :type (unsigned-byte 64))
  (max-height 0 :type (unsigned-byte 64))
  (total-weight 0 :type integer))

(defun make-tree-lock ()
  "Create a lock for tree synchronization."
  #+sbcl (sb-thread:make-mutex :name "block-tree-lock")
  #-sbcl nil)

(defun make-block-tree (&key genesis-hash genesis-state-root)
  "Create a new block tree with genesis block."
  (let ((tree (%make-block-tree)))
    (when genesis-hash
      (let ((genesis-node (make-tree-node
                           :block-hash genesis-hash
                           :parent-hash nil
                           :slot +genesis-slot+
                           :height 0
                           :weight 0
                           :state-root genesis-state-root)))
        (setf (tree-node-justified-p genesis-node) t)
        (setf (tree-node-finalized-p genesis-node) t)
        (setf (gethash genesis-hash (block-tree-nodes tree)) genesis-node)
        (setf (block-tree-root tree) genesis-hash)
        (setf (block-tree-node-count tree) 1)))
    tree))

(defun print-block-tree (tree stream depth)
  "Print a block tree summary."
  (declare (ignore depth))
  (format stream "#<BLOCK-TREE nodes=~D height=~D>"
          (block-tree-node-count tree)
          (block-tree-max-height tree)))

;;; ============================================================================
;;; Thread-Safe Macros
;;; ============================================================================

(defmacro with-tree-lock ((tree) &body body)
  "Execute body with tree lock held."
  #+sbcl
  `(sb-thread:with-mutex ((block-tree-lock ,tree))
     ,@body)
  #-sbcl
  `(progn ,@body))

;;; ============================================================================
;;; Hash Utilities
;;; ============================================================================

(defun hash-equal-p (h1 h2)
  "Compare two 32-byte hashes for equality."
  (and h1 h2
       (= (length h1) (length h2) 32)
       (loop for i from 0 below 32
             always (= (aref h1 i) (aref h2 i)))))

(defun hash-to-hex (hash)
  "Convert a hash to hexadecimal string."
  (when hash
    (with-output-to-string (s)
      (loop for byte across hash
            do (format s "~2,'0x" byte)))))

(defun hex-to-hash (hex)
  "Convert hexadecimal string to hash."
  (when (and hex (= (length hex) 64))
    (let ((hash (make-array 32 :element-type '(unsigned-byte 8))))
      (loop for i from 0 below 32
            do (setf (aref hash i)
                     (parse-integer hex :start (* i 2) :end (+ (* i 2) 2) :radix 16)))
      hash)))

;;; ============================================================================
;;; Node Operations
;;; ============================================================================

(defun tree-add-node (tree block-hash parent-hash slot
                      &key weight state-root timestamp)
  "Add a new node to the block tree."
  (with-tree-lock (tree)
    ;; Check for duplicate
    (when (gethash block-hash (block-tree-nodes tree))
      (return-from tree-add-node nil))

    ;; Get parent (must exist for non-root)
    (let ((parent-node (when parent-hash
                         (gethash parent-hash (block-tree-nodes tree)))))
      (when (and parent-hash (not parent-node))
        (return-from tree-add-node nil))

      ;; Create new node
      (let* ((height (if parent-node
                         (1+ (tree-node-height parent-node))
                         0))
             (node (make-tree-node
                    :block-hash block-hash
                    :parent-hash parent-hash
                    :slot slot
                    :height height
                    :weight (or weight 0)
                    :state-root state-root
                    :timestamp (or timestamp 0))))

        ;; Mark validity based on parent
        (when parent-node
          (setf (tree-node-validity node)
                (if (eq (tree-node-validity parent-node) :invalid)
                    :invalid
                    :unknown)))

        ;; Add to tree
        (setf (gethash block-hash (block-tree-nodes tree)) node)
        (incf (block-tree-node-count tree))

        ;; Update parent's children
        (when parent-node
          (push block-hash (tree-node-children parent-node)))

        ;; Update tree stats
        (when (> height (block-tree-max-height tree))
          (setf (block-tree-max-height tree) height))
        (incf (block-tree-total-weight tree) (tree-node-weight node))

        ;; Invalidate head cache
        (setf (block-tree-head-cache-valid tree) nil)

        ;; Propagate weight to ancestors
        (propagate-weight-up tree block-hash)

        ;; Call hook
        (when *on-block-added*
          (funcall *on-block-added* node tree))

        node))))

(defun tree-remove-node (tree block-hash)
  "Remove a leaf node from the block tree."
  (with-tree-lock (tree)
    (let ((node (gethash block-hash (block-tree-nodes tree))))
      (unless node
        (return-from tree-remove-node nil))

      ;; Cannot remove non-leaf nodes
      (when (tree-node-children node)
        (return-from tree-remove-node nil))

      ;; Cannot remove root
      (when (hash-equal-p block-hash (block-tree-root tree))
        (return-from tree-remove-node nil))

      ;; Remove from parent's children
      (let ((parent (gethash (tree-node-parent-hash node)
                             (block-tree-nodes tree))))
        (when parent
          (setf (tree-node-children parent)
                (remove block-hash (tree-node-children parent)
                        :test #'hash-equal-p))))

      ;; Remove from tree
      (remhash block-hash (block-tree-nodes tree))
      (decf (block-tree-node-count tree))
      (decf (block-tree-total-weight tree) (tree-node-weight node))

      ;; Invalidate head cache
      (setf (block-tree-head-cache-valid tree) nil)

      t)))

(defun tree-get-node (tree block-hash)
  "Get a node from the tree by its hash."
  (gethash block-hash (block-tree-nodes tree)))

(defun tree-has-node-p (tree block-hash)
  "Check if a node exists in the tree."
  (not (null (gethash block-hash (block-tree-nodes tree)))))

(defun tree-get-children (tree block-hash)
  "Get all children of a node."
  (let ((node (tree-get-node tree block-hash)))
    (when node
      (mapcar (lambda (child-hash)
                (gethash child-hash (block-tree-nodes tree)))
              (tree-node-children node)))))

(defun tree-get-parent (tree block-hash)
  "Get the parent of a node."
  (let ((node (tree-get-node tree block-hash)))
    (when (and node (tree-node-parent-hash node))
      (gethash (tree-node-parent-hash node) (block-tree-nodes tree)))))

;;; ============================================================================
;;; Ancestor/Descendant Operations
;;; ============================================================================

(defun tree-get-ancestors (tree block-hash &key (max-depth nil) (include-self nil))
  "Get all ancestors of a node up to max-depth."
  (let ((ancestors nil)
        (count 0)
        (current-hash block-hash))

    ;; Optionally include self
    (when (and include-self (tree-get-node tree block-hash))
      (push (tree-get-node tree block-hash) ancestors)
      (incf count))

    ;; Walk up the tree
    (loop
      (when (and max-depth (>= count max-depth))
        (return))
      (let ((node (tree-get-node tree current-hash)))
        (unless node
          (return))
        (let ((parent-hash (tree-node-parent-hash node)))
          (unless parent-hash
            (return))
          (let ((parent (tree-get-node tree parent-hash)))
            (unless parent
              (return))
            (push parent ancestors)
            (incf count)
            (setf current-hash parent-hash)))))

    (nreverse ancestors)))

(defun tree-get-descendants (tree block-hash &key (max-depth nil))
  "Get all descendants of a node up to max-depth using BFS."
  (let ((descendants nil)
        (queue (list (cons block-hash 0))))

    (loop while queue do
      (destructuring-bind (current-hash . depth) (pop queue)
        (when (or (null max-depth) (<= depth max-depth))
          (let ((node (tree-get-node tree current-hash)))
            (when node
              (unless (hash-equal-p current-hash block-hash)
                (push node descendants))
              (dolist (child-hash (tree-node-children node))
                (push (cons child-hash (1+ depth)) queue)))))))

    (nreverse descendants)))

;;; ============================================================================
;;; Tree Properties
;;; ============================================================================

(defun tree-height (tree)
  "Get the maximum height of the tree."
  (block-tree-max-height tree))

(defun tree-tip-count (tree)
  "Get the number of tips (leaf nodes) in the tree."
  (let ((count 0))
    (maphash (lambda (hash node)
               (declare (ignore hash))
               (when (null (tree-node-children node))
                 (incf count)))
             (block-tree-nodes tree))
    count))

(defun tree-is-ancestor-p (tree ancestor-hash descendant-hash)
  "Check if ancestor-hash is an ancestor of descendant-hash."
  (when (hash-equal-p ancestor-hash descendant-hash)
    (return-from tree-is-ancestor-p t))

  (let ((current-hash descendant-hash))
    (loop
      (let ((node (tree-get-node tree current-hash)))
        (unless node
          (return-from tree-is-ancestor-p nil))
        (let ((parent-hash (tree-node-parent-hash node)))
          (unless parent-hash
            (return-from tree-is-ancestor-p nil))
          (when (hash-equal-p parent-hash ancestor-hash)
            (return-from tree-is-ancestor-p t))
          (setf current-hash parent-hash))))))

(defun tree-get-path (tree from-hash to-hash)
  "Get the path between two nodes.
Returns (values up-path down-path common-ancestor-hash)."
  (let ((from-ancestors (make-hash-table :test 'equalp))
        (from-path nil)
        (to-path nil))

    ;; Build ancestor map for from-hash
    (let ((current-hash from-hash)
          (distance 0))
      (loop
        (unless current-hash
          (return))
        (setf (gethash current-hash from-ancestors) distance)
        (let ((node (tree-get-node tree current-hash)))
          (unless node
            (return))
          (setf current-hash (tree-node-parent-hash node))
          (incf distance))))

    ;; Find common ancestor by walking from to-hash
    (let ((current-hash to-hash)
          (common-ancestor nil))
      (loop
        (unless current-hash
          (return))
        (when (gethash current-hash from-ancestors)
          (setf common-ancestor current-hash)
          (return))
        (push current-hash to-path)
        (let ((node (tree-get-node tree current-hash)))
          (unless node
            (return))
          (setf current-hash (tree-node-parent-hash node))))

      ;; Build from-path
      (setf current-hash from-hash)
      (loop while (and current-hash (not (hash-equal-p current-hash common-ancestor)))
            do (push current-hash from-path)
               (let ((node (tree-get-node tree current-hash)))
                 (setf current-hash (when node (tree-node-parent-hash node)))))

      (values (nreverse from-path)
              to-path
              common-ancestor))))

(defun tree-common-ancestor (tree hash1 hash2)
  "Find the common ancestor of two nodes."
  (let ((node1 (tree-get-node tree hash1))
        (node2 (tree-get-node tree hash2)))
    (unless (and node1 node2)
      (return-from tree-common-ancestor nil))

    ;; Walk deeper node up to same height
    (let ((h1 (tree-node-height node1))
          (h2 (tree-node-height node2))
          (current1 hash1)
          (current2 hash2))

      ;; Equalize heights
      (loop while (> h1 h2)
            do (let ((node (tree-get-node tree current1)))
                 (when node
                   (setf current1 (tree-node-parent-hash node))
                   (decf h1))))

      (loop while (> h2 h1)
            do (let ((node (tree-get-node tree current2)))
                 (when node
                   (setf current2 (tree-node-parent-hash node))
                   (decf h2))))

      ;; Walk both up together
      (loop
        (when (hash-equal-p current1 current2)
          (return-from tree-common-ancestor current1))
        (let ((n1 (tree-get-node tree current1))
              (n2 (tree-get-node tree current2)))
          (unless (and n1 n2)
            (return-from tree-common-ancestor nil))
          (setf current1 (tree-node-parent-hash n1))
          (setf current2 (tree-node-parent-hash n2)))))))

(defun tree-subtree-weight (tree root-hash)
  "Calculate the total weight of a subtree."
  (let ((node (tree-get-node tree root-hash)))
    (when node
      (tree-node-cumulative-weight node))))

;;; ============================================================================
;;; Tree Traversal
;;; ============================================================================

(defun tree-walk-up (tree start-hash callback &key (max-depth nil))
  "Walk up the tree from start to root, calling callback on each node."
  (let ((current-hash start-hash)
        (depth 0))
    (loop
      (when (and max-depth (>= depth max-depth))
        (return nil))
      (let ((node (tree-get-node tree current-hash)))
        (unless node
          (return nil))
        (let ((result (funcall callback node depth)))
          (unless result
            (return nil))
          (let ((parent-hash (tree-node-parent-hash node)))
            (unless parent-hash
              (return result))
            (setf current-hash parent-hash)
            (incf depth)))))))

(defun tree-walk-down (tree start-hash callback &key (max-depth nil))
  "Walk down the tree using BFS, calling callback on each node."
  (let ((visited 0)
        (queue (list (cons start-hash 0))))
    (loop while queue do
      (destructuring-bind (current-hash . depth) (pop queue)
        (when (or (null max-depth) (< depth max-depth))
          (let ((node (tree-get-node tree current-hash)))
            (when node
              (incf visited)
              (when (funcall callback node depth)
                (dolist (child-hash (tree-node-children node))
                  (push (cons child-hash (1+ depth)) queue))))))))
    visited))

(defun tree-map-nodes (tree function)
  "Apply function to all nodes in the tree."
  (let ((results nil))
    (maphash (lambda (hash node)
               (declare (ignore hash))
               (push (funcall function node) results))
             (block-tree-nodes tree))
    (nreverse results)))

(defun tree-fold-nodes (tree function initial-value)
  "Fold over all nodes in the tree."
  (let ((acc initial-value))
    (maphash (lambda (hash node)
               (declare (ignore hash))
               (setf acc (funcall function acc node)))
             (block-tree-nodes tree))
    acc))

(defun tree-filter-nodes (tree predicate)
  "Filter nodes by predicate."
  (let ((results nil))
    (maphash (lambda (hash node)
               (declare (ignore hash))
               (when (funcall predicate node)
                 (push node results)))
             (block-tree-nodes tree))
    results))

;;; ============================================================================
;;; Debugging
;;; ============================================================================

(defun print-tree-summary (tree &optional (stream *standard-output*))
  "Print a summary of the block tree."
  (format stream "~&=== Block Tree Summary ===~%")
  (format stream "Nodes: ~D~%" (block-tree-node-count tree))
  (format stream "Max Height: ~D~%" (block-tree-max-height tree))
  (format stream "Tips: ~D~%" (tree-tip-count tree))
  (format stream "Total Weight: ~D~%" (block-tree-total-weight tree))
  (format stream "Root: ~A~%"
          (when (block-tree-root tree)
            (subseq (hash-to-hex (block-tree-root tree)) 0 16)))
  (format stream "Head Cache Valid: ~A~%" (block-tree-head-cache-valid tree))
  (format stream "============================~%"))

(defun validate-tree-invariants (tree)
  "Validate all tree invariants.
Returns (values valid-p error-list)."
  (let ((errors nil))

    ;; Check root exists
    (unless (and (block-tree-root tree)
                 (tree-get-node tree (block-tree-root tree)))
      (push "Root node missing" errors))

    ;; Check parent references
    (maphash (lambda (hash node)
               (let ((parent-hash (tree-node-parent-hash node)))
                 (when (and parent-hash
                            (not (tree-get-node tree parent-hash)))
                   (push (format nil "Node ~A has missing parent ~A"
                                (subseq (hash-to-hex hash) 0 8)
                                (subseq (hash-to-hex parent-hash) 0 8))
                         errors))))
             (block-tree-nodes tree))

    ;; Check children consistency
    (maphash (lambda (hash node)
               (declare (ignore hash))
               (dolist (child-hash (tree-node-children node))
                 (let ((child (tree-get-node tree child-hash)))
                   (unless child
                     (push (format nil "Missing child ~A"
                                  (subseq (hash-to-hex child-hash) 0 8))
                           errors))
                   (when (and child
                              (not (hash-equal-p (tree-node-parent-hash child)
                                                 (tree-node-block-hash node))))
                     (push "Child parent mismatch" errors)))))
             (block-tree-nodes tree))

    ;; Check weight invariants
    (maphash (lambda (hash node)
               (declare (ignore hash))
               (when (< (tree-node-cumulative-weight node)
                        (tree-node-weight node))
                 (push "Cumulative weight less than weight" errors)))
             (block-tree-nodes tree))

    (values (null errors) (nreverse errors))))
