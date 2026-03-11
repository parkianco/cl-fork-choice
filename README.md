# CL-FORK-CHOICE

A Common Lisp library implementing fork choice rules for blockchain consensus, including LMD-GHOST (Latest Message Driven Greedy Heaviest Observed SubTree).

## Features

- **Block Tree Management**: Efficient tree structure for tracking blockchain forks
- **Multiple Fork Choice Rules**:
  - Longest Chain Rule
  - GHOST (Greedy Heaviest Observed SubTree)
  - LMD-GHOST (Latest Message Driven GHOST)
- **Weight Propagation**: Cumulative weight calculation for branch scoring
- **Attestation Processing**: Support for validator attestations
- **Head Selection Caching**: Optimized head calculation with cache invalidation
- **Epoch/Slot Utilities**: Time-based calculations for proof-of-stake

## Installation

Clone the repository and load via ASDF:

```lisp
(asdf:load-system :cl-fork-choice)
```

## Quick Start

```lisp
(use-package :cl-fork-choice)

;; Create a genesis block hash
(defvar *genesis* (make-array 32 :element-type '(unsigned-byte 8) :initial-element 0))

;; Create a fork choice instance
(defvar *fc* (make-fork-choice :genesis-hash *genesis*))

;; Add blocks
(defvar *block1* (make-array 32 :element-type '(unsigned-byte 8) :initial-element 1))
(fork-choice-add-block *fc* *block1* *genesis* 1 :weight 100)

;; Get the current head
(fork-choice-get-head *fc*)
```

## API Reference

### Fork Choice Interface

- `make-fork-choice` - Create a new fork choice instance
- `fork-choice-add-block` - Add a block to the tree
- `fork-choice-remove-block` - Remove a block from the tree
- `fork-choice-get-head` - Get the current head block
- `fork-choice-process-attestation` - Process a validator attestation

### Block Tree Operations

- `make-block-tree` - Create a new block tree
- `tree-add-node` - Add a node to the tree
- `tree-remove-node` - Remove a node from the tree
- `tree-get-node` - Get a node by hash
- `tree-get-ancestors` - Get all ancestors of a node
- `tree-common-ancestor` - Find common ancestor of two nodes
- `tree-is-ancestor-p` - Check if one block is ancestor of another

### Head Selection

- `select-head` - Select head using specified rule
- `get-head` - Get head with caching
- `invalidate-head-cache` - Force recalculation on next access

### Constants

- `+rule-longest-chain+` - Longest chain rule
- `+rule-ghost+` - GHOST rule
- `+rule-lmd-ghost+` - LMD-GHOST rule (default)
- `+genesis-slot+` - Genesis slot (0)
- `+slots-per-epoch+` - Slots per epoch (32)
- `+seconds-per-slot+` - Seconds per slot (12)

## Testing

```lisp
(asdf:test-system :cl-fork-choice)
```

## Requirements

- SBCL (for threading support via sb-thread)
- ASDF 3.0+

## License

BSD-3-Clause. See LICENSE file.
