;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; gs-priority.lisp -- feature channels and the priority map.
;;;
;;; Handoff sections 5.1 and 5.3.  Loaded after gs-params.lisp and before
;;; gs-diffuser.lisp and gs-eye.lisp; it also holds the small geometry and
;;; statistics helpers those files use.
;;;
;;;     P_i = w_BU BU_i + w_TD TD_i + w_H H_i + w_V V_i + w_S S_i
;;;           - w_E e_i + eps_i
;;;
;;; Only guiding features (:gs-guiding-features) enter it.  Identification-only
;;; features such as SHAPE never do; that single rule is what keeps 2-vs-5
;;; inefficient while feature search stays efficient.

(in-package :cl-user)

;;; ------------------------------------------------------------------
;;; Numeric helpers
;;; ------------------------------------------------------------------

(defun gs-erf (x)
  "Abramowitz and Stegun 7.1.26; absolute error below 1.5e-7."
  (let* ((sign (if (minusp x) -1.0 1.0))
         (ax (abs (coerce x 'double-float)))
         (tt (/ 1.0d0 (+ 1.0d0 (* 0.3275911d0 ax))))
         (y (- 1.0d0
               (* (+ (* (+ (* (+ (* (+ (* 1.061405429d0 tt) -1.453152027d0) tt)
                                  1.421413741d0) tt)
                           -0.284496736d0) tt)
                     0.254829592d0)
                  tt (exp (- (* ax ax)))))))
    (coerce (* sign y) 'single-float)))

(defun gs-normal-cdf (z)
  (* 0.5 (+ 1.0 (gs-erf (/ z (sqrt 2.0))))))

(defun gs-logistic-noise (s)
  "Logistic noise of scale S, or 0 when S is zero."
  (if (and (numberp s) (plusp s)) (act-r-noise s) 0.0))

(defun gs-standard-normal ()
  "A unit-variance sample from ACT-R's stream, EMMA's approximation.

EMMA's ADD-GAUSSIAN-NOISE takes a logistic sample scaled so its SD matches
the requested one; the same trick with SD 1 gives sqrt(3)/pi."
  (act-r-noise (/ (sqrt 3.0) pi)))

(defun gs-wald (mean shape)
  "Inverse Gaussian sample, Michael, Schucany and Haas (1976)."
  (if (or (not (plusp mean)) (not (plusp shape)))
      (max 0.0 mean)
    (let* ((n (gs-standard-normal))
           (y (* n n))
           (x (+ mean
                 (/ (* mean mean y) (* 2.0 shape))
                 (- (* (/ mean (* 2.0 shape))
                       (sqrt (max 0.0 (+ (* 4.0 mean shape y)
                                         (* mean mean y y))))))))
           (u (act-r-random 1.0)))
      (max 0.0 (if (<= u (/ mean (+ mean x))) x (/ (* mean mean) x))))))

(defun gs-ecc-deg (vis-mod x y)
  "Eccentricity in degrees of the pixel position (X,Y) from the current gaze.

Uses PM-PIXELS-TO-ANGLE so that the module and harness/tasks.py measure the
same thing; see the note in that file about ACT-R's chord convention."
  (let ((eye (eye-xyz vis-mod)))
    (pm-pixels-to-angle (sqrt (+ (expt (- x (aref eye 0)) 2)
                                 (expt (- y (aref eye 1)) 2))))))

;;; ------------------------------------------------------------------
;;; Channels (section 5.1)
;;; ------------------------------------------------------------------

(defparameter *gs-color-map*
  '((red . red) (dark-red . red) (pink . red)
    (green . green) (dark-green . green)
    (blue . blue) (light-blue . blue) (dark-blue . blue)
    (cyan . blue) (dark-cyan . blue) (purple . blue)
    (magenta . blue) (dark-magenta . blue)
    (yellow . yellow) (dark-yellow . yellow) (brown . yellow)
    (black . black) (dark-gray . black)
    (white . white) (light-gray . white) (gray . white))
  "ACT-R colour names folded onto the six Guided Search colour channels.
A colour that is not listed becomes its own channel, so custom colours still
match a template exactly.")

(defun gs-hue-channel (hue)
  (let ((h (mod (float hue) 360.0)))
    (cond ((or (>= h 330.0) (< h 30.0)) 'red)
          ((< h 90.0) 'yellow)
          ((< h 150.0) 'green)
          (t 'blue))))

(defun gs-color-channels (color hue)
  "HUE wins when present; otherwise the COLOR symbol is folded."
  (cond ((numberp hue) (list (cons (gs-hue-channel hue) 1.0)))
        ((null color) nil)
        (t (list (cons (or (cdr (assoc color *gs-color-map*)) color) 1.0)))))

(defparameter *gs-orient-ramp* 10.0
  "Degrees of linear ramp either side of an orientation channel boundary.")

(defun gs-orient-hard (theta)
  (let ((a (abs theta)))
    (cond ((< a 22.5) 'steep)
          ((> a 67.5) 'shallow)
          ((plusp theta) 'right)
          (t 'left))))

(defun gs-orient-channels (theta)
  "steep / shallow / left / right with soft boundaries.

Guided Search 2 lets one item drive a steep/shallow and a left/right channel
at the same time; the exclusive binning here is the simplification the handoff
records in section 5.1.  Only the boundaries are softened."
  (if (not (numberp theta))
      nil
    (let ((tt (- (mod (+ (float theta) 90.0) 180.0) 90.0)))
      (dolist (edge '(-67.5 -22.5 22.5 67.5) (list (cons (gs-orient-hard tt) 1.0)))
        (let ((d (- tt edge)))
          (when (< (abs d) *gs-orient-ramp*)
            (let ((below (gs-orient-hard (- edge *gs-orient-ramp*)))
                  (above (gs-orient-hard (+ edge *gs-orient-ramp*))))
              (unless (eq below above)
                (let ((w (/ (+ d *gs-orient-ramp*) (* 2.0 *gs-orient-ramp*))))
                  (return (list (cons below (- 1.0 w)) (cons above w))))))))))))

(defparameter *gs-size-names* #(small medium large))
(defparameter *gs-lum-names* #(dark mid bright))

(defun gs-tercile-channels (v range names)
  "Bin V into terciles of RANGE, a (lo . hi) pair.  Degenerate ranges give the
middle channel, so a display where every item is the same size does not make
size a guiding dimension by accident."
  (if (or (not (numberp v)) (null range))
      nil
    (let ((lo (car range)) (hi (cdr range)))
      (if (<= hi lo)
          (list (cons (aref names 1) 1.0))
        (let ((f (/ (- (float v) lo) (- hi lo))))
          (list (cons (aref names (cond ((< f 1/3) 0) ((< f 2/3) 1) (t 2))) 1.0)))))))

(defun gs-channels-for (vis-mod slot value &optional hue)
  "Channel alist for one feature slot, in the current display's context."
  (let ((ranges (display-ranges vis-mod)))
    (case slot
      (color (gs-color-channels value hue))
      (orient (gs-orient-channels value))
      (size (gs-tercile-channels value (getf ranges 'size) *gs-size-names*))
      (lum (gs-tercile-channels value (getf ranges 'lum) *gs-lum-names*))
      (t (when value (list (cons value 1.0)))))))

(defun gs-channel-distance (a b)
  (if (or (null a) (null b))
      0.0
    (let ((keys (union (mapcar #'car a) (mapcar #'car b))))
      (* 0.5 (loop for k in keys
                   sum (abs (- (or (cdr (assoc k a :test 'equal)) 0.0)
                               (or (cdr (assoc k b :test 'equal)) 0.0))))))))

(defun gs-channel-overlap (a b)
  (if (or (null a) (null b)) 0.0 (- 1.0 (gs-channel-distance a b))))

(defun gs-template-channels (vis-mod template)
  "Map a template plist onto channels.

Per section 5.7 a symbol names a channel directly and a number is mapped
through the same binning as an item's own value, so both
`color red` and `hue 5` reach the RED channel."
  (let (out)
    (loop for (slot value) on template by #'cddr
          do (push slot out)
             (push (cond ((and (eq slot 'color) (symbolp value))
                          (gs-color-channels value nil))
                         ((and (eq slot 'hue) (numberp value))
                          (gs-color-channels nil value))
                         ((and (symbolp value) (not (null value))
                               (member slot '(orient size lum)))
                          (list (cons value 1.0)))   ; already a channel name
                         (t (gs-channels-for vis-mod slot value)))
                   out))
    (nreverse out)))

;;; ------------------------------------------------------------------
;;; Priority map (section 5.3)
;;; ------------------------------------------------------------------

(defun gs-guiding-template-slots (vis-mod)
  "Template slots that may guide: guiding features, further restricted by the
optional `guide` slot of the gs-search request."
  (let ((guiding (guiding-features vis-mod))
        (restrict (guide-set vis-mod))
        out)
    (loop for (slot nil) on (template vis-mod) by #'cddr
          when (and (member slot guiding)
                    (or (null restrict) (member slot restrict)))
            do (push slot out))
    (nreverse out)))

(defun gs-available-p (vis-mod icon slot now)
  (let ((ts (gethash slot (gsi-feats icon))))
    (and ts (<= (- now ts) (iconic-span vis-mod)))))

(defun gs-bottom-up (vis-mod icons now)
  "Mean channel dissimilarity from the 8 nearest neighbours, scaled by 1/distance.

Eight neighbours rather than Guided Search 2's 5x5 window so that displays of
any density behave alike (handoff section 5.3).  A SALIENCE slot, if any item
has one, replaces the whole computation."
  (let ((table (make-hash-table :test 'equal))
        (guiding (guiding-features vis-mod)))
    (if (some #'gsi-salience icons)
        (let ((smax (reduce #'max icons :key (lambda (i) (abs (or (gsi-salience i) 0.0)))
                                        :initial-value 0.0)))
          (dolist (i icons) (setf (gethash (gsi-entry i) table)
                                  (if (plusp smax) (/ (or (gsi-salience i) 0.0) smax) 0.0))))
      (dolist (a icons)
        (let ((neighbours nil))
          (dolist (b icons)
            (unless (eq a b)
              (push (cons (pm-pixels-to-angle
                           (sqrt (+ (expt (- (gsi-x a) (gsi-x b)) 2)
                                    (expt (- (gsi-y a) (gsi-y b)) 2))))
                          b)
                    neighbours)))
          (setf neighbours (subseq (sort neighbours #'< :key #'car)
                                   0 (min 8 (length neighbours))))
          (let ((total 0.0))
            (dolist (nb neighbours)
              (let ((d (max 1.0 (car nb))) (b (cdr nb)) (s 0.0))
                (dolist (k guiding)
                  (when (and (gs-available-p vis-mod a k now)
                             (gs-available-p vis-mod b k now))
                    (incf s (gs-channel-distance (getf (gsi-channels a) k)
                                                 (getf (gsi-channels b) k)))))
                (incf total (/ s d))))
            (setf (gethash (gsi-entry a) table)
                  (if neighbours (/ total (length neighbours)) 0.0))))))
    table))

(defun gs-top-down (vis-mod icons tmpl-ch now)
  "1 for a channel match, 0 for a mismatch, 0.5 when the feature is unknown.

When the template holds no guiding feature at all -- the 2-vs-5 case, whose
template is `shape two` -- every item scores 1, which is the module's way of
saying that nothing guides."
  (let ((table (make-hash-table :test 'equal))
        (slots (gs-guiding-template-slots vis-mod)))
    (if (null slots)
        (dolist (i icons) (setf (gethash (gsi-entry i) table) 1.0))
      (dolist (i icons)
        (let ((s 0.0))
          (dolist (k slots)
            (incf s (if (gs-available-p vis-mod i k now)
                        (gs-channel-overlap (getf (gsi-channels i) k)
                                            (getf tmpl-ch k))
                        0.5)))            ; PAAV uncertainty rule
          (setf (gethash (gsi-entry i) table) (/ s (length slots))))))
    table))

(defun gs-trace-value (vis-mod key now-s)
  (let ((v (gethash key (history vis-mod))))
    (if (null v)
        0.0
      (* (car v) (exp (- (/ (- now-s (cdr v)) (priming-tau vis-mod))))))))

(defun gs-bump-trace (vis-mod key now-s)
  (setf (gethash key (history vis-mod))
        (cons (+ 1.0 (gs-trace-value vis-mod key now-s)) now-s)))

(defun gs-history-term (vis-mod icons now)
  (let ((table (make-hash-table :test 'equal))
        (guiding (guiding-features vis-mod))
        (now-s (ms->seconds now)))
    (dolist (i icons)
      (let ((s 0.0))
        (dolist (k guiding)
          (when (gs-available-p vis-mod i k now)
            (dolist (c (getf (gsi-channels i) k))
              (incf s (* (cdr c) (gs-trace-value vis-mod (cons k (car c)) now-s))))))
        (setf (gethash (gsi-entry i) table) s)))
    table))

(defun gs-normalise (table)
  "Divide by the display maximum.  This keeps a table whose entries are all
equal at 1.0, which min-max normalisation would turn into 0/0."
  (let ((m 0.0))
    (maphash (lambda (k v) (declare (ignore k)) (when (> v m) (setf m v))) table)
    (when (plusp m)
      (maphash (lambda (k v) (setf (gethash k table) (/ v m))) table))
    table))

(defun gs-value-term (vis-mod icon)
  (let ((hook (value-hook vis-mod)))
    (if (and hook (gsi-chunk icon))
        (let ((r (dispatch-apply hook (gsi-chunk icon))))
          (if (numberp r) r 0.0))
      0.0)))

(defun gs-compute-priority (vis-mod)
  "Recompute the priority of every item in iconic memory.

Called when a search starts, when a saccade lands and when the visicon
changes.  Returns the raw top-down table, which the caller needs for the
effective set size."
  (let* ((now (mp-time-ms))
         (icons (loop for e in (icon-order vis-mod)
                      for i = (gethash e (iconic vis-mod))
                      when i collect i))
         (tmpl-ch (gs-template-channels vis-mod (template vis-mod)))
         (td-raw (gs-top-down vis-mod icons tmpl-ch now))
         (bu (gs-normalise (gs-bottom-up vis-mod icons now)))
         (td (gs-normalise (let ((c (make-hash-table :test 'equal)))
                             (maphash (lambda (k v) (setf (gethash k c) v)) td-raw)
                             c)))
         (hist (gs-normalise (gs-history-term vis-mod icons now)))
         (table (priority vis-mod)))
    (clrhash table)
    (dolist (i icons)
      (let* ((e (gsi-entry i))
             (p (+ (* (w-bu vis-mod) (gethash e bu 0.0))
                   (* (w-td vis-mod) (gethash e td 0.0))
                   (* (w-h vis-mod) (gethash e hist 0.0))
                   (* (w-v vis-mod) (gs-value-term vis-mod i))
                   (* (w-s vis-mod) (gsi-prior i))
                   (- (* (w-e vis-mod) (gs-ecc-deg vis-mod (gsi-x i) (gsi-y i))))
                   (gs-logistic-noise (gs-noise vis-mod)))))
        (setf (gsi-priority i) p
              (gsi-td i) (gethash e td-raw 0.0)
              (gethash e table) p)))
    td-raw))
