;;; -*- mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; Copyright (c) 2009 by the authors.
;;;
;;; See LICENCE for details.

(in-package :hu.dwim.def)

(def (definer :available-flags "e") function/cc ()
  (function-like-definer -definer- 'hu.dwim.delico:defun/cc -whole- -environment- -options-))

(integrated-export '(hu.dwim.delico:defun/cc function/cc) :hu.dwim.def)
