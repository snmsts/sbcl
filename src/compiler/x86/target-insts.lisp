;;;; target-only stuff from CMU CL's src/compiler/x86/insts.lisp
;;;;
;;;; i.e. stuff which was in CMU CL's insts.lisp file, but which in
;;;; the SBCL build process can't be compiled into code for the
;;;; cross-compilation host

;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; This software is derived from the CMU CL system, which was
;;;; written at Carnegie Mellon University and released into the
;;;; public domain. The software is in the public domain and is
;;;; provided with absolutely no warranty. See the COPYING and CREDITS
;;;; files for more information.

(in-package "SB!X86-ASM")

(defun print-reg-with-width (value width stream dstate)
  (declare (ignore dstate))
  (princ (aref (ecase width
                 (:byte *byte-reg-names*)
                 (:word *word-reg-names*)
                 (:dword *dword-reg-names*))
               value)
         stream)
  ;; XXX plus should do some source-var notes
  )

(defun print-reg (value stream dstate)
  (declare (type reg value)
           (type stream stream)
           (type disassem-state dstate))
  (print-reg-with-width value
                        (inst-operand-size dstate)
                        stream
                        dstate))

(defun print-word-reg (value stream dstate)
  (declare (type reg value)
           (type stream stream)
           (type disassem-state dstate))
  (print-reg-with-width value
                        (inst-word-operand-size dstate)
                        stream
                        dstate))

(defun print-byte-reg (value stream dstate)
  (declare (type reg value)
           (type stream stream)
           (type disassem-state dstate))
  (print-reg-with-width value :byte stream dstate))

(defun print-addr-reg (value stream dstate)
  (declare (type reg value)
           (type stream stream)
           (type disassem-state dstate))
  (print-reg-with-width value *default-address-size* stream dstate))

(defun print-reg/mem (value stream dstate)
  (declare (type (or list reg) value)
           (type stream stream)
           (type disassem-state dstate))
  (if (typep value 'reg)
      (print-reg value stream dstate)
      (print-mem-access value stream nil dstate)))

;; Same as print-reg/mem, but prints an explicit size indicator for
;; memory references.
(defun print-sized-reg/mem (value stream dstate)
  (declare (type (or list reg) value)
           (type stream stream)
           (type disassem-state dstate))
  (if (typep value 'reg)
      (print-reg value stream dstate)
      (print-mem-access value stream t dstate)))

(defun print-byte-reg/mem (value stream dstate)
  (declare (type (or list reg) value)
           (type stream stream)
           (type disassem-state dstate))
  (if (typep value 'reg)
      (print-byte-reg value stream dstate)
      (print-mem-access value stream t dstate)))

(defun print-word-reg/mem (value stream dstate)
  (declare (type (or list reg) value)
           (type stream stream)
           (type disassem-state dstate))
  (if (typep value 'reg)
      (print-word-reg value stream dstate)
      (print-mem-access value stream nil dstate)))

(defun print-label (value stream dstate)
  (declare (ignore dstate))
  (princ16 value stream))

(defun maybe-print-segment-override (stream dstate)
  (cond ((dstate-get-inst-prop dstate 'fs-segment-prefix)
         (princ "FS:" stream))
        ((dstate-get-inst-prop dstate 'gs-segment-prefix)
         (princ "GS:" stream))))

(defun print-mem-access (value stream print-size-p dstate)
  (declare (type list value)
           (type stream stream)
           (type (member t nil) print-size-p)
           (type disassem-state dstate))
  (when print-size-p
    (princ (inst-operand-size dstate) stream)
    (princ '| PTR | stream))
  (maybe-print-segment-override stream dstate)
  (write-char #\[ stream)
  (let ((firstp t))
    (macrolet ((pel ((var val) &body body)
                 ;; Print an element of the address, maybe with
                 ;; a leading separator.
                 `(let ((,var ,val))
                    (when ,var
                      (unless firstp
                        (write-char #\+ stream))
                      ,@body
                      (setq firstp nil)))))
      (pel (base-reg (first value))
        (print-addr-reg base-reg stream dstate))
      (pel (index-reg (third value))
        (print-addr-reg index-reg stream dstate)
        (let ((index-scale (fourth value)))
          (when (and index-scale (not (= index-scale 1)))
            (write-char #\* stream)
            (princ index-scale stream))))
      (let ((offset (second value)))
        (when (and offset (or firstp (not (zerop offset))))
          (unless (or firstp (minusp offset))
            (write-char #\+ stream))
          (if firstp
            (progn
              (princ16 offset stream)
              (or (minusp offset)
                  (nth-value 1 (note-code-constant-absolute offset dstate))
                  (maybe-note-assembler-routine offset nil dstate)))
            (princ offset stream))))))
  (write-char #\] stream))

;;;; interrupt instructions

(defun snarf-error-junk (sap offset &optional length-only)
  (let* ((length (sap-ref-8 sap offset))
         (vector (make-array length :element-type '(unsigned-byte 8))))
    (declare (type system-area-pointer sap)
             (type (unsigned-byte 8) length)
             (type (simple-array (unsigned-byte 8) (*)) vector))
    (cond (length-only
           (values 0 (1+ length) nil nil))
          (t
           (copy-ub8-from-system-area sap (1+ offset) vector 0 length)
           (collect ((sc-offsets)
                     (lengths))
             (lengths 1)                ; the length byte
             (let* ((index 0)
                    (error-number (read-var-integer vector index)))
               (lengths index)
               (loop
                 (when (>= index length)
                   (return))
                 (let ((old-index index))
                   (sc-offsets (read-var-integer vector index))
                   (lengths (- index old-index))))
               (values error-number
                       (1+ length)
                       (sc-offsets)
                       (lengths))))))))

(defun break-control (chunk inst stream dstate)
  (declare (ignore inst))
  (flet ((nt (x) (if stream (note x dstate))))
    (case #!-ud2-breakpoints (byte-imm-code chunk dstate)
          #!+ud2-breakpoints (word-imm-code chunk dstate)
      (#.error-trap
       (nt "error trap")
       (handle-break-args #'snarf-error-junk stream dstate))
      (#.cerror-trap
       (nt "cerror trap")
       (handle-break-args #'snarf-error-junk stream dstate))
      (#.breakpoint-trap
       (nt "breakpoint trap"))
      (#.pending-interrupt-trap
       (nt "pending interrupt trap"))
      (#.halt-trap
       (nt "halt trap"))
      (#.fun-end-breakpoint-trap
       (nt "function end breakpoint trap")))))
