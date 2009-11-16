;;; -*- mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; Copyright (c) 2009 by the authors.
;;;
;;; See LICENCE for details.

(in-package :hu.dwim.def)

(def (definer e :available-flags "ioed") function ()
  (function-like-definer -definer- 'defun -whole- -environment- -options-))

(def (definer e :available-flags "eod") method ()
  (function-like-definer -definer- 'defmethod -whole- -environment- -options-))

(def (definer e :available-flags "eod") methods ()
  (defmethods-like-definer 'defmethod -whole- -options-))

(def (definer e :available-flags "eod") macro ()
  (function-like-definer -definer- 'defmacro -whole- -environment- -options-))

(def (definer e :available-flags "eod") compiler-macro ()
  (function-like-definer -definer- 'define-compiler-macro -whole- -environment- -options-))

(def (definer e :available-flags "e") symbol-macro (name expansion &optional documentation)
  (check-type name symbol)
  (with-standard-definer-options name
    `(progn
       (define-symbol-macro ,name ,expansion)
       (setf (documentation ',name 'variable) ,documentation))))

(def (definer e :available-flags "eod") generic ()
  (bind ((body (nthcdr 2 -whole-))
         (name (pop body))
         (outer-declarations (function-like-definer-declarations -options-)))
    `(locally
         ,@outer-declarations
       ,@(when (getf -options- :export)
               `((export ',name)))
       (defgeneric ,name ,@body))))

(def (definer :available-flags "e") type (name args &body forms)
  (with-standard-definer-options name
    `(deftype ,name ,args
       ,@forms)))

(def macro with-class-definer-options (name slots &body body)
  ``(progn
    ,@(when (getf -options- :export)
       `((export ',,name)))
    ,@(awhen (and (getf -options- :export-slot-names)
                  (mapcar (lambda (slot)
                            (first (ensure-list slot)))
                          ,slots))
       `((export ',it)))
    ,@(awhen (and (getf -options- :export-accessor-names)
                  (iter (for slot :in slots)
                        (setf slot (ensure-list slot))
                        (for slot-options = (rest slot))
                        (awhen (getf slot-options :accessor)
                          (collect it))
                        (awhen (getf slot-options :reader)
                          (collect it))
                        (awhen (getf slot-options :writer)
                          (collect it))))
       `((export ',it)))
    ,,@body))

(def (definer :available-flags "eas") class (name supers slots &rest options)
  "Example that exports all the class name and all the readers, writers and slot names:
    (def (class eas) foo \(bar baz)
     \(\(slot1 :reader readerr)
      \(slot2 :writer writerr :accessor accessorr))
     \(:metaclass fofofo))"
  (with-class-definer-options name slots
    `(defclass ,name ,supers
       ,slots
       ,@options)))

(def (definer :available-flags "eas") condition (name supers slots &rest options)
  "See the CLASS definer."
  (with-class-definer-options name slots
    `(define-condition ,name ,supers
       ,slots
       ,@options)))

(def macro with-structure-definer-options (name slots &body body)
  ``(progn
    ,@(when (getf -options- :export)
       `((export ',,name)))
    ,@(awhen (and (getf -options- :export-slot-names)
                  (mapcar (lambda (slot)
                            (first (ensure-list slot)))
                          ,slots))
       `((export ',it)))
    ;; TODO support exporting accessors, constructor, whatelse?
    ,,@body))

(def (definer :available-flags "eas") structure (name &body slots)
  (bind ((documentation (when (stringp (first slots))
                          (pop slots))))
    (with-structure-definer-options name slots
      `(defstruct ,name
         ,@(when documentation
             (list documentation))
         ,@slots))))

(def function %reevaluate-constant (name value &key (test 'eql))
  (if (not (boundp name))
      value
      (let ((old (symbol-value name))
            (new value))
        (if (not (constantp name))
            (prog1 new
              (cerror "Try to redefine the variable as a constant."
                      "~@<~S is an already bound non-constant variable ~
                       whose value is ~S.~:@>" name old))
            (if (funcall test old new)
                old
                (prog1 new
                  (cerror "Try to redefine the constant."
                          "~@<~S is an already defined constant whose value ~
                           ~S is not equal to the provided initial value ~S ~
                           under ~S.~:@>" name old new test)))))))

(def (definer e :available-flags "e") constant (name initial-value &optional documentation)
  "Use like: (def (constant e :test #'string=) alma \"korte\") test defaults to equal."
  (check-type name symbol)
  (bind ((test (getf -options- :test ''equal)))
    (with-standard-definer-options name
      `(eval-when (:compile-toplevel :load-toplevel :execute)
         (defconstant ,name (%reevaluate-constant ',name ,initial-value :test ,test)
           ,@(when documentation `(,documentation)))))))

(def (definer e :available-flags "e") load-time-constant (name initial-value &optional documentation)
  (check-type name symbol)
  (bind ((variable-name (format-symbol *package* "%%%~A" name)))
    (with-standard-definer-options name
      `(progn
         (eval-when (:compile-toplevel :load-toplevel :execute)
           (defvar ,variable-name)
           (setf (documentation ',name 'variable) ,documentation)
           (unless (boundp ',variable-name)
             (setf ,variable-name ,initial-value)))
         (define-symbol-macro ,name (load-time-value ,variable-name))))))

(def (definer e :available-flags "e") special-variable (name &optional value documentation)
  "Uses defvar/defparameter based on whether a value was provided or not, and accepts :documentation definer parameter for value-less defvars."
  (assert (not (and documentation (getf -options- :documentation))) () "Multiple documentations for ~S" -whole-)
  (setf documentation (or documentation (getf -options- :documentation)))
  (bind ((has-value? (> (length -whole-) 3)))
    (with-standard-definer-options name
      `(progn
        ,@(when documentation
            `((setf (documentation ',name 'variable) ,documentation)))
        (defvar ,name)
        (makunbound ',name)
        ,@(when has-value?
            `((setf ,name ,value)))))))

(def (definer e :available-flags "o") constructor (class-name* &body body)
  (let ((key-args (when (listp class-name*)
                    (rest class-name*)))
        (class-name (if (listp class-name*)
                        (first class-name*)
                        class-name*)))
    (bind ((declarations (function-like-definer-declarations -options-)))
      `(locally
           ,@declarations
         ;; TODO this is a bad idea: a headache for macro writing macros...
         ;; use -self- instead. same for print-object and friends...
         (defmethod initialize-instance :after ((-self- ,class-name) &key ,@key-args)
           ,@body)))))

(def (definer e) print-object (&whole whole class-name* &body body)
  "Define a PRINT-OBJECT method using PRINT-UNREADABLE-OBJECT.
  An example:
  (def print-object parenscript-dispatcher ; could be (parenscript-dispatcher :identity nil)
    (when (cachep self)
      (princ \"cached\")
      (princ \" \"))
    (princ (parenscript-file self)))"
  (with-unique-names (stream printing)
    (bind ((args (ensure-list class-name*))
           ((class-name &key (identity t) (type t) with-package (muffle-errors t)) args)
           ((:values body declarations documentation) (parse-body body :documentation #t :whole whole)))
      `(defmethod print-object ((-self- ,class-name) ,stream)
         ,@(when documentation
             (list documentation))
         ,@declarations
         (print-unreadable-object (-self- ,stream :type ,type :identity ,identity)
           (let ((*standard-output* ,stream))
             (block ,printing
               (,@(if muffle-errors
                      `(handler-bind ((error (lambda (error)
                                               (declare (ignore error))
                                               (write-string "<<error printing object>>")
                                               (return-from ,printing)))))
                      `(progn))
                  (let (,@(when with-package `((*package* ,(find-package with-package)))))
                    ,@body)))))
         ;; primary PRINT-OBJECT methods are supposed to return the object
         -self-))))

;; TODO it should check if the &key and &optional args of the macro part were provided and
;; only forward them if when they were. otherwise let the function's default forms kick in.
;; currently you need to C-c C-c all usages if the default values changed incompatibly.
(def function expand-with-macro (name args body -options- flat must-have-args)
  (flet ((simple-lambda-list? (args)
           (bind (((:values nil optionals rest keywords allow-other-keys?) (parse-ordinary-lambda-list args)))
             (and (not rest)
                  (not optionals)
                  (not keywords)
                  (not allow-other-keys?)))))
    (unless (or (not flat)
                (simple-lambda-list? args))
      (error "Can not generate a flat with-macro when using &rest, &optional or &key in its lambda list. Use with-macro* for that.")))
  (with-unique-names (fn with-body)
    (with-standard-definer-options name
      (bind ((call-funcion-name (format-symbol *package* "CALL-~A" name))
             (inner-arguments 'undefined))
        (labels ((process-body (form)
                   (cond ((consp form)
                          (cond
                            ((eq (first form) '-body-)
                             (unless (or (eq inner-arguments 'undefined)
                                         (equal inner-arguments (rest form)))
                               (error "Used -BODY- multiple times and they have different argument lists: ~S, ~S" inner-arguments (rest form)))
                             (setf inner-arguments (rest form))
                             ;; use an flet instead `(funcall ,fn ,@inner-arguments) so that #'-body- is also possible
                             `(,(first form) ,@(mapcar (lambda (el)
                                                         (first (ensure-list el)))
                                                       (rest form))))
                            ((and (eq (first form) 'function)
                                  (eq (second form) '-body-)
                                  (length= 2 form))
                             ;; shut up if there's a #'-body- somewhere
                             (setf inner-arguments nil)
                             form)
                            (t
                             (iter (for entry :first form :then (cdr entry))
                                   (collect (process-body (car entry)) :into result)
                                   (cond
                                     ((consp (cdr entry))
                                      ;; nop, go on looping
                                      )
                                     ((cdr entry)
                                      (setf (cdr (last result)) (cdr entry))
                                      (return result))
                                     (t (return result)))))))
                         ((typep form 'standard-object)
                          ;; NOTE: to avoid warning for quasi-quote literal STANDARD-OBJECT AST nodes wrapping -body-
                          (setf inner-arguments nil)
                          form)
                         (t form))))
          (setf body (process-body body))
          (when (eq inner-arguments 'undefined)
            (simple-style-warning "You probably want to have at least one (-body-) form in the body of a WITH-MACRO to invoke the user provided body...")
            (setf inner-arguments nil))
          (bind ((args-to-remove-from-fn ())
                 (fn-args args)
                 (inner-arguments/macro-body ())
                 (inner-arguments/fn-body ()))
            (dolist (el inner-arguments)
              (if (consp el)
                  (progn
                    (unless (and (length= 2 el)
                                 (notany (lambda (part)
                                           (or (not (symbolp part))
                                               (not (symbolp part))
                                               (member part '(&rest &optional &key &allow-other-keys))))
                                         el))
                      (error "The arguemnts used to invoke (-body- foo1 foo2) may only contain symbols, or (with-macro-body-name lexically-visible-name) pairs denoting variables that are \"transferred\" from the call site in the with-macro into the lexical scope of the user provided body."))
                    (push (second el) args-to-remove-from-fn)
                    (push (first el) inner-arguments/macro-body)
                    (push (second el) inner-arguments/fn-body))
                  (progn
                    (push el inner-arguments/macro-body)
                    (push `(quote ,el) inner-arguments/fn-body))))
            (reversef inner-arguments/macro-body)
            (reversef inner-arguments/fn-body)
            (bind ()
              (dolist (arg args-to-remove-from-fn)
                (removef fn-args arg))
              (bind (((:values funcall-list rest-variable-name) (lambda-list-to-funcall-list fn-args))
                     (body-fn-name (format-symbol *package* "~A-BODY" name)))
                `(progn
                   (defun ,call-funcion-name (,fn ,@fn-args)
                     (declare (type function ,fn))
                     ,@(function-like-definer-declarations -options-)
                     (flet ((-body- (,@inner-arguments/macro-body)
                              (funcall ,fn ,@inner-arguments/macro-body)))
                       (declare (inline -body-))
                       (block ,name
                         ,@body)))
                   (defmacro ,name (,@(when (or args must-have-args)
                                            (bind ((macro-args (lambda-list-to-lambda-list-with-quoted-defaults
                                                                args)))
                                              (if flat
                                                  macro-args
                                                  (list macro-args))))
                                    &body ,with-body)
                     `(,',call-funcion-name
                       (named-lambda ,',body-fn-name ,(list ,@inner-arguments/fn-body)
                         ,@,with-body)
                       ,,@funcall-list
                       ,@,rest-variable-name)))))))))))

(def (definer e :available-flags "eod") with-macro (name args &body body)
  "(def with-macro with-foo (arg1 arg2)
     (let ((*zyz* 42)
           (local 43))
       (do something)
       (-body- local)))
   Example:
   (with-foo arg1 arg2
     (...))"
  (expand-with-macro name args body -options- #t #f))

(def (definer e :available-flags "eod") with-macro* (name args &body body)
  "(def with-macro* with-foo (arg1 arg2 &key alma)
     (let ((*zyz* 42)
           (local 43))
       (do something)
       (-body- local)))
   Example:
   (with-foo (arg1 arg2 :alma alma)
     (...))"
  (expand-with-macro name args body -options- #f #t))

(def (definer e :available-flags "e") with/without (name)
  (bind ((package (symbol-package name))
         (variable-name (format-symbol package "*~A*" name))
         (with-macro-name (format-symbol package "WITH-~A" name))
         (without-macro-name (format-symbol package "WITHOUT-~A" name)))
    `(progn
       ,@(when (getf -options- :export)
               `((export '(,variable-name ,with-macro-name ,without-macro-name))))
       (defvar ,variable-name)
       (defmacro ,with-macro-name (&body forms)
         `(let ((,',variable-name #t))
            ,@forms))
       (defmacro ,without-macro-name (&body forms)
         `(let ((,',variable-name #f))
            ,@forms)))))

(def (definer e :available-flags "e") namespace (name &optional args &body forms)
  (bind ((variable-name (symbolicate "*" name '#:-namespace*))
         (lock-variable-name (symbolicate "%" name '#:-namespace-lock%))
         (finder-name (symbolicate '#:find- name))
         (collector-name (symbolicate '#:collect- name '#:-namespace-values))
         (iterator-name (symbolicate '#:iterate- name '#:-namespace)))
    `(progn
       ,@(when (getf -options- :export)
               `((export '(,variable-name ,finder-name ,collector-name ,iterator-name))))
       (defvar ,variable-name (make-hash-table :test ,(or (getf -options- :test) '#'eq)))
       (defvar ,lock-variable-name (make-lock :name ,(concatenate 'string "lock for " (string variable-name))))
       (def function ,finder-name (name &key (otherwise nil otherwise?))
         (or (with-lock ,lock-variable-name
               (gethash name ,variable-name))
             (if otherwise?
                 otherwise
                 (error "Cannot find ~A in namespace ~A" name ',name))))
       (def function (setf ,finder-name) (value name)
         (with-lock ,lock-variable-name
           (setf (gethash name ,variable-name) value)))
       (def function ,collector-name ()
         (with-lock ,lock-variable-name
           (hash-table-values ,variable-name)))
       (def function ,iterator-name (visitor)
         (with-lock ,lock-variable-name
           (maphash visitor ,variable-name)))
       (def (definer ,@-options-) ,name (name ,@args)
         `(setf (,',finder-name ',name) ,,@forms)))))

