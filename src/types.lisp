;;;; types.lisp - Core type definitions for CL-FORK-CHOICE
;;;;
;;;; Defines constants and basic type specifications used throughout
;;;; the fork choice implementation.

(in-package #:cl-fork-choice)

;;; ============================================================================
;;; Constants
;;; ============================================================================

(defconstant +genesis-slot+ 0
  "Slot number of the genesis block.")

(defconstant +genesis-epoch+ 0
  "Epoch number of the genesis block.")

(defconstant +slots-per-epoch+ 32
  "Number of slots per epoch.")

(defconstant +seconds-per-slot+ 12
  "Seconds per slot (Ethereum 2.0 default).")

(defconstant +proposer-boost-numerator+ 40
  "Numerator for proposer score boost calculation.")

(defconstant +proposer-boost-denominator+ 100
  "Denominator for proposer score boost calculation.")

(defconstant +max-reorg-depth+ 100
  "Maximum allowed reorganization depth.")

(defconstant +safe-slots-to-update-justified+ 8
  "Slots after epoch boundary before updating justified.")

;;; Fork Choice Rule Constants
(defconstant +rule-longest-chain+ :longest-chain
  "Use longest chain (by height) fork choice rule.")

(defconstant +rule-ghost+ :ghost
  "Use GHOST (heaviest observed subtree) fork choice rule.")

(defconstant +rule-lmd-ghost+ :lmd-ghost
  "Use LMD-GHOST (Latest Message Driven GHOST) fork choice rule.")

;;; ============================================================================
;;; Branch Score Structure
;;; ============================================================================

(defstruct (branch-score
            (:constructor make-branch-score
                (&key weight attestation-weight block-weight
                      proposer-boost finality-bonus)))
  "Score components for a branch in the block tree."
  (weight 0 :type integer)
  (attestation-weight 0 :type integer)
  (block-weight 0 :type integer)
  (proposer-boost 0 :type integer)
  (finality-bonus 0 :type integer))

;;; ============================================================================
;;; Finality Checkpoint Structure
;;; ============================================================================

(defstruct (finality-checkpoint
            (:constructor make-finality-checkpoint
                (&key epoch root state-root justified-p finalized-p)))
  "Represents a finality checkpoint in the consensus process."
  (epoch 0 :type (unsigned-byte 64))
  (root nil :type (or null (simple-array (unsigned-byte 8) (32))))
  (state-root nil :type (or null (simple-array (unsigned-byte 8) (32))))
  (justified-p nil :type boolean)
  (finalized-p nil :type boolean))

;;; ============================================================================
;;; Fork Choice Structure
;;; ============================================================================

(defstruct (fork-choice
            (:constructor %make-fork-choice))
  "Main fork choice state container."
  (rule +rule-lmd-ghost+ :type keyword)
  (tree nil :type (or null block-tree))
  (attestation-store nil :type t)
  (finality-state nil :type t)
  (config nil :type list))

(defun make-fork-choice (&key (rule +rule-lmd-ghost+)
                              genesis-hash
                              genesis-state-root
                              config)
  "Create a new fork choice instance with the given parameters."
  (let ((tree (make-block-tree :genesis-hash genesis-hash
                               :genesis-state-root genesis-state-root)))
    (%make-fork-choice
     :rule rule
     :tree tree
     :config config)))
