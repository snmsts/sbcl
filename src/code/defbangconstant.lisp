;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; This software is derived from the CMU CL system, which was
;;;; written at Carnegie Mellon University and released into the
;;;; public domain. The software is in the public domain and is
;;;; provided with absolutely no warranty. See the COPYING and CREDITS
;;;; files for more information.

(in-package "SB!KERNEL")

;;;; the DEF!CONSTANT macro

;;; FIXME: This code was created by cut-and-paste from the
;;; corresponding code for DEF!TYPE. DEF!CONSTANT, DEF!TYPE and
;;; DEF!MACRO are currently very parallel, and if we ever manage to
;;; rationalize the use of UNCROSS in the cross-compiler, they should
;;; become completely parallel, at which time they should be merged to
;;; eliminate the duplicate code.

;;; *sigh* -- Even the comments are cut'n'pasted :-/ If I were more
;;; confident in my understanding, I might try to do drastic surgery,
;;; but my head is currently spinning (host? target? both?) so I'll go
;;; for the minimal changeset... -- CSR, 2002-05-11
(defmacro def!constant (&whole whole name value &optional doc)
  (declare (ignore value doc #-sb-xc-host name))
  `(progn
     #-sb-xc-host
     (defconstant ,@(cdr whole))
     #+sb-xc-host
     ,(unless (eql (find-symbol (symbol-name name) :cl) name)
        `(defconstant ,@(cdr whole)))
     #+sb-xc-host
     ,(let ((form `(sb!xc:defconstant ,@(cdr whole))))
        (if (boundp '*delayed-def!constants*)
            `(push ',form *delayed-def!constants*)
            form))))

;;; machinery to implement DEF!CONSTANT delays
#+sb-xc-host
(progn
  (/show "binding *DELAYED-DEF!CONSTANTS*")
  (defvar *delayed-def!constants* nil)
  (/show "done binding *DELAYED-DEF!CONSTANTS*")
  (defun force-delayed-def!constants ()
    (if (boundp '*delayed-def!constants*)
        (progn
          (mapc #'eval *delayed-def!constants*)
          (makunbound '*delayed-def!constants*))
        ;; This condition is probably harmless if it comes up when
        ;; interactively experimenting with the system by loading a
        ;; source file into it more than once. But it's worth warning
        ;; about it because it definitely shouldn't come up in an
        ;; ordinary build process.
        (warn "*DELAYED-DEF!CONSTANTS* is already unbound."))))

(defun %defconstant-eqx-value (symbol expr eqx)
  (declare (type function eqx))
  (if (boundp symbol)
      (let ((oldval (symbol-value symbol)))
        ;; %DEFCONSTANT will give a choice of how to proceeed on error.
        (if (funcall eqx oldval expr) oldval expr))
      expr))

;;; generalization of DEFCONSTANT to values which are the same not
;;; under EQL but under e.g. EQUAL or EQUALP
;;;
;;; DEFCONSTANT-EQX is to be used instead of DEFCONSTANT for values
;;; which are appropriately compared using the function given by the
;;; EQX argument instead of EQL.
;;;
(defmacro defconstant-eqx (symbol expr eqx &optional doc)
  `(def!constant ,symbol
     (%defconstant-eqx-value ',symbol ,expr ,eqx)
     ,@(when doc (list doc))))

