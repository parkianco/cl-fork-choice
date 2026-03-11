;;;; fork-choice.lisp - Fork choice rule implementation
;;;;
;;;; Implements the main fork choice interface including
;;;; head selection algorithms for various rules.

(in-package #:cl-fork-choice)

;;; ============================================================================
;;; Head Selection
;;; ============================================================================

(defun select-head (tree &key (rule +rule-lmd-ghost+) justified-root)
  "Select the head block according to the specified fork choice rule.

PARAMETERS:
- tree: block-tree - The block tree to select from
- rule: keyword - Fork choice rule to use
- justified-root: hash - Starting point for LMD-GHOST (optional)

RETURNS:
- hash - Block hash of the selected head"
  (case rule
    (#.+rule-longest-chain+
     (select-head-longest-chain tree))
    (#.+rule-ghost+
     (select-head-ghost tree (or justified-root (block-tree-root tree))))
    (#.+rule-lmd-ghost+
     (select-head-lmd-ghost tree (or justified-root (block-tree-root tree))))
    (t
     (select-head-lmd-ghost tree (or justified-root (block-tree-root tree))))))

(defun get-head (tree &key force-recalculate)
  "Get the current head, using cache if valid."
  (if (and (not force-recalculate)
           (block-tree-head-cache-valid tree)
           (block-tree-head-cache tree))
      (block-tree-head-cache tree)
      (let ((head (select-head tree)))
        (setf (block-tree-head-cache tree) head)
        (setf (block-tree-head-cache-valid tree) t)
        head)))

(defun invalidate-head-cache (tree)
  "Invalidate the head cache, forcing recalculation on next get-head."
  (setf (block-tree-head-cache-valid tree) nil))

;;; ============================================================================
;;; Longest Chain Rule
;;; ============================================================================

(defun select-head-longest-chain (tree)
  "Select head using longest chain (by height) rule."
  (let ((best-hash nil)
        (best-height -1))
    (maphash (lambda (hash node)
               (when (and (null (tree-node-children node))
                          (> (tree-node-height node) best-height))
                 (setf best-hash hash)
                 (setf best-height (tree-node-height node))))
             (block-tree-nodes tree))
    best-hash))

;;; ============================================================================
;;; GHOST Rule
;;; ============================================================================

(defun select-head-ghost (tree start-hash)
  "Select head using GHOST (heaviest subtree) rule.
Walks down the tree, always choosing the heaviest child."
  (let ((current-hash start-hash))
    (loop
      (let ((node (tree-get-node tree current-hash)))
        (unless node
          (return current-hash))
        (let ((children (tree-node-children node)))
          (unless children
            (return current-hash))
          ;; Find heaviest child
          (let ((best-child nil)
                (best-weight -1))
            (dolist (child-hash children)
              (let ((child (tree-get-node tree child-hash)))
                (when (and child
                           (> (tree-node-cumulative-weight child) best-weight))
                  (setf best-child child-hash)
                  (setf best-weight (tree-node-cumulative-weight child)))))
            (if best-child
                (setf current-hash best-child)
                (return current-hash))))))))

;;; ============================================================================
;;; LMD-GHOST Rule
;;; ============================================================================

(defun select-head-lmd-ghost (tree start-hash)
  "Select head using LMD-GHOST rule.
Similar to GHOST but uses best-descendant cache when available."
  (let ((current-hash start-hash))
    (loop
      (let ((node (tree-get-node tree current-hash)))
        (unless node
          (return current-hash))
        ;; Use cached best-descendant if available
        (let ((best (tree-node-best-descendant node)))
          (if best
              (setf current-hash best)
              ;; No best-descendant, must be a leaf
              (return current-hash)))))))

;;; ============================================================================
;;; Fork Choice Interface
;;; ============================================================================

(defun fork-choice-add-block (fc block-hash parent-hash slot &key weight state-root)
  "Add a block to the fork choice tree."
  (let ((tree (fork-choice-tree fc)))
    (tree-add-node tree block-hash parent-hash slot
                   :weight weight
                   :state-root state-root)))

(defun fork-choice-remove-block (fc block-hash)
  "Remove a block from the fork choice tree."
  (let ((tree (fork-choice-tree fc)))
    (tree-remove-node tree block-hash)))

(defun fork-choice-get-head (fc &key justified-root)
  "Get the current head according to fork choice rules."
  (let ((tree (fork-choice-tree fc))
        (rule (fork-choice-rule fc)))
    (select-head tree :rule rule :justified-root justified-root)))

(defun fork-choice-process-attestation (fc validator-index target-root weight)
  "Process an attestation vote.
Updates the weight of the target block."
  (let ((tree (fork-choice-tree fc)))
    (propagate-weight-down tree target-root weight)
    ;; Invalidate cache since weights changed
    (invalidate-head-cache tree)))

(defun fork-choice-on-tick (fc current-slot)
  "Process a slot tick (called each slot).
Can be used to clear proposer boost from previous slot."
  (declare (ignore fc current-slot))
  ;; Clear expired proposer boosts, update epoch if needed
  nil)
