;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-

;;; Copyright (C) 2010, Dmitry Ignatiev <lovesan.ru@gmail.com>

;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use, copy,
;;; modify, merge, publish, distribute, sublicense, and/or sell copies
;;; of the Software, and to permit persons to whom the Software is
;;; furnished to do so, subject to the following conditions:

;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.

;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;;; DEALINGS IN THE SOFTWARE.

(in-package #:virgil)

(defmacro define-type-parser (name (&rest args) &body body)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (setf (gethash ',name *type-parsers*)
           (lambda ,args ,@body))
     ',name))

(defmacro defalias (name (&rest args) &body body)
  `(define-type-parser ,name ,args
     (parse-typespec (locally ,@body))))

(defmacro define-primitive-type (&whole form name &rest options)
  (destructuring-bind
      (&key (cffi-type (error "Please supply :cffi-type: ~s" form))
       (lisp-type T)
       (prototype (coerce 0 lisp-type)))
      (flatten-options options)
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (define-type-parser ,name ()
         (make-primitive-type
             :name ',name
           :cffi-type ',cffi-type
           :lisp-type ',lisp-type
           :prototype ,prototype))
       (deftype ,name () ',lisp-type))))

(defmacro %type-method (method-name form type-name-var (&rest args))
  (with-gensyms (body-var)
    `(destructuring-bind
         ((,@args) &body ,body-var) ,form
       `(defmethod ,',method-name
            (,,@(butlast args) (,,@(last args) ,,type-name-var))
          ,@,body-var))))

(defmacro define-immediate-type (name (&rest superclasses)
                                      (&rest slots)
                                      &rest options)
  (destructuring-bind
      (&key (base-type nil base-type-p)
       (lisp-type nil lisp-type-p)
       (prototype nil prototype-p)
       (prototype-expansion nil prototype-expansion-p)
       (translator nil translator-p)
       (translator-expansion nil translator-expansion-p)
       (converter nil converter-p)
       (converter-expansion nil converter-expansion-p)
       (simple-parser nil simple-parser-p)
       (cleaner nil cleaner-p)
       (cleaner-expansion nil cleaner-expansion-p)
       (dynamic-extent-expansion nil dynamic-extent-expansion-p)
       (callback-dynamic-extent-expansion nil callback-dx-p))
      (flatten-options options)
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (defclass ,name (,@superclasses immediate-type)
         (,@slots)
         ,@(when base-type-p
             `((:default-initargs :base-type
                   (parse-typespec ',base-type)))))
       ,(when simple-parser-p
          `(progn
             (define-type-parser ,simple-parser ()
               (make-instance ',name))
             (defmethod unparse-type ((#.(gensym) ,name))
               ',simple-parser)))
       ,(when lisp-type-p
          (%type-method lisp-type lisp-type name
                        (type-var)))
       ,(when prototype-p
          (%type-method prototype prototype name
                        (type-var)))
       ,(when prototype-expansion-p
          (%type-method expand-prototype prototype-expansion name
                        (type-var)))
       ,(when translator-p
          (%type-method translate-value translator name
                        (raw-value-var type-var)))
       ,(when translator-expansion-p
          (%type-method expand-translate-value translator-expansion name
                        (raw-value-form-var type-var)))
       ,(when converter-p
          (%type-method convert-value converter name
                        (lisp-value-var type-var)))
       ,(when converter-expansion-p
          (%type-method expand-convert-value converter-expansion name
                        (lisp-value-form-var type-var)))
       ,(when cleaner-p
          (%type-method cleanup-value cleaner name
                        (pointer-var value-var type-var)))
       ,(when cleaner-expansion-p
          (%type-method expand-cleanup-value cleaner-expansion name
                        (pointer-form-var value-form-var type-var)))
       ,(when dynamic-extent-expansion-p
          (%type-method expand-dynamic-extent dynamic-extent-expansion name
                        (var-var value-var body-var type-var)))
       ,(when callback-dx-p
          (%type-method expand-callback-dynamic-extent
                        callback-dynamic-extent-expansion
                        name
                        (var-var raw-value-var body-var type-var)))
       ',name)))

(defmacro define-aggregate-type (name (&rest superclasses)
                                      (&rest slots)
                                      &rest options)
  (destructuring-bind
      (&key (size nil size-p)
       (size-expansion nil size-expansion-p)
       (fixed-size nil fixed-size-p)
       (align nil align-p)
       (prototype nil prototype-p)
       (prototype-expansion nil prototype-expansion-p)
       (lisp-type nil lisp-type-p)
       (simple-parser nil simple-parser-p)
       (reader nil reader-p)
       (writer nil writer-p)
       (cleaner nil cleaner-p)
       (reader-expansion nil reader-expansion-p)
       (writer-expansion nil writer-expansion-p)
       (cleaner-expansion nil cleaner-expansion-p)
       (reference-dynamic-extent-expansion nil rdx-p))
      (flatten-options options)
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (defclass ,name (,@superclasses aggregate-type)
         (,@slots))
       ,(when simple-parser-p
          `(define-type-parser ,simple-parser ()
             (make-instance ',name)))
       ,(when size-p
          (assert (not fixed-size-p) ()
            "~s : You should not supply both :size and :fixed-size options"
            'define-aggregate-type)
          (%type-method compute-size size name
                        (value-var type-var)))
       ,(when size-expansion-p
          (assert (not fixed-size-p) ()
            "~s : You should not supply both :size-expansion and :fixed-size options"
            'define-aggregate-type)
          (%type-method expand-compute-size size-expansion name
                        (value-form-var type-var)))
       ,(when fixed-size-p
          (with-gensyms (value)
            (destructuring-bind
                ((type-var) &body body) fixed-size
              `(progn
                 (defmethod compute-fixed-size ((,type-var ,name))
                   ,@body)
                 (defmethod compute-size (,value (,type-var ,name))
                   (compute-fixed-size ,type-var))
                 (defmethod expand-compute-size (,value (,type-var ,name))
                   (compute-fixed-size ,type-var))))))
       ,(when align-p
          (%type-method compute-alignment align name
                        (type-var)))
       ,(when prototype-p
          (%type-method prototype prototype name
                        (type-var)))
       ,(when prototype-expansion-p
          (%type-method expand-prototype prototype-expansion name
                        (type-var)))
       ,(when lisp-type-p
          (%type-method lisp-type lisp-type name
                        (type-var)))
       ,(when reader-p
          (%type-method read-value reader name
                        (pointer-var output-var type-var)))
       ,(when writer-p
          (%type-method write-value writer name
                        (value-var pointer-var type-var)))
       ,(when cleaner-p
          (%type-method cleanup-value cleaner name
                        (pointer-var value-var type-var)))
       ,(when reader-expansion-p
          (%type-method expand-read-value reader-expansion name
                        (pointer-form-var output-form-var type-var)))
       ,(when writer-expansion-p
          (%type-method expand-write-value writer-expansion name
                        (value-form-var pointer-form-var type-var)))
       ,(when cleaner-expansion-p
          (%type-method expand-cleanup-value cleaner-expansion name
                        (pointer-form-var value-form-var type-var)))
       ,(when rdx-p
          (%type-method expand-reference-dynamic-extent
                        reference-dynamic-extent-expansion
                        name
                        (var-var size-var-var value-form-var
                                 body-form-var mode-var type-var)))
       ',name)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %int-type (cffi-type &optional signed-p)
    `(,(if signed-p 'signed-byte 'unsigned-byte)
        ,(* (foreign-type-size cffi-type) 8))))