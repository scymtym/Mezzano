;;;; Copyright (c) 2011-2016 Henry Harrington <henry.harrington@gmail.com>
;;;; This code is licensed under the MIT license.

(in-package :mezzano.internals)

(declaim (inline ratiop))
(defun ratiop (object)
  (%object-of-type-p object +object-tag-ratio+))

(defun numerator (rational)
  (etypecase rational
    (ratio (%object-ref-t rational +ratio-numerator+))
    (integer rational)))

(defun denominator (rational)
  (etypecase rational
    (ratio (%object-ref-t rational +ratio-denominator+))
    (integer 1)))

(declaim (inline complexp))
(defun complexp (object)
  (sys.int::%object-of-type-range-p
   object
   sys.int::+first-complex-object-tag+
   sys.int::+last-complex-object-tag+))

(defun complex (realpart &optional imagpart)
  (check-type realpart real)
  (check-type imagpart (or real null))
  (unless imagpart
    (setf imagpart (coerce 0 (type-of realpart))))
  (cond ((or (typep realpart 'double-float)
             (typep imagpart 'double-float))
         (let ((r (%double-float-as-integer (float realpart 0.0d0)))
               (i (%double-float-as-integer (float imagpart 0.0d0)))
               (result (mezzano.runtime::%allocate-object +object-tag-complex-double-float+ 0 2 nil)))
           (setf (%object-ref-unsigned-byte-64 result sys.int::+complex-realpart+) r
                 (%object-ref-unsigned-byte-64 result sys.int::+complex-imagpart+) i)
           result))
        ((or (typep realpart 'single-float)
             (typep imagpart 'single-float))
         (let ((r (%single-float-as-integer (float realpart 0.0f0)))
               (i (%single-float-as-integer (float imagpart 0.0f0)))
               (result (mezzano.runtime::%allocate-object +object-tag-complex-single-float+ 0 1 nil)))
           (setf (%object-ref-unsigned-byte-32 result sys.int::+complex-realpart+) r
                 (%object-ref-unsigned-byte-32 result sys.int::+complex-imagpart+) i)
           result))
        ((or (typep realpart 'short-float)
             (typep imagpart 'short-float))
         (let ((r (%short-float-as-integer (float realpart 0.0s0)))
               (i (%short-float-as-integer (float imagpart 0.0s0)))
               (result (mezzano.runtime::%allocate-object +object-tag-complex-short-float+ 0 1 nil)))
           (setf (%object-ref-unsigned-byte-16 result sys.int::+complex-realpart+) r
                 (%object-ref-unsigned-byte-16 result sys.int::+complex-imagpart+) i)
           result))
        ((not (zerop imagpart))
         (let ((result (mezzano.runtime::%allocate-object +object-tag-complex-rational+ 0 2 nil)))
           (setf (%object-ref-t result sys.int::+complex-realpart+) realpart
                 (%object-ref-t result sys.int::+complex-imagpart+) imagpart)
           result))
        (t
         realpart)))

(defun realpart (number)
  (cond
    ((%object-of-type-p number +object-tag-complex-rational+)
     (%object-ref-t number +complex-realpart+))
    ((%object-of-type-p number +object-tag-complex-short-float+)
     (%integer-as-short-float (%object-ref-unsigned-byte-16 number +complex-realpart+)))
    ((%object-of-type-p number +object-tag-complex-single-float+)
     (%integer-as-single-float (%object-ref-unsigned-byte-32 number +complex-realpart+)))
    ((%object-of-type-p number +object-tag-complex-double-float+)
     (%integer-as-double-float (%object-ref-unsigned-byte-64 number +complex-realpart+)))
    (t
     (check-type number number)
     number)))

(defun imagpart (number)
  (cond
    ((%object-of-type-p number +object-tag-complex-rational+)
     (%object-ref-t number +complex-imagpart+))
    ((%object-of-type-p number +object-tag-complex-short-float+)
     (%integer-as-short-float (%object-ref-unsigned-byte-16 number +complex-imagpart+)))
    ((%object-of-type-p number +object-tag-complex-single-float+)
     (%integer-as-single-float (%object-ref-unsigned-byte-32 number +complex-imagpart+)))
    ((%object-of-type-p number +object-tag-complex-double-float+)
     (%integer-as-double-float (%object-ref-unsigned-byte-64 number +complex-imagpart+)))
    (t
     (check-type number number)
     (* 0 number))))

(defun expt (base power)
  (etypecase power
    (integer
     (cond ((minusp power)
            (/ (expt base (- power))))
           (t (let ((accum 1))
                (dotimes (i power accum)
                  (setf accum (* accum base)))))))
    (float
     (cond ((eql (float (truncate power) power) power)
            ;; Moderately integer-like?
            (expt base (truncate power)))
           ((zerop base)
            (assert (not (minusp power)))
            (float 0.0 power))
           (t
            ;; Slower...
            (exp (* power (log base))))))
    (ratio (exp (* power (log base))))))

(defstruct (large-byte (:constructor make-large-byte (size position)))
  (size 0 :type (integer 0) :read-only t)
  (position 0 :type (integer 0) :read-only t))

;; Stuff size & position into the low 32-bits.
(defconstant +byte-size+ (byte 13 6))
(defconstant +byte-position+ (byte 13 19))

(deftype byte ()
  `(satisfies bytep))

(defun small-byte-p (object)
  (%value-has-immediate-tag-p object +immediate-tag-byte-specifier+))

(defun bytep (object)
  (or (small-byte-p object)
      (large-byte-p object)))

(defun fits-in-field-p (bytespec integer)
  "Test if INTEGER fits in the byte defined by BYTESPEC."
  (eql integer (logand integer
                       (1- (ash 1 (byte-size bytespec))))))

(defun byte (size position)
  (if (and (fits-in-field-p +byte-size+ size)
           (fits-in-field-p +byte-position+ position))
      (%%assemble-value (logior (ash size (byte-position +byte-size+))
                                (ash position (byte-position +byte-position+))
                                (dpb +immediate-tag-byte-specifier+
                                     +immediate-tag+
                                     0))
                        +tag-immediate+)
      (make-large-byte size position)))

(defun byte-size (byte-specifier)
  (if (small-byte-p byte-specifier)
      (ldb +byte-size+ (lisp-object-address byte-specifier))
      (large-byte-size byte-specifier)))

(defun byte-position (byte-specifier)
  (if (small-byte-p byte-specifier)
      (ldb +byte-position+ (lisp-object-address byte-specifier))
      (large-byte-position byte-specifier)))

(declaim (inline %ldb ldb %dpb dpb %ldb-test ldb-test logbitp
                 %mask-field mask-field %deposit-field deposit-field))
(defun %ldb (size position integer)
  (logand (ash integer (- position))
          (1- (ash 1 size))))

(defun ldb (bytespec integer)
  (%ldb (byte-size bytespec) (byte-position bytespec) integer))

(defun %dpb (newbyte size position integer)
  (let ((mask (1- (ash 1 size))))
    (logior (ash (logand newbyte mask) position)
            (logand integer (lognot (ash mask position))))))

(defun dpb (newbyte bytespec integer)
  (%dpb newbyte (byte-size bytespec) (byte-position bytespec) integer))

(defun %ldb-test (size position integer)
  (not (eql 0 (%ldb size position integer))))

(defun ldb-test (bytespec integer)
  (%ldb-test (byte-size bytespec) (byte-position bytespec) integer))

(defun logbitp (index integer)
  (ldb-test (byte 1 index) integer))

(defun %mask-field (size position integer)
  (logand integer (%dpb -1 size position 0)))

(defun mask-field (bytespec integer)
  (%mask-field (byte-size bytespec) (byte-position bytespec) integer))

(defun %deposit-field (newbyte size position integer)
  (let ((mask (%dpb -1 size position 0)))
    (logior (logand integer (lognot mask))
            (logand newbyte mask))))

(defun deposit-field (newbyte bytespec integer)
  (%deposit-field newbyte (byte-size bytespec) (byte-position bytespec) integer))

(defun %double-float-as-integer (double-float)
  (%object-ref-unsigned-byte-64 double-float 0))

(defun %integer-as-double-float (integer)
  (let ((result (mezzano.runtime::%allocate-object
                 sys.int::+object-tag-double-float+ 0 1 nil)))
    (setf (%object-ref-unsigned-byte-64 result 0) integer)
    result))

(declaim (inline call-with-float-contagion))
(defun call-with-float-contagion (x y single-fn double-fn short-fn)
  (cond ((or (double-float-p x)
             (double-float-p y))
         (funcall double-fn
                  (float x 1.0d0)
                  (float y 1.0d0)))
        ((or (single-float-p x)
             (single-float-p y))
         (funcall single-fn
                  (float x 1.0f0)
                  (float y 1.0f0)))
        (t
         (funcall short-fn
                  (float x 1.0s0)
                  (float y 1.0s0)))))

(defun sys.int::full-truncate (number divisor)
  (check-type number real)
  (check-type divisor real)
  (assert (/= divisor 0) (number divisor) 'division-by-zero)
  (cond ((and (sys.int::fixnump number)
              (sys.int::fixnump divisor))
         (error "FIXNUM/FIXNUM case hit GENERIC-TRUNCATE"))
        ((and (sys.int::fixnump number)
              (sys.int::bignump divisor))
         (sys.int::%%bignum-truncate number divisor))
        ((and (sys.int::bignump number)
              (sys.int::fixnump divisor))
         (sys.int::%%bignum-truncate number divisor))
        ((and (sys.int::bignump number)
              (sys.int::bignump divisor))
         (sys.int::%%bignum-truncate number divisor))
        ((or (floatp number)
             (floatp divisor))
         (let* ((val (/ number divisor))
                (integer-part (etypecase val
                                (short-float
                                 (mezzano.runtime::%truncate-short-float val))
                                (single-float
                                 (mezzano.runtime::%truncate-single-float val))
                                (double-float
                                 (mezzano.runtime::%truncate-double-float val)))))
           (values integer-part (* (- val integer-part) divisor))))
        ((or (sys.int::ratiop number)
             (sys.int::ratiop divisor))
         (cond ((integerp number)
                (multiple-value-bind (quot rem)
                    (truncate (* number (denominator divisor))
                              (numerator divisor))
                  (values quot (/ rem (denominator divisor)))))
               (t
                (let ((q (truncate (numerator number)
                                   (* (denominator number) divisor))))
                  (values q (- number (* q divisor)))))))
        (t (check-type number number)
           (check-type divisor number)
           (error "Argument combination ~S and ~S not supported." number divisor))))

(defun sys.int::full-/ (x y)
  (cond ((and (typep x 'integer)
              (typep y 'integer))
         (multiple-value-bind (quot rem)
             (truncate x y)
           (cond ((zerop rem)
                  ;; Remainder is zero, result is an integer.
                  quot)
                 (t ;; Remainder is non-zero, produce a ratio.
                  (let ((negative (if (minusp x)
                                      (not (minusp y))
                                      (minusp y)))
                        (gcd (gcd x y)))
                    (sys.int::make-ratio (if negative
                                             (- (/ (abs x) gcd))
                                             (/ (abs x) gcd))
                                         (/ (abs y) gcd)))))))
        ((or (complexp x)
             (complexp y))
         (complex (/ (+ (* (realpart x) (realpart y))
                        (* (imagpart x) (imagpart y)))
                     (+ (expt (realpart y) 2)
                        (expt (imagpart y) 2)))
                  (/ (- (* (imagpart x) (realpart y))
                        (* (realpart x) (imagpart y)))
                     (+ (expt (realpart y) 2)
                        (expt (imagpart y) 2)))))
        ((or (floatp x)
             (floatp y))
         (call-with-float-contagion x y #'%%single-float-/ #'%%double-float-/ #'%%short-float-/))
        ((or (sys.int::ratiop x) (sys.int::ratiop y))
         (/ (* (numerator x) (denominator y))
            (* (denominator x) (numerator y))))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination ~S and ~S not supported." x y))))

(defun sys.int::full-+ (x y)
  (cond ((and (sys.int::fixnump x)
              (sys.int::fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC-+"))
        ((and (sys.int::fixnump x)
              (sys.int::bignump y))
         (sys.int::%%bignum-+ (sys.int::%make-bignum-from-fixnum x) y))
        ((and (sys.int::bignump x)
              (sys.int::fixnump y))
         (sys.int::%%bignum-+ x (sys.int::%make-bignum-from-fixnum y)))
        ((and (sys.int::bignump x)
              (sys.int::bignump y))
         (sys.int::%%bignum-+ x y))
        ((or (complexp x)
             (complexp y))
         (complex (+ (realpart x) (realpart y))
                  (+ (imagpart x) (imagpart y))))
        ((or (floatp x)
             (floatp y))
         (call-with-float-contagion x y #'%%single-float-+ #'%%double-float-+ #'%%short-float-+))
        ((or (sys.int::ratiop x)
             (sys.int::ratiop y))
         (/ (+ (* (numerator x) (denominator y))
               (* (numerator y) (denominator x)))
            (* (denominator x) (denominator y))))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination ~S and ~S not supported." x y))))

(defun sys.int::full-- (x y)
  (cond ((and (sys.int::fixnump x)
              (sys.int::fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC--"))
        ((and (sys.int::fixnump x)
              (sys.int::bignump y))
         (sys.int::%%bignum-- (sys.int::%make-bignum-from-fixnum x) y))
        ((and (sys.int::bignump x)
              (sys.int::fixnump y))
         (sys.int::%%bignum-- x (sys.int::%make-bignum-from-fixnum y)))
        ((and (sys.int::bignump x)
              (sys.int::bignump y))
         (sys.int::%%bignum-- x y))
        ((or (complexp x)
             (complexp y))
         (complex (- (realpart x) (realpart y))
                  (- (imagpart x) (imagpart y))))
        ((or (floatp x)
             (floatp y))
         (call-with-float-contagion x y #'%%single-float-- #'%%double-float-- #'%%short-float--))
        ((or (sys.int::ratiop x)
             (sys.int::ratiop y))
         (/ (- (* (numerator x) (denominator y))
               (* (numerator y) (denominator x)))
            (* (denominator x) (denominator y))))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination ~S and ~S not supported." x y))))

(defun sys.int::full-* (x y)
  (cond ((and (sys.int::fixnump x)
              (sys.int::fixnump y))
         (error "FIXNUM/FIXNUM case hit GENERIC-*"))
        ((and (sys.int::fixnump x)
              (sys.int::bignump y))
         (sys.int::%%bignum-multiply-signed x y))
        ((and (sys.int::bignump x)
              (sys.int::fixnump y))
         (sys.int::%%bignum-multiply-signed x y))
        ((and (sys.int::bignump x)
              (sys.int::bignump y))
         (sys.int::%%bignum-multiply-signed x y))
        ((or (complexp x)
             (complexp y))
         (complex (- (* (realpart x) (realpart y))
                     (* (imagpart x) (imagpart y)))
                  (+ (* (imagpart x) (realpart y))
                     (* (realpart x) (imagpart y)))))
        ((or (floatp x)
             (floatp y))
         (call-with-float-contagion x y #'%%single-float-* #'%%double-float-* #'%%short-float-*))
        ((or (sys.int::ratiop x)
             (sys.int::ratiop y))
         (/ (* (numerator x) (numerator y))
            (* (denominator x) (denominator y))))
        (t (check-type x number)
           (check-type y number)
           (error "Argument combination ~S and ~S not supported." x y))))

(defun abs (number)
  (check-type number number)
  (etypecase number
    (complex
     (sqrt (+ (expt (realpart number) 2)
              (expt (imagpart number) 2))))
    (single-float
     (%integer-as-single-float
      (logand #x7FFFFFFF
              (%single-float-as-integer number))))
    (double-float
     (%integer-as-double-float
      (logand #x7FFFFFFFFFFFFFFF
              (%double-float-as-integer number))))
    (real
     (if (minusp number)
         (- number)
         number))))

(defun sqrt (number)
  (check-type number number)
  (etypecase number
    (double-float
     (%%double-float-sqrt number))
    (short-float
     (%%short-float-sqrt number))
    (real
     (%%single-float-sqrt (float number 0.0f0)))
    (complex
     (exp (/ (log number) 2)))))

(defun isqrt (number)
  (values (floor (sqrt number))))

(macrolet ((def (name bignum-name)
             `(defun ,name (x y)
                (cond ((and (fixnump x)
                            (fixnump y))
                       (error "FIXNUM/FIXNUM case hit ~S." ',name))
                      ((and (fixnump x)
                            (bignump y))
                       (,bignum-name (%make-bignum-from-fixnum x) y))
                      ((and (bignump x)
                            (fixnump y))
                       (,bignum-name x (%make-bignum-from-fixnum y)))
                      ((and (bignump x)
                            (bignump y))
                       (,bignum-name x y))
                      (t (check-type x integer)
                         (check-type y integer)
                         (error "Argument combination not supported."))))))
  (def generic-logand %%bignum-logand)
  (def generic-logior %%bignum-logior)
  (def generic-logxor %%bignum-logxor))

(defun generic-lognot (integer)
  (logxor integer -1))

(defun logandc1 (integer-1 integer-2)
  "AND complement of INTEGER-1 with INTEGER-2."
  (logand (lognot integer-1) integer-2))

(defun logandc2 (integer-1 integer-2)
  "AND INTEGER-1 with complement of INTEGER-2."
  (logand integer-1 (lognot integer-2)))

(defun lognand (integer-1 integer-2)
  "Complement of INTEGER-1 AND INTEGER-2."
  (lognot (logand integer-1 integer-2)))

(defun lognor (integer-1 integer-2)
  "Complement of INTEGER-1 OR INTEGER-2."
  (lognot (logior integer-1 integer-2)))

(defun logorc1 (integer-1 integer-2)
  "OR complement of INTEGER-1 with INTEGER-2."
  (logior (lognot integer-1) integer-2))

(defun logorc2 (integer-1 integer-2)
  "OR INTEGER-1 with complement of INTEGER-2."
  (logior integer-1 (lognot integer-2)))

(defconstant boole-1 'boole-1 "integer-1")
(defconstant boole-2 'boole-2 "integer-2")
(defconstant boole-andc1 'boole-andc1 "and complement of integer-1 with integer-2")
(defconstant boole-andc2 'boole-andc2 "and integer-1 with complement of integer-2")
(defconstant boole-and 'boole-and "and")
(defconstant boole-c1 'boole-c1 "complement of integer-1")
(defconstant boole-c2 'boole-c2 "complement of integer-2")
(defconstant boole-clr 'boole-clr "always 0 (all zero bits)")
(defconstant boole-eqv 'boole-eqv "equivalence (exclusive nor)")
(defconstant boole-ior 'boole-ior "inclusive or")
(defconstant boole-nand 'boole-nand "not-and")
(defconstant boole-nor 'boole-nor "not-or")
(defconstant boole-orc1 'boole-orc1 "or complement of integer-1 with integer-2")
(defconstant boole-orc2 'boole-orc2 "or integer-1 with complement of integer-2")
(defconstant boole-set 'boole-set "always -1 (all one bits)")
(defconstant boole-xor 'boole-xor "exclusive or")

(defun boole (op integer-1 integer-2)
  "Perform bit-wise logical OP on INTEGER-1 and INTEGER-2."
  (check-type integer-1 integer)
  (check-type integer-2 integer)
  (ecase op
    (boole-1 integer-1)
    (boole-2 integer-2)
    (boole-andc1 (logandc1 integer-1 integer-2))
    (boole-andc2 (logandc2 integer-1 integer-2))
    (boole-and (logand integer-1 integer-2))
    (boole-c1 (lognot integer-1))
    (boole-c2 (lognot integer-2))
    (boole-clr 0)
    (boole-eqv (logeqv integer-1 integer-2))
    (boole-ior (logior integer-1 integer-2))
    (boole-nand (lognand integer-1 integer-2))
    (boole-nor (lognor integer-1 integer-2))
    (boole-orc1 (logorc1 integer-1 integer-2))
    (boole-orc2 (logorc2 integer-1 integer-2))
    (boole-set -1)
    (boole-xor (logxor integer-1 integer-2))))

(defun signum (number)
  (if (zerop number)
      number
      (/ number (abs number))))

;;; Mathematical horrors!

(defconstant pi 3.14159265358979323846264338327950288419716939937511d0)

;;; Derived from SLEEF: https://github.com/shibatch/sleef

(defconstant +sleef-pi4-af+ 0.78515625f0)
(defconstant +sleef-pi4-bf+ 0.00024187564849853515625f0)
(defconstant +sleef-pi4-cf+ 3.7747668102383613586f-08)
(defconstant +sleef-pi4-df+ 1.2816720341285448015f-12)

(defun sleef-mulsignf (x y)
  (sys.int::%integer-as-single-float
   (logxor
    (sys.int::%single-float-as-integer x)
    (logand (sys.int::%single-float-as-integer y)
            (ash 1 31)))))

(defun sleef-signf (d)
  (sleef-mulsignf 1.0f0 d))

(declaim (inline sleef-mlaf))
(defun sleef-mlaf (x y z)
  (declare (type single-float x y z))
  (+ (* x y) z))

(declaim (inline sleef-rintf))
(defun sleef-rintf (x)
  (declare (type single-float x))
  (if (< x 0.0f0)
      (the fixnum (truncate (- x 0.5f0)))
      (the fixnum (truncate (+ x 0.5f0)))))

(defconstant +sleef-pi4-a+ 0.78539816290140151978d0)
(defconstant +sleef-pi4-b+ 4.9604678871439933374d-10)
(defconstant +sleef-pi4-c+ 1.1258708853173288931d-18)
(defconstant +sleef-pi4-d+ 1.7607799325916000908d-27)

(declaim (inline sleef-mla))
(defun sleef-mla (x y z)
  (declare (type double-float x y z))
  (+ (* x y) z))

(declaim (inline sleef-rint))
(defun sleef-rint (x)
  (declare (type double-float x))
  (if (< x 0.0d0)
      (the fixnum (truncate (- x 0.5d0)))
      (the fixnum (truncate (+ x 0.5d0)))))

(declaim (inline finish-sincos-single-float))
(defun finish-sincos-single-float (s d)
  (declare (type single-float s d))
  (let ((u 2.6083159809786593541503f-06))
    (declare (type single-float u))
    (setf u (sleef-mlaf u s -0.0001981069071916863322258f0))
    (setf u (sleef-mlaf u s 0.00833307858556509017944336f0))
    (setf u (sleef-mlaf u s -0.166666597127914428710938f0))

    (setf u (sleef-mlaf s (* u d) d))

    (cond ((float-infinity-p d)
           (/ 0.0f0 0.0f0))
          (t
           u))))

(defun sin-single-float (d)
  (declare (type single-float d)
           (optimize (speed 3) (safety 0) (debug 0)))
  (let* ((q (sleef-rintf (* d (/ (float pi 0.0f0)))))
         (q-float (float q 0.0f0)))
    (declare (type fixnum q)
             (type single-float q-float))
    (setf d (sleef-mlaf q-float (* +sleef-pi4-af+ -4) d))
    (setf d (sleef-mlaf q-float (* +sleef-pi4-bf+ -4) d))
    (setf d (sleef-mlaf q-float (* +sleef-pi4-cf+ -4) d))
    (setf d (sleef-mlaf q-float (* +sleef-pi4-df+ -4) d))
    (let ((s (* d d)))
      (declare (type single-float s))
      (when (logtest q 1)
        (setf d (- 0.0f0 d)))
      (finish-sincos-single-float s d))))

(defun cos-single-float (d)
  (declare (type single-float d)
           (optimize (speed 3) (safety 0) (debug 0)))
  (let* ((q (+ 1 (* 2 (sleef-rintf (- (* d (/ (float pi 0.0f0))) 0.5f0)))))
         (q-float (float q 0.0f0)))
    (declare (type fixnum q)
             (type single-float q-float))
    (setf d (sleef-mlaf q-float (* +sleef-pi4-af+ -2) d))
    (setf d (sleef-mlaf q-float (* +sleef-pi4-bf+ -2) d))
    (setf d (sleef-mlaf q-float (* +sleef-pi4-cf+ -2) d))
    (setf d (sleef-mlaf q-float (* +sleef-pi4-df+ -2) d))
    (let ((s (* d d)))
      (declare (type single-float s))
      (when (not (logtest q 2))
        (setf d (- 0.0f0 d)))
      (finish-sincos-single-float s d))))

(declaim (inline finish-sincos-double-float))
(defun finish-sincos-double-float (s d)
  (declare (type double-float s d))
  (let ((u -7.97255955009037868891952d-18))
    (declare (type double-float u))
    (setf u (sleef-mla u s 2.81009972710863200091251d-15))
    (setf u (sleef-mla u s -7.64712219118158833288484d-13))
    (setf u (sleef-mla u s 1.60590430605664501629054d-10))
    (setf u (sleef-mla u s -2.50521083763502045810755d-08))
    (setf u (sleef-mla u s 2.75573192239198747630416d-06))
    (setf u (sleef-mla u s -0.000198412698412696162806809d0))
    (setf u (sleef-mla u s 0.00833333333333332974823815d0))
    (setf u (sleef-mla u s -0.166666666666666657414808d0))

    (sleef-mla s (* u d) d)))

(defun sin-double-float (d)
  (declare (type double-float d)
           (optimize (speed 3) (safety 0) (debug 0)))
  (let* ((q (sleef-rint (* d (/ (float pi 0.0d0)))))
         (q-float (float q 0.0d0)))
    (declare (type fixnum q)
             (type double-float q-float))
    (setf d (sleef-mla q-float (* +sleef-pi4-a+ -4) d))
    (setf d (sleef-mla q-float (* +sleef-pi4-b+ -4) d))
    (setf d (sleef-mla q-float (* +sleef-pi4-c+ -4) d))
    (setf d (sleef-mla q-float (* +sleef-pi4-d+ -4) d))
    (let ((s (* d d)))
      (declare (type double-float s))
      (when (logtest q 1)
        (setf d (- 0.0d0 d)))
      (finish-sincos-double-float s d))))

(defun cos-double-float (d)
  (declare (type double-float d)
           (optimize (speed 3) (safety 0) (debug 0)))
  (let* ((q (+ 1 (* 2 (sleef-rint (- (* d (/ (float pi 0.0d0))) 0.5d0)))))
         (q-float (float q 0.0d0)))
    (declare (type fixnum q)
             (type double-float q-float))
    (setf d (sleef-mla q-float (* +sleef-pi4-a+ -2) d))
    (setf d (sleef-mla q-float (* +sleef-pi4-b+ -2) d))
    (setf d (sleef-mla q-float (* +sleef-pi4-c+ -2) d))
    (setf d (sleef-mla q-float (* +sleef-pi4-d+ -2) d))
    (let ((s (* d d)))
      (declare (type double-float s))
      (when (not (logtest q 2))
        (setf d (- 0.0d0 d)))
      (finish-sincos-double-float s d))))

(defun sin (x)
  (etypecase x
    (complex
     (let ((real (realpart x))
           (imag (imagpart x)))
       (complex (* (sin real) (cosh imag))
                (* (cos real) (sinh imag)))))
    (double-float
     (sin-double-float x))
    (short-float
     (float (sin-single-float (float x 0.0f0)) 0.0s0))
    (real
     (sin-single-float (float x 0.0f0)))))

(defun cos (x)
  (etypecase x
    (complex
     (let ((real (realpart x))
           (imag (imagpart x)))
       (complex (* (cos real) (cosh imag))
                (- (* (sin real) (sinh imag))))))
    (double-float
     (cos-double-float x))
    (short-float
     (float (cos-single-float (float x 0.0f0)) 0.0s0))
    (real
     (cos-single-float (float x 0.0f0)))))

(defun tan-single-float (d)
  (declare (type single-float d))
  (let* ((q (sleef-rintf (* d 2 (/ (float pi 0.0f0)))))
         (q-float (float q 0.0f0))
         u s
         (x d))
    (declare (type fixnum q)
             (type single-float q-float x))
    (setf x (sleef-mlaf q-float (* +sleef-pi4-af+ -4 0.5f0) x))
    (setf x (sleef-mlaf q-float (* +sleef-pi4-bf+ -4 0.5f0) x))
    (setf x (sleef-mlaf q-float (* +sleef-pi4-cf+ -4 0.5f0) x))
    (setf x (sleef-mlaf q-float (* +sleef-pi4-df+ -4 0.5f0) x))

    (setf s (* x x))

    (when (not (eql (logand q 1) 0))
      (setf x (- x)))

    (setf u 0.00927245803177356719970703f0)
    (setf u (sleef-mlaf u s 0.00331984995864331722259521f0))
    (setf u (sleef-mlaf u s 0.0242998078465461730957031f0))
    (setf u (sleef-mlaf u s 0.0534495301544666290283203f0))
    (setf u (sleef-mlaf u s 0.133383005857467651367188f0))
    (setf u (sleef-mlaf u s 0.333331853151321411132812f0))

    (setf u (sleef-mlaf s (* u x) x))

    (when (not (eql (logand q 1) 0))
      (setf u (/ u)))

    (when (float-infinity-p d)
      (setf u (/ 0.0f0 0.0f0)))

    (if (floatp d)
        (float u d)
        u)))

(defun tan (radians)
  (etypecase radians
    (double-float
     (float (tan-single-float (float radians 0.0f0)) 0.0d0))
    (real
     (tan-single-float (float radians 0.0f0)))))

(defconstant +sleef-r-ln2f+ 1.442695040888963407359924681001892137426645954152985934135449406931f0)
(defconstant +sleef-l2uf+ 0.693145751953125f0)
(defconstant +sleef-l2lf+ 1.428606765330187045f-06)

(defun sleef-ldexpkf (x q)
  (let (u m)
    (setf m (ash q -31))
    (setf m (ash (- (ash (+ m q) -6) m) 4))
    (setf q (- q (ash m 2)))
    (incf m 127)
    (setf m (if (< m 0) 0 m))
    (setf m (if (> m 255) 255 m))
    (setf u (sys.int::%integer-as-single-float (ash m 23)))
    (setf x (* x u u u u))
    (setf u (sys.int::%integer-as-single-float (ash (+ q #x7f) 23)))
    (* x u)))

(defun sleef-ilogbkf (d)
  (let (m q)
    (setf m (< d 5.421010862427522f-20))
    (setf d (if m
                (* 1.8446744073709552f19 d)
                d))
    (setf q (logand (ash (sys.int::%single-float-as-integer d) -23) #xFF))
    (if m
        (- q (+ 64 #x7F))
        (- q #x7F))))

(defun exp-single-float (d)
  (declare (type single-float d))
  (let* ((q (sleef-rintf (* d +sleef-r-ln2f+)))
         (q-float (float q 0.0f0))
         (s d)
         u)
    (declare (type fixnum q)
             (type single-float q-float s))
    (setf s (sleef-mlaf q-float (- +sleef-l2uf+) s))
    (setf s (sleef-mlaf q-float (- +sleef-l2lf+) s))

    (setf u 0.000198527617612853646278381f0)
    (setf u (sleef-mlaf u s 0.00139304355252534151077271f0))
    (setf u (sleef-mlaf u s 0.00833336077630519866943359f0))
    (setf u (sleef-mlaf u s 0.0416664853692054748535156f0))
    (setf u (sleef-mlaf u s 0.166666671633720397949219f0))
    (setf u (sleef-mlaf u s 0.5f0))

    (setf u (+ (* s s u) s 1.0f0))
    (setf u (sleef-ldexpkf u q))

    (if (< d -104) (setf u 0))
    (if (> d  104) (setf u single-float-positive-infinity))

    u))

(defun exp (number)
  (etypecase number
    (double-float
     (float (exp-single-float (float number 0.0f0)) 0.0d0))
    (real
     (exp-single-float (float number 0.0f0)))))

(defun log-e (number)
  (let ((d (float number 0.0f0))
        x x2 tt m e)
    (setf e (sleef-ilogbkf (* d (/ 0.75f0))))
    (setf m (sleef-ldexpkf d (- e)))

    (setf x (/ (- m 1.0f0) (+ m 1.0f0)))
    (setf x2 (* x x))

    (setf tt 0.2392828464508056640625f0)
    (setf tt (sleef-mlaf tt x2 0.28518211841583251953125f0))
    (setf tt (sleef-mlaf tt x2 0.400005877017974853515625f0))
    (setf tt (sleef-mlaf tt x2 0.666666686534881591796875f0))
    (setf tt (sleef-mlaf tt x2 2.0f0))

    (setf x (+ (* x tt) (* 0.693147180559945286226764f0 e)))

    (when (float-infinity-p d)
      (setf x single-float-positive-infinity))
    (when (< d 0)
      (setf x (/ 0.0f0 0.0f0)))
    (when (= d 0)
      (setf x single-float-negative-infinity))

    (if (floatp number)
        (float x number)
        x)))

(defun log (number &optional base)
  (cond (base
         (/ (log number) (log base)))
        ((complexp number)
         (complex (log (abs number)) (phase number)))
        (t
         (log-e number))))

(defun atan (number1 &optional number2)
  (if number2
      (atan2 number1 number2)
      (let ((s (float number1 0.0f0))
            (q 0)
            tt u)
        (when (= (sleef-signf s) -1)
          (setf s (- s))
          (setf q 2))
        (when (> s 1)
          (setf s (/ s))
          (setf q (logior q 1)))

        (setf tt (* s s))

        (setf u 0.00282363896258175373077393f0)
        (setf u (sleef-mlaf u tt -0.0159569028764963150024414f0))
        (setf u (sleef-mlaf u tt 0.0425049886107444763183594f0))
        (setf u (sleef-mlaf u tt -0.0748900920152664184570312f0))
        (setf u (sleef-mlaf u tt 0.106347933411598205566406f0))
        (setf u (sleef-mlaf u tt -0.142027363181114196777344f0))
        (setf u (sleef-mlaf u tt 0.199926957488059997558594f0))
        (setf u (sleef-mlaf u tt -0.333331018686294555664062f0))

        (setf tt (+ s (* s tt u)))

        (when (not (eql (logand q 1) 0))
          (setf tt (- 1.570796326794896557998982f0 tt)))
        (when (not (eql (logand q 2) 0))
          (setf tt (- tt)))
        (if (floatp number1)
            (float tt number1)
            tt))))

(defun atan2 (y x)
  (let ((n (cond ((> x 0) (atan (/ y x)))
                 ((and (>= y 0) (< x 0))
                  (+ (atan (/ y x)) pi))
                 ((and (< y 0) (< x 0))
                  (- (atan (/ y x)) pi))
                 ((and (> y 0) (zerop x))
                  (/ pi 2))
                 ((and (< y 0) (zerop x))
                  (- (/ pi 2)))
                 (t 0))))
    (cond ((and (floatp x) (floatp y))
           (float (float n x) y))
          ((floatp x)
           (float n x))
          ((floatp y)
           (float n y))
          (t n))))

(defun two-arg-gcd (a b)
  (check-type a integer)
  (check-type b integer)
  (setf a (abs a))
  (setf b (abs b))
  (loop (when (zerop b)
          (return a))
     (psetf b (mod a b)
            a b)))

(defun conjugate (number)
  (if (complexp number)
      (complex (realpart number)
               (- (imagpart number)))
      number))

(defun phase (number)
  (atan (imagpart number) (realpart number)))

(defun fix-fdiv-quotient (quotient number divisor)
  (cond ((or (double-float-p number)
             (double-float-p divisor))
         (float quotient 0.0d0))
        ((or (single-float-p number)
             (single-float-p divisor))
         (float quotient 0.0f0))
        ((or (short-float-p number)
             (short-float-p divisor))
         (float quotient 0.0s0))
        (t
         (float quotient 0.0f0))))

(defun ffloor (number &optional (divisor 1))
  (multiple-value-bind (quotient remainder)
      (floor number divisor)
    (values (fix-fdiv-quotient quotient number divisor)
            remainder)))

(defun fceiling (number &optional (divisor 1))
  (multiple-value-bind (quotient remainder)
      (ceiling number divisor)
    (values (fix-fdiv-quotient quotient number divisor)
            remainder)))

(defun ftruncate (number &optional (divisor 1))
  (multiple-value-bind (quotient remainder)
      (truncate number divisor)
    (values (fix-fdiv-quotient quotient number divisor)
            remainder)))

(defun fround (number &optional (divisor 1))
  (multiple-value-bind (quotient remainder)
      (round number divisor)
    (values (fix-fdiv-quotient quotient number divisor)
            remainder)))

;;; INTEGER-DECODE-FLOAT from SBCL.

(defconstant +single-float-significand-byte+ (byte 23 0))
(defconstant +single-float-exponent-byte+ (byte 8 23))
(defconstant +single-float-hidden-bit+ #x800000)
(defconstant +single-float-bias+ 126)
(defconstant +single-float-digits+ 24)
(defconstant +single-float-normal-exponent-max+ 254)
(defconstant +single-float-normal-exponent-min+ 1)

;;; Handle the denormalized case of INTEGER-DECODE-FLOAT for SINGLE-FLOAT.
(defun integer-decode-single-denorm (x)
  (let* ((bits (%single-float-as-integer (abs x)))
         (sig (ash (ldb +single-float-significand-byte+ bits) 1))
         (extra-bias 0))
    (loop
      (unless (zerop (logand sig +single-float-hidden-bit+))
        (return))
      (setq sig (ash sig 1))
      (incf extra-bias))
    (values sig
            (- (- +single-float-bias+)
               +single-float-digits+
               extra-bias)
            (if (minusp (float-sign x)) -1 1))))

;;; Handle the single-float case of INTEGER-DECODE-FLOAT. If an infinity or
;;; NaN, error. If a denorm, call i-d-s-DENORM to handle it.
(defun integer-decode-single-float (x)
  (let* ((bits (%single-float-as-integer (abs x)))
         (exp (ldb +single-float-exponent-byte+ bits))
         (sig (ldb +single-float-significand-byte+ bits))
         (sign (if (minusp (float-sign x)) -1 1))
         (biased (- exp +single-float-bias+ +single-float-digits+)))
    (unless (<= exp +single-float-normal-exponent-max+)
      (error "can't decode NaN or infinity: ~S" x))
    (cond ((and (zerop exp) (zerop sig))
           (values 0 biased sign))
          ((< exp +single-float-normal-exponent-min+)
           (integer-decode-single-denorm x))
          (t
           (values (logior sig +single-float-hidden-bit+) biased sign)))))

(defconstant +double-float-significand-byte+ (byte 20 0))
(defconstant +double-float-exponent-byte+ (byte 11 20))
(defconstant +double-float-hidden-bit+ #x100000)
(defconstant +double-float-bias+ 1022)
(defconstant +double-float-digits+ 53)
(defconstant +double-float-normal-exponent-max+ 2046)
(defconstant +double-float-normal-exponent-min+ 1)

;;; like INTEGER-DECODE-SINGLE-DENORM, only doubly so
(defun integer-decode-double-denorm (x)
  (let* ((bits (%double-float-as-integer (abs x)))
         (high-bits (ldb (byte 32 32) bits))
         (sig-high (ldb +double-float-significand-byte+ high-bits))
         (low-bits (ldb (byte 32 0) bits))
         (sign (if (minusp (float-sign x)) -1 1))
         (biased (- (- +double-float-bias+) +double-float-digits+)))
    (if (zerop sig-high)
        (let ((sig low-bits)
              (extra-bias (- +double-float-digits+ 33))
              (bit (ash 1 31)))
          (loop
            (unless (zerop (logand sig bit)) (return))
            (setq sig (ash sig 1))
            (incf extra-bias))
          (values (ash sig (- +double-float-digits+ 32))
                  (- biased extra-bias)
                  sign))
        (let ((sig (ash sig-high 1))
              (extra-bias 0))
          (loop
            (unless (zerop (logand sig +double-float-hidden-bit+))
              (return))
            (setq sig (ash sig 1))
            (incf extra-bias))
          (values (logior (ash sig 32) (ash low-bits (1- extra-bias)))
                  (- biased extra-bias)
                  sign)))))

;;; like INTEGER-DECODE-SINGLE-FLOAT, only doubly so
(defun integer-decode-double-float (x)
  (let* ((abs (abs x))
         (bits (%double-float-as-integer abs))
         (hi (ldb (byte 32 32) bits))
         (lo (ldb (byte 32 0) bits))
         (exp (ldb +double-float-exponent-byte+ hi))
         (sig (ldb +double-float-significand-byte+ hi))
         (sign (if (minusp (float-sign x)) -1 1))
         (biased (- exp +double-float-bias+ +double-float-digits+)))
    (unless (<= exp +double-float-normal-exponent-max+)
      (error "Can't decode NaN or infinity: ~S." x))
    (cond ((and (zerop exp) (zerop sig) (zerop lo))
           (values 0 biased sign))
          ((< exp +double-float-normal-exponent-min+)
           (integer-decode-double-denorm x))
          (t
           (values
            (logior (ash (logior (ldb +double-float-significand-byte+ hi)
                                 +double-float-hidden-bit+)
                         32)
                    lo)
            biased sign)))))

(defconstant +short-float-significand-byte+ (byte 10 0))
(defconstant +short-float-exponent-byte+ (byte 5 10))
(defconstant +short-float-hidden-bit+ #x0400)
(defconstant +short-float-bias+ 14)
(defconstant +short-float-digits+ 11)
(defconstant +short-float-normal-exponent-max+ 30)
(defconstant +short-float-normal-exponent-min+ 1)

;;; like INTEGER-DECODE-SINGLE-DENORM, only half as much so
(defun integer-decode-short-denorm (x)
  (let* ((bits (%short-float-as-integer (abs x)))
         (sig (ash (ldb +short-float-significand-byte+ bits) 1))
         (extra-bias 0))
    (loop
      (unless (zerop (logand sig +short-float-hidden-bit+))
        (return))
      (setq sig (ash sig 1))
      (incf extra-bias))
    (values sig
            (- (- +short-float-bias+)
               +short-float-digits+
               extra-bias)
            (if (minusp (float-sign x)) -1 1))))

;;; like INTEGER-DECODE-SINGLE-FLOAT, only doubly so
(defun integer-decode-short-float (x)
  (let* ((bits (%short-float-as-integer (abs x)))
         (exp (ldb +short-float-exponent-byte+ bits))
         (sig (ldb +short-float-significand-byte+ bits))
         (sign (if (minusp (float-sign x)) -1 1))
         (biased (- exp +short-float-bias+ +short-float-digits+)))
    (unless (<= exp +short-float-normal-exponent-max+)
      (error "can't decode NaN or infinity: ~S" x))
    (cond ((and (zerop exp) (zerop sig))
           (values 0 biased sign))
          ((< exp +short-float-normal-exponent-min+)
           (integer-decode-short-denorm x))
          (t
           (values (logior sig +short-float-hidden-bit+) biased sign)))))

(defun integer-decode-float (float)
  (etypecase float
    (short-float (integer-decode-short-float float))
    (single-float (integer-decode-single-float float))
    (double-float (integer-decode-double-float float))))

(defun float-sign (float1 &optional (float2 (float 1 float1)))
  "Return a floating-point number that has the same sign as
   FLOAT1 and, if FLOAT2 is given, has the same absolute value
   as FLOAT2."
  (check-type float1 float)
  (check-type float2 float)
  (* (if (etypecase float1
           (short-float (logbitp 15 (%short-float-as-integer float1)))
           (single-float (logbitp 31 (%single-float-as-integer float1)))
           (double-float (logbitp 63 (%double-float-as-integer float1))))
         (float -1 float1)
         (float 1 float1))
     (abs float2)))

(defun float-digits (f)
  (check-type f float)
  (etypecase f
    (short-float +short-float-digits+)
    (single-float +single-float-digits+)
    (double-float +double-float-digits+)))

(defun float-radix (x)
  "Return (as an integer) the radix b of its floating-point argument."
  (check-type x float)
  2)

(defun float-denormalized-p (x)
  "Return true if the float X is denormalized."
  (check-type x float)
  (etypecase x
    (short-float
     (and (zerop (ldb +short-float-exponent-byte+ (%short-float-as-integer x)))
          (not (zerop x))))
    (single-float
     (and (zerop (ldb +single-float-exponent-byte+ (%single-float-as-integer x)))
          (not (zerop x))))
    ((double-float)
     (and (zerop (ldb +double-float-exponent-byte+
                      (ash (%double-float-as-integer x) -32)))
          (not (zerop x))))))

(defun float-precision (f)
  "Return a non-negative number of significant digits in its float argument.
  Will be less than FLOAT-DIGITS if denormalized or zero."
  (check-type f float)
  (macrolet ((frob (digits bias decode)
               `(cond ((zerop f) 0)
                      ((float-denormalized-p f)
                       (multiple-value-bind (ignore exp) (,decode f)
                         (declare (ignore ignore))
                         (the fixnum
                                    (+ ,digits (1- ,digits) ,bias exp))))
                      (t
                       ,digits))))
    (etypecase f
      (short-float
       (frob +short-float-digits+ +short-float-bias+
         integer-decode-short-denorm))
      (single-float
       (frob +single-float-digits+ +single-float-bias+
         integer-decode-single-denorm))
      (double-float
       (frob +double-float-digits+ +double-float-bias+
         integer-decode-double-denorm)))))

(defun scale-float (float integer)
  (* float (expt (float (float-radix float) float) integer)))

;;; Handle the denormalized case of DECODE-SINGLE-FLOAT. We call
;;; INTEGER-DECODE-SINGLE-DENORM and then make the result into a float.
(defun decode-single-denorm (x)
  (check-type x single-float)
  (multiple-value-bind (sig exp sign)
      (integer-decode-single-denorm x)
    (values (%integer-as-single-float
             (dpb sig +single-float-significand-byte+
                  (dpb +single-float-bias+
                       +single-float-exponent-byte+
                       0)))
            (+ exp +single-float-digits+)
            (float sign x))))

;;; Handle the single-float case of DECODE-FLOAT. If an infinity or NaN,
;;; error. If a denorm, call d-s-DENORM to handle it.
(defun decode-single-float (x)
  (check-type x single-float)
  (let* ((bits (%single-float-as-integer (abs x)))
         (exp (ldb +single-float-exponent-byte+ bits))
         (sign (float-sign x))
         (biased (- exp +single-float-bias+)))
    (unless (<= exp +single-float-normal-exponent-max+)
      (error "can't decode NaN or infinity: ~S" x))
    (cond ((zerop x)
           (values 0.0f0 biased sign))
          ((< exp +single-float-normal-exponent-min+)
           (decode-single-denorm x))
          (t
           (values (%integer-as-single-float
                    (dpb +single-float-bias+
                         +single-float-exponent-byte+
                         bits))
                   biased sign)))))

;;; like DECODE-SINGLE-DENORM, only doubly so
(defun decode-double-denorm (x)
  (check-type x double-float)
  (multiple-value-bind (sig exp sign)
      (integer-decode-double-denorm x)
    (values (%integer-as-double-float
             (logior
              (ash (dpb (logand (ash sig -32)
                                (lognot +double-float-hidden-bit+))
                        +double-float-significand-byte+
                        (dpb +double-float-bias+
                             +double-float-exponent-byte+
                             0))
                   32)
              (ldb (byte 32 0) sig)))
            (+ exp +double-float-digits+)
            (float sign x))))

;;; like DECODE-SINGLE-FLOAT, only doubly so
(defun decode-double-float (x)
  (check-type x double-float)
  (let* ((abs (abs x))
         (hi (ldb (byte 32 32) (%double-float-as-integer abs)))
         (lo (ldb (byte 32 0) (%double-float-as-integer abs)))
         (exp (ldb +double-float-exponent-byte+ hi))
         (sign (float-sign x))
         (biased (- exp +double-float-bias+)))
    (unless (<= exp +double-float-normal-exponent-max+)
      (error "can't decode NaN or infinity: ~S" x))
    (cond ((zerop x)
           (values 0.0d0 biased sign))
          ((< exp +double-float-normal-exponent-min+)
           (decode-double-denorm x))
          (t
           (values (%integer-as-double-float
                    (logior
                     (ash (dpb +double-float-bias+
                               +double-float-exponent-byte+ hi)
                          32)
                     lo))
                   biased sign)))))

;;; Handle the denormalized case of DECODE-SHORT-FLOAT. We call
;;; INTEGER-DECODE-SHORT-DENORM and then make the result into a float.
(defun decode-short-denorm (x)
  (check-type x short-float)
  (multiple-value-bind (sig exp sign)
      (integer-decode-short-denorm x)
    (values (%integer-as-short-float
             (dpb sig +short-float-significand-byte+
                  (dpb +short-float-bias+
                       +short-float-exponent-byte+
                       0)))
            (+ exp +short-float-digits+)
            (float sign x))))

;;; Handle the short-float case of DECODE-FLOAT. If an infinity or NaN,
;;; error. If a denorm, call d-s-DENORM to handle it.
(defun decode-short-float (x)
  (check-type x short-float)
  (let* ((bits (%short-float-as-integer (abs x)))
         (exp (ldb +short-float-exponent-byte+ bits))
         (sign (float-sign x))
         (biased (- exp +short-float-bias+)))
    (unless (<= exp +short-float-normal-exponent-max+)
      (error "can't decode NaN or infinity: ~S" x))
    (cond ((zerop x)
           (values 0.0f0 biased sign))
          ((< exp +short-float-normal-exponent-min+)
           (decode-short-denorm x))
          (t
           (values (%integer-as-short-float
                    (dpb +short-float-bias+
                         +short-float-exponent-byte+
                         bits))
                   biased sign)))))

;;; Dispatch to the appropriate type-specific function.
(defun decode-float (f)
  "Return three values:
   1) a floating-point number representing the significand. This is always
      between 0.5 (inclusive) and 1.0 (exclusive).
   2) an integer representing the exponent.
   3) -1.0 or 1.0 (i.e. the sign of the argument.)"
  (check-type f float)
  (etypecase f
    (single-float
     (decode-single-float f))
    (double-float
     (decode-double-float f))
    (short-float
     (decode-short-float f))))

;;; These functions let us create floats from bits with the
;;; significand uniformly represented as an integer. This is less
;;; efficient for double floats, but is more convenient when making
;;; special values, etc.
(defun single-from-bits (sign exp sig)
  (declare (type bit sign) (type (unsigned-byte 24) sig)
           (type (unsigned-byte 8) exp))
  (%integer-as-single-float
   (dpb exp +single-float-exponent-byte+
        (dpb sig +single-float-significand-byte+
             (if (zerop sign) 0 #x80000000)))))
(defun double-from-bits (sign exp sig)
  (declare (type bit sign) (type (unsigned-byte 53) sig)
           (type (unsigned-byte 11) exp))
  (%integer-as-double-float
   (logior (ash (dpb exp +double-float-exponent-byte+
                     (dpb (ash sig -32)
                          +double-float-significand-byte+
                          (if (zerop sign) 0 #x80000000)))
                32)
           (ldb (byte 32 0) sig))))
(defun short-from-bits (sign exp sig)
  (declare (type bit sign) (type (unsigned-byte 11) sig)
           (type (unsigned-byte 5) exp))
  (%integer-as-short-float
   (dpb exp +short-float-exponent-byte+
        (dpb sig +short-float-significand-byte+
             (if (zerop sign) 0 #x8000)))))

;;; Ratio to float conversion from SBCL 1.4.2

;;; Convert a ratio to a float. We avoid any rounding error by doing an
;;; integer division. Accuracy is important to preserve print-read
;;; consistency, since this is ultimately how the reader reads a float. We
;;; scale the numerator by a power of two until the division results in the
;;; desired number of fraction bits, then do round-to-nearest.
(defun ratio-to-float (x format)
  (let* ((signed-num (numerator x))
         (plusp (plusp signed-num))
         (num (if plusp signed-num (- signed-num)))
         (den (denominator x))
         (digits (ecase format
                   (short-float +short-float-digits+)
                   (single-float +single-float-digits+)
                   (double-float +double-float-digits+)))
         (scale 0))
    (declare (type fixnum digits scale))
    ;; Strip any trailing zeros from the denominator and move it into the scale
    ;; factor (to minimize the size of the operands.)
    (let ((den-twos (1- (integer-length (logxor den (1- den))))))
      (declare (type fixnum den-twos))
      (decf scale den-twos)
      (setq den (ash den (- den-twos))))
    ;; Guess how much we need to scale by from the magnitudes of the numerator
    ;; and denominator. We want one extra bit for a guard bit.
    (let* ((num-len (integer-length num))
           (den-len (integer-length den))
           (delta (- den-len num-len))
           (shift (1+ (the fixnum (+ delta digits))))
           (shifted-num (ash num shift)))
      (declare (type fixnum delta shift))
      (decf scale delta)
      (labels ((float-and-scale (bits)
                 (let* ((bits (ash bits -1))
                        (len (integer-length bits)))
                   (cond ((> len digits)
                          (assert (= len (the fixnum (1+ digits))))
                          (scale-float (floatit (ash bits -1)) (1+ scale)))
                         (t
                          (scale-float (floatit bits) scale)))))
               (floatit (bits)
                 (let ((sign (if plusp 0 1)))
                   (case format
                     (short-float
                      (short-from-bits sign +short-float-bias+ bits))
                     (single-float
                      (single-from-bits sign +single-float-bias+ bits))
                     (double-float
                      (double-from-bits sign +double-float-bias+ bits))))))
        (loop
          (multiple-value-bind (fraction-and-guard rem)
              (truncate shifted-num den)
            (let ((extra (- (integer-length fraction-and-guard) digits)))
              (declare (type fixnum extra))
              (cond ((/= extra 1)
                     (assert (> extra 1)))
                    ((oddp fraction-and-guard)
                     (return
                      (if (zerop rem)
                          (float-and-scale
                           (if (zerop (logand fraction-and-guard 2))
                               fraction-and-guard
                               (1+ fraction-and-guard)))
                          (float-and-scale (1+ fraction-and-guard)))))
                    (t
                     (return (float-and-scale fraction-and-guard)))))
            (setq shifted-num (ash shifted-num -1))
            (incf scale)))))))

(defun rational (number)
  (check-type number real)
  (etypecase number
    (rational
     number)
    (float
     (multiple-value-bind (significand exponent sign)
         (integer-decode-float number)
       (if (eql significand 0)
           0
           (let ((signed-significand (if (minusp sign)
                                         (- significand)
                                         significand)))
             (if (minusp exponent)
                 (* signed-significand (/ (ash 1 (- exponent))))
                 (ash signed-significand exponent))))))))

(defun rationalize (number)
  (rational number))

(defun short-float-to-ieee-binary16 (short-float)
  "Reinterpret SHORT-FLOAT as an (unsigned-byte 16).
This returns the raw IEEE binary representation of the float as an integer.
0.0s0 => #x0000, 1.0s0 => #x3C00, etc."
  (check-type short-float short-float)
  (%short-float-as-integer short-float))

(defun ieee-binary16-to-short-float (ieee-binary16)
  "Reinterpret the (unsigned-byte 16) IEEE-BINARY16 as a short-float.
This converts the raw IEEE binary representation to a float.
#x0000 => 0.0s0, #x3C00 => 1.0s0, etc."
  (check-type ieee-binary16 (unsigned-byte 16))
  (%integer-as-short-float ieee-binary16))

(defun single-float-to-ieee-binary32 (single-float)
  "Reinterpret SINGLE-FLOAT as an (unsigned-byte 32).
This returns the raw IEEE binary representation of the float as an integer.
0.0f0 => #x00000000, 1.0f0 => #x3F800000, etc."
  (check-type single-float single-float)
  (%single-float-as-integer single-float))

(defun ieee-binary32-to-single-float (ieee-binary32)
  "Reinterpret the (unsigned-byte 32) IEEE-BINARY32 as a single-float.
This converts the raw IEEE binary representation to a float.
#x00000000 => 0.0f0, #x3F800000 => 1.0f0, etc."
  (check-type ieee-binary32 (unsigned-byte 32))
  (%integer-as-single-float ieee-binary32))

(defun double-float-to-ieee-binary64 (double-float)
  "Reinterpret DOUBLE-FLOAT as an (unsigned-byte 64).
This returns the raw IEEE binary representation of the float as an integer.
0.0d0 => #x0000000000000000, 1.0d0 => #x3FF0000000000000, etc."
  (check-type double-float double-float)
  (%double-float-as-integer double-float))

(defun ieee-binary64-to-double-float (ieee-binary64)
  "Reinterpret the (unsigned-byte 64) IEEE-BINARY64 as a double-float.
This converts the raw IEEE binary representation to a float.
#x0000000000000000 => 0.0d0, #x3FF0000000000000 => 1.0d0, etc."
  (check-type ieee-binary64 (unsigned-byte 64))
  (%integer-as-double-float ieee-binary64))
