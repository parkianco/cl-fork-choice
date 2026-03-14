;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; cl-fork-choice.asd - System definition for CL-FORK-CHOICE
;;;; LMD-GHOST fork choice implementation

(asdf:defsystem #:cl-fork-choice
  :description "LMD-GHOST fork choice rule implementation for blockchain consensus"
  :author "Parkian Company LLC"
  :license "BSD-3-Clause"
  :version "0.1.0"
  :serial t
  :depends-on ()  ; Standalone - no external dependencies
  :components ((:file "package")
               (:module "src"
                :serial t
                :components ((:file "types")
                             (:file "tree")
                             (:file "scoring")
                             (:file "fork-choice"))))
  :in-order-to ((asdf:test-op (test-op #:cl-fork-choice/tests))))

(asdf:defsystem #:cl-fork-choice/tests
  :description "Tests for CL-FORK-CHOICE"
  :depends-on (#:cl-fork-choice)
  :serial t
  :components ((:module "test"
                :serial t
                :components ((:file "package")
                             (:file "fork-choice-tests")
                             (:file "fork-choice-tests"))))
  :perform (asdf:test-op (o s)
             (let ((result (uiop:symbol-call :cl-fork-choice.tests :run-all-tests)))
               (unless result
                 (error "Tests failed")))))
