;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; test/package.lisp - Test package for CL-FORK-CHOICE

(defpackage #:cl-fork-choice.tests
  (:use #:cl #:cl-fork-choice)
  (:export #:run-all-tests))

(in-package #:cl-fork-choice.tests)

(defvar *test-results* nil)
(defvar *test-count* 0)
(defvar *pass-count* 0)

(defmacro deftest (name &body body)
  "Define a test."
  `(progn
     (defun ,name ()
       (handler-case
           (progn
             ,@body
             (incf *pass-count*)
             (push (cons ',name :pass) *test-results*)
             t)
         (error (e)
           (push (cons ',name e) *test-results*)
           nil)))
     (pushnew ',name *all-tests*)))

(defvar *all-tests* nil)

(defmacro assert-true (form &optional message)
  `(unless ,form
     (error "~A: ~A" (or ,message "Assertion failed") ',form)))

(defmacro assert-equal (expected actual &optional message)
  `(unless (equal ,expected ,actual)
     (error "~A: expected ~S, got ~S"
            (or ,message "Equality assertion failed")
            ,expected ,actual)))

(defmacro assert-nil (form &optional message)
  `(when ,form
     (error "~A: expected NIL, got ~S" (or ,message "NIL assertion failed") ,form)))

(defun run-all-tests ()
  "Run all defined tests."
  (setf *test-results* nil
        *test-count* 0
        *pass-count* 0)
  (dolist (test (reverse *all-tests*))
    (incf *test-count*)
    (funcall test))
  (format t "~%Tests: ~D, Passed: ~D, Failed: ~D~%"
          *test-count* *pass-count* (- *test-count* *pass-count*))
  (= *test-count* *pass-count*))
