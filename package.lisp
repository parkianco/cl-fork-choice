;;;; package.lisp - Package definition for CL-FORK-CHOICE
;;;;
;;;; LMD-GHOST fork choice implementation for blockchain consensus.
;;;; Provides block tree representation and head selection algorithms.

(defpackage #:cl-fork-choice
  (:use #:cl)
  (:nicknames #:fork-choice)
  (:documentation "LMD-GHOST fork choice rule implementation.
Provides efficient block tree management and head selection for
blockchain consensus systems.")
  (:export
   ;; Constants
   #:+genesis-slot+
   #:+genesis-epoch+
   #:+slots-per-epoch+
   #:+seconds-per-slot+
   #:+proposer-boost-numerator+
   #:+proposer-boost-denominator+
   #:+max-reorg-depth+
   #:+safe-slots-to-update-justified+

   ;; Tree Node
   #:tree-node
   #:make-tree-node
   #:tree-node-p
   #:tree-node-block-hash
   #:tree-node-parent-hash
   #:tree-node-slot
   #:tree-node-height
   #:tree-node-weight
   #:tree-node-cumulative-weight
   #:tree-node-children
   #:tree-node-justified-p
   #:tree-node-finalized-p
   #:tree-node-best-descendant
   #:tree-node-proposer-boost
   #:tree-node-state-root
   #:tree-node-timestamp
   #:tree-node-validity

   ;; Block Tree
   #:block-tree
   #:make-block-tree
   #:block-tree-p
   #:block-tree-root
   #:block-tree-nodes
   #:block-tree-justified-checkpoint
   #:block-tree-finalized-checkpoint
   #:block-tree-proposer-boost-root
   #:block-tree-head-cache
   #:block-tree-head-cache-valid
   #:block-tree-node-count
   #:block-tree-max-height
   #:block-tree-total-weight

   ;; Tree Operations
   #:tree-add-node
   #:tree-remove-node
   #:tree-get-node
   #:tree-has-node-p
   #:tree-get-children
   #:tree-get-parent
   #:tree-get-ancestors
   #:tree-get-descendants

   ;; Tree Properties
   #:tree-height
   #:tree-tip-count
   #:tree-is-ancestor-p
   #:tree-get-path
   #:tree-common-ancestor
   #:tree-subtree-weight

   ;; Tree Traversal
   #:tree-walk-up
   #:tree-walk-down
   #:tree-map-nodes
   #:tree-fold-nodes
   #:tree-filter-nodes

   ;; Weight Propagation
   #:propagate-weight-up
   #:propagate-weight-down
   #:recalculate-all-weights

   ;; Slot/Epoch Utilities
   #:compute-epoch-at-slot
   #:compute-start-slot-at-epoch
   #:compute-slot-at-time
   #:compute-time-at-slot
   #:is-epoch-boundary-p

   ;; Hash Utilities
   #:hash-equal-p
   #:hash-to-hex
   #:hex-to-hash

   ;; Head Selection
   #:select-head
   #:get-head
   #:invalidate-head-cache

   ;; Branch Scoring
   #:branch-score
   #:make-branch-score
   #:compute-branch-score
   #:compute-node-weight

   ;; Fork Choice Interface
   #:fork-choice
   #:make-fork-choice
   #:fork-choice-rule
   #:fork-choice-tree
   #:fork-choice-add-block
   #:fork-choice-remove-block
   #:fork-choice-get-head
   #:fork-choice-process-attestation
   #:fork-choice-on-tick

   ;; Fork Choice Rules
   #:+rule-longest-chain+
   #:+rule-ghost+
   #:+rule-lmd-ghost+

   ;; Debugging
   #:print-tree-summary
   #:validate-tree-invariants
   #:with-tree-lock

   ;; Events
   #:*on-head-changed*
   #:*on-block-added*))

(in-package #:cl-fork-choice)

;; Event hooks
(defvar *on-head-changed* nil
  "Callback function invoked when head block changes.")

(defvar *on-block-added* nil
  "Callback function invoked when a block is added to the tree.")
