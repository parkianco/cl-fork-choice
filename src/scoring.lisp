;;;; scoring.lisp - Weight and scoring for fork choice
;;;;
;;;; Implements weight propagation and branch scoring algorithms
;;;; used in fork choice rule evaluation.

(in-package #:cl-fork-choice)

;;; ============================================================================
;;; Weight Propagation
;;; ============================================================================

(defun propagate-weight-up (tree block-hash)
  "Propagate weight changes up the tree from a node.
Updates cumulative-weight for all ancestors."
  (let ((current-hash block-hash))
    (loop
      (let ((node (tree-get-node tree current-hash)))
        (unless node
          (return))

        ;; Recalculate cumulative weight
        (let ((best-child-weight 0)
              (best-child-hash nil))
          (dolist (child-hash (tree-node-children node))
            (let ((child (tree-get-node tree child-hash)))
              (when (and child
                         (> (tree-node-cumulative-weight child) best-child-weight))
                (setf best-child-weight (tree-node-cumulative-weight child))
                (setf best-child-hash child-hash))))

          ;; Update node
          (setf (tree-node-cumulative-weight node)
                (+ (tree-node-weight node)
                   (tree-node-proposer-boost node)
                   best-child-weight))
          (setf (tree-node-best-descendant node) best-child-hash))

        ;; Move to parent
        (let ((parent-hash (tree-node-parent-hash node)))
          (unless parent-hash
            (return))
          (setf current-hash parent-hash))))))

(defun propagate-weight-down (tree block-hash delta)
  "Add delta weight to a node and propagate up."
  (let ((node (tree-get-node tree block-hash)))
    (when node
      (incf (tree-node-weight node) delta)
      (propagate-weight-up tree block-hash))))

(defun recalculate-all-weights (tree)
  "Recalculate all cumulative weights in the tree.
Uses post-order traversal to calculate weights bottom-up."
  (let ((root-hash (block-tree-root tree)))
    (when root-hash
      (labels ((recalculate (hash)
                 (let ((node (tree-get-node tree hash)))
                   (when node
                     ;; First recalculate children
                     (dolist (child-hash (tree-node-children node))
                       (recalculate child-hash))

                     ;; Then update this node
                     (let ((best-child-weight 0)
                           (best-child-hash nil))
                       (dolist (child-hash (tree-node-children node))
                         (let ((child (tree-get-node tree child-hash)))
                           (when (and child
                                      (> (tree-node-cumulative-weight child) best-child-weight))
                             (setf best-child-weight (tree-node-cumulative-weight child))
                             (setf best-child-hash child-hash))))

                       (setf (tree-node-cumulative-weight node)
                             (+ (tree-node-weight node)
                                (tree-node-proposer-boost node)
                                best-child-weight))
                       (setf (tree-node-best-descendant node) best-child-hash))))))
        (recalculate root-hash)))))

;;; ============================================================================
;;; Slot/Epoch Utilities
;;; ============================================================================

(defun compute-epoch-at-slot (slot)
  "Compute the epoch number for a given slot."
  (floor slot +slots-per-epoch+))

(defun compute-start-slot-at-epoch (epoch)
  "Compute the first slot of an epoch."
  (* epoch +slots-per-epoch+))

(defun compute-slot-at-time (genesis-time current-time)
  "Compute the current slot based on time."
  (if (< current-time genesis-time)
      0
      (floor (- current-time genesis-time) +seconds-per-slot+)))

(defun compute-time-at-slot (genesis-time slot)
  "Compute the Unix timestamp of a slot."
  (+ genesis-time (* slot +seconds-per-slot+)))

(defun is-epoch-boundary-p (slot)
  "Check if a slot is at an epoch boundary."
  (zerop (mod slot +slots-per-epoch+)))

;;; ============================================================================
;;; Branch Scoring
;;; ============================================================================

(defun compute-branch-score (tree block-hash)
  "Compute the overall score for a branch rooted at block-hash."
  (let ((node (tree-get-node tree block-hash)))
    (when node
      (make-branch-score
       :weight (tree-node-cumulative-weight node)
       :attestation-weight (tree-node-weight node)
       :block-weight (tree-node-height node)
       :proposer-boost (tree-node-proposer-boost node)
       :finality-bonus (if (tree-node-finalized-p node) 1000000 0)))))

(defun compute-node-weight (tree block-hash)
  "Compute the weight of a single node."
  (let ((node (tree-get-node tree block-hash)))
    (when node
      (tree-node-weight node))))
