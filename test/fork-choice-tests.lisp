;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; test/fork-choice-tests.lisp - Tests for fork choice rules

(in-package #:cl-fork-choice.tests)

(deftest test-make-fork-choice
  (let ((genesis-hash (make-test-hash 0)))
    (let ((fc (make-fork-choice :genesis-hash genesis-hash)))
      (assert-true fc "Fork choice should be created")
      (assert-equal +rule-lmd-ghost+ (fork-choice-rule fc)
                    "Default rule should be LMD-GHOST"))))

(deftest test-fork-choice-add-block
  (let* ((genesis-hash (make-test-hash 0))
         (fc (make-fork-choice :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1)))
    (let ((node (fork-choice-add-block fc block1-hash genesis-hash 1 :weight 50)))
      (assert-true node "Block should be added"))))

(deftest test-fork-choice-get-head-single-chain
  (let* ((genesis-hash (make-test-hash 0))
         (fc (make-fork-choice :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1))
         (block2-hash (make-test-hash 2)))
    (fork-choice-add-block fc block1-hash genesis-hash 1)
    (fork-choice-add-block fc block2-hash block1-hash 2)
    (let ((head (fork-choice-get-head fc)))
      (assert-true (hash-equal-p block2-hash head)
                   "Head should be latest block"))))

(deftest test-fork-choice-get-head-fork
  (let* ((genesis-hash (make-test-hash 0))
         (fc (make-fork-choice :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1))
         (block2-hash (make-test-hash 2)))
    ;; Create a fork at genesis
    (fork-choice-add-block fc block1-hash genesis-hash 1 :weight 100)
    (fork-choice-add-block fc block2-hash genesis-hash 2 :weight 50)
    (let ((head (fork-choice-get-head fc)))
      (assert-true (hash-equal-p block1-hash head)
                   "Head should be heavier branch"))))

(deftest test-fork-choice-attestation
  (let* ((genesis-hash (make-test-hash 0))
         (fc (make-fork-choice :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1))
         (block2-hash (make-test-hash 2)))
    (fork-choice-add-block fc block1-hash genesis-hash 1 :weight 10)
    (fork-choice-add-block fc block2-hash genesis-hash 2 :weight 10)
    ;; Add attestation to block2
    (fork-choice-process-attestation fc 0 block2-hash 100)
    (let ((head (fork-choice-get-head fc)))
      (assert-true (hash-equal-p block2-hash head)
                   "Head should follow attestations"))))

(deftest test-select-head-longest-chain
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1))
         (block2-hash (make-test-hash 2))
         (block3-hash (make-test-hash 3)))
    ;; Chain 1: genesis -> block1 -> block3
    (tree-add-node tree block1-hash genesis-hash 1)
    (tree-add-node tree block3-hash block1-hash 3)
    ;; Chain 2: genesis -> block2
    (tree-add-node tree block2-hash genesis-hash 2)
    (let ((head (select-head tree :rule +rule-longest-chain+)))
      (assert-true (hash-equal-p block3-hash head)
                   "Longest chain should win"))))

(deftest test-select-head-ghost
  (let* ((genesis-hash (make-test-hash 0))
         (tree (make-block-tree :genesis-hash genesis-hash))
         (block1-hash (make-test-hash 1))
         (block2-hash (make-test-hash 2)))
    (tree-add-node tree block1-hash genesis-hash 1 :weight 100)
    (tree-add-node tree block2-hash genesis-hash 2 :weight 50)
    (let ((head (select-head tree :rule +rule-ghost+)))
      (assert-true (hash-equal-p block1-hash head)
                   "GHOST should select heaviest subtree"))))

(deftest test-constants
  (assert-equal 0 +genesis-slot+ "Genesis slot should be 0")
  (assert-equal 32 +slots-per-epoch+ "Slots per epoch should be 32")
  (assert-equal 12 +seconds-per-slot+ "Seconds per slot should be 12"))

(deftest test-epoch-calculations
  (assert-equal 0 (compute-epoch-at-slot 0) "Slot 0 is epoch 0")
  (assert-equal 0 (compute-epoch-at-slot 31) "Slot 31 is epoch 0")
  (assert-equal 1 (compute-epoch-at-slot 32) "Slot 32 is epoch 1")
  (assert-equal 0 (compute-start-slot-at-epoch 0) "Epoch 0 starts at slot 0")
  (assert-equal 32 (compute-start-slot-at-epoch 1) "Epoch 1 starts at slot 32")
  (assert-true (is-epoch-boundary-p 0) "Slot 0 is boundary")
  (assert-true (is-epoch-boundary-p 32) "Slot 32 is boundary")
  (assert-nil (is-epoch-boundary-p 1) "Slot 1 is not boundary"))
