;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; gs-eye.lisp -- acuity, iconic memory, functional visual fields, saccades.
;;;
;;; Handoff sections 5.2 and 5.5.
;;;
;;; The saccade arithmetic reproduces EMMA (actr7.x/extras/emma/emma.lisp,
;;; version 8.2a3) rather than calling it, because EMMA's scheduling is
;;; entangled with MOVE-ATTENTION: EMMA-ATTENTION-HOOK builds the object,
;;; stores it as the shift target and calls SCHEDULE-ENCODING-COMPLETE, none of
;;; which applies to a saccade the module makes on its own initiative.  The
;;; numbers are read from EMMA's own parameters at run time so the two stay in
;;; step, and GS-SET-EYE calls SET-EYE-LOCATION so EMMA's marker and the
;;; Environment eye spot follow the module's gaze.
;;;
;;; One correction to the handoff's section 3 summary: EMMA counts two saccade
;;; directions as the same within pi/4, not within 90 degrees.  DIRECTION= in
;;; core-modules/motor.lisp line 894 is the authority and is what is used here.

(in-package :cl-user)

;; Forward references to functions defined lower down in this file.
(declaim (ftype function gs-schedule-fixation-timeout gs-quit-search
                gs-resume-pending))

(defparameter *gs-emma-defaults*
  '(:saccade-feat-time 0.050 :saccade-init-time 0.050 :saccade-base-time 0.020
    :eye-saccade-rate 0.002 :visual-encoding-factor 0.006
    :visual-encoding-exponent 0.4 :vis-obj-freq 0.1)
  "Fallbacks used when the EMMA extra is not loaded.")

(defun gs-emma-param (key)
  (let ((v (ignore-errors (get-parameter-value key))))
    (if (numberp v) v (getf *gs-emma-defaults* key))))

(defun gs-emma-on-p ()
  (and (get-module :emma) (eq t (ignore-errors (get-parameter-value :emma)))))

(defun gs-gaussian (x sd)
  "EMMA's ADD-GAUSSIAN-NOISE: a logistic sample scaled to the requested SD."
  (if (and (numberp sd) (plusp sd))
      (+ x (act-r-noise (/ (sqrt (* 3.0 sd sd)) pi)))
    x))

;;; ------------------------------------------------------------------
;;; Gaze
;;; ------------------------------------------------------------------

(defun gs-set-eye (vis-mod x y)
  "Move the module's gaze and tell EMMA, so one eye position is shared."
  (let ((z (aref (eye-xyz vis-mod) 2)))
    (setf (eye-xyz vis-mod) (vector x y z))
    (when (gs-emma-on-p)
      (ignore-errors (set-eye-location (list x y z))))))

(defun gs-centre-eye (vis-mod)
  "Adopt the current gaze at the start of a search, or centre it if it is unset.

EMMA's marker starts at the screen origin, which is the top-left corner, so a
first search would open with a 23 degree saccade out of the corner.  A gaze
still at the origin therefore means \"nobody has said where the eyes are\" and
the module centres on the visicon, as an experiment's fixation cross would.
An experiment that wants a different starting fixation calls SET-EYE-LOCATION
before the trial and that position is used instead."
  (let* ((icons (loop for e in (icon-order vis-mod)
                      for i = (gethash e (iconic vis-mod)) when i collect i))
         (loc (and (gs-emma-on-p) (ignore-errors (current-eye-location))))
         (x (if loc (first loc) (aref (eye-xyz vis-mod) 0)))
         (y (if loc (second loc) (aref (eye-xyz vis-mod) 1))))
    (if (and icons (zerop x) (zerop y))
        (gs-set-eye vis-mod
                    (/ (reduce #'+ icons :key #'gsi-x) (length icons))
                    (/ (reduce #'+ icons :key #'gsi-y) (length icons)))
      (setf (eye-xyz vis-mod) (vector x y (aref (eye-xyz vis-mod) 2))))))

;;; ------------------------------------------------------------------
;;; Iconic memory (section 5.2)
;;; ------------------------------------------------------------------

(defparameter *gs-feature-slots* '(color orient lum shape size value kind hue)
  "Slots read off a visicon feature into the module's own representation.")

(defun gs-angular-size (chunk vis-mod)
  "Mean of width and height in degrees; sqrt of SIZE when they are missing.

WIDTH and HEIGHT are pixels in ACT-R; SIZE is already in square degrees."
  (declare (ignorable vis-mod))
  (let ((w (chunk-slot-value-fct chunk 'width))
        (h (chunk-slot-value-fct chunk 'height))
        (s (chunk-slot-value-fct chunk 'size)))
    (cond ((and (numberp w) (numberp h))
           (/ (+ (pm-pixels-to-angle w) (pm-pixels-to-angle h)) 2.0))
          ((numberp s) (sqrt (max 0.0 s)))
          ((numberp w) (pm-pixels-to-angle w))
          ((numberp h) (pm-pixels-to-angle h))
          (t 1.0))))

(defun gs-refresh-iconic (vis-mod)
  "Rebuild iconic memory from the visicon, keeping the availability timestamps.

Keyed on CHUNK-VISICON-ENTRY, never on the chunk name: with
:delete-visicon-chunks at its default T the location chunks are deleted and
re-created behind the module's back."
  (let ((chunks (bt:with-recursive-lock-held ((visicon-lock vis-mod))
                  (copy-list (visicon-chunks vis-mod))))
        (seen (make-hash-table :test 'equal))
        (order nil)
        (sizes nil) (lums nil))
    ;; first pass: positions, raw values and the display ranges
    (let ((raws nil))
      (dolist (c chunks)
        (let* ((entry (or (chunk-visicon-entry c) c))
               (xyz (xyz-loc c vis-mod))
               (raw nil))
          (dolist (slot *gs-feature-slots*)
            (let ((v (chunk-slot-value-fct c slot)))
              (when v (setf raw (append raw (list slot v))))))
          (let ((sz (getf raw 'size)) (lm (getf raw 'lum)))
            (when (numberp sz) (push sz sizes))
            (when (numberp lm) (push lm lums)))
          (push (list entry c xyz raw) raws)
          (push entry order)
          (setf (gethash entry seen) t)))
      (setf (display-ranges vis-mod)
            (list 'size (when sizes (cons (reduce #'min sizes) (reduce #'max sizes)))
                  'lum (when lums (cons (reduce #'min lums) (reduce #'max lums)))))
      ;; second pass: channels, now that the ranges are known
      (dolist (r (nreverse raws))
        (destructuring-bind (entry c xyz raw) r
          (let ((icon (or (gethash entry (iconic vis-mod))
                          (setf (gethash entry (iconic vis-mod))
                                (make-gs-icon :entry entry
                                              :feats (make-hash-table :test 'eq))))))
            (setf (gsi-chunk icon) c
                  (gsi-x icon) (or (aref xyz 0) 0.0)
                  (gsi-y icon) (or (aref xyz 1) 0.0)
                  (gsi-size-deg icon) (gs-angular-size c vis-mod)
                  (gsi-raw icon) raw
                  (gsi-prior icon) (let ((p (chunk-slot-value-fct c 'prior)))
                                     (if (numberp p) p 0.0))
                  (gsi-salience icon) (let ((s (chunk-slot-value-fct c 'salience)))
                                        (and (numberp s) s)))
            (let (ch)
              (dolist (slot '(color orient size lum shape value kind))
                (let ((v (getf raw slot)))
                  (when v
                    (setf ch (append ch (list slot
                                              (gs-channels-for vis-mod slot v
                                                               (getf raw 'hue))))))))
              (setf (gsi-channels icon) ch))))))
    ;; drop items that left the display
    (let (dead)
      (maphash (lambda (k v) (declare (ignore v))
                 (unless (gethash k seen) (push k dead)))
               (iconic vis-mod))
      (dolist (k dead) (remhash k (iconic vis-mod))))
    (setf (icon-order vis-mod) (nreverse order))))

(defun gs-draw-availability (vis-mod)
  "One EPIC availability draw per fixation per item per feature.

Available with probability P(s > N(theta_f * e, sigma)), which is
Phi((s - theta_f e) / sigma).  A feature with no theta -- anything outside
:gs-acuity-theta -- is treated as always available."
  (let ((now (mp-time-ms))
        (theta (acuity-theta vis-mod))
        (sigma (acuity-sigma vis-mod)))
    (dolist (e (icon-order vis-mod))
      (let ((icon (gethash e (iconic vis-mod))))
        (when icon
          (let ((ecc (gs-ecc-deg vis-mod (gsi-x icon) (gsi-y icon)))
                (s (gsi-size-deg icon)))
            (loop for (slot nil) on (gsi-raw icon) by #'cddr
                  do (let ((th (or (getf theta slot)
                                   ;; hue is colour measured continuously, so it
                                   ;; inherits colour's acuity rather than
                                   ;; escaping the rule for want of an entry
                                   (and (eq slot 'hue) (getf theta 'color)))))
                       (if (null th)
                           (setf (gethash slot (gsi-feats icon)) now)
                         (let ((p (gs-normal-cdf (/ (- s (* th ecc)) sigma))))
                           (when (< (act-r-random 1.0) p)
                             (setf (gethash slot (gsi-feats icon)) now))))))))))))

;;; ------------------------------------------------------------------
;;; Saccades (section 5.5)
;;; ------------------------------------------------------------------

(defun gs-saccade-time (vis-mod amplitude direction)
  "EMMA preparation plus execution, in milliseconds.

Preparation costs :saccade-feat-time per changed feature -- three for the
first saccade of a style, otherwise one each for a distance that differs by
more than 2 degrees and a direction that differs by more than pi/4.
Execution is :saccade-init-time + :saccade-base-time + rate * amplitude."
  (let* ((last (last-saccade vis-mod))
         (nfeat (if (null last)
                    3
                  (+ (if (distance= amplitude (car last)) 0 1)
                     (if (direction= direction (cdr last)) 0 1))))
         (prep (* (gs-emma-param :saccade-feat-time) nfeat))
         (exe (+ (gs-emma-param :saccade-init-time)
                 (gs-emma-param :saccade-base-time)
                 (* (gs-emma-param :eye-saccade-rate) amplitude))))
    (setf (last-saccade vis-mod) (cons amplitude direction))
    (let ((prep-ms (round (seconds->ms (randomize-time prep))))
          (exe-ms (round (seconds->ms (randomize-time exe)))))
      (values (+ prep-ms exe-ms) prep-ms exe-ms))))

(defun gs-raw-encoding-time (ecc)
  "EMMA's K (-ln f) exp(k eps), in seconds."
  (* (gs-emma-param :visual-encoding-factor)
     (- (log (max 1e-6 (gs-emma-param :vis-obj-freq))))
     (exp (* (gs-emma-param :visual-encoding-exponent) ecc))))

(defun gs-encoding-time (vis-mod ecc)
  "Encoding cost of a hit in seconds, with EMMA's remaining-proportion rule.

When the peripheral estimate exceeds the time it would take to saccade there,
EMMA moves the eye and restarts the encoding at the new eccentricity keeping
only the proportion that was left (COMPLETE-EYE-MOVE in emma.lisp).  Without
the second half a covert hit at 12 degrees would cost 1.7 s, which is EMMA's
peripheral estimate rather than its behaviour."
  (if (not (gs-emma-on-p))
      (ms->seconds (move-attn-latency vis-mod))
    (let ((enc (gs-raw-encoding-time ecc))
          (sacc (+ (gs-emma-param :saccade-init-time)
                   (gs-emma-param :saccade-base-time)
                   (* (gs-emma-param :eye-saccade-rate) ecc))))
      (if (<= enc sacc)
          enc
        (+ sacc (* (max 0.0 (- 1.0 (/ sacc enc))) (gs-raw-encoding-time 0.5)))))))

(defun gs-saccade-candidates (vis-mod &optional radius)
  "Items that are neither in the IOR ring nor in the diffuser."
  (let (out)
    (dolist (e (icon-order vis-mod))
      (let ((icon (gethash e (iconic vis-mod))))
        (when (and icon
                   (not (member e (rejected vis-mod) :test 'equal))
                   (not (find e (diffuser vis-mod) :key #'gsd-entry :test 'equal))
                   (or (null radius)
                       (<= (gs-ecc-deg vis-mod (gsi-x icon) (gsi-y icon)) radius)))
          (push icon out))))
    (nreverse out)))

(defun gs-best-by-priority (icons)
  (when icons
    (let ((best (first icons)))
      (dolist (i (rest icons) best)
        (when (> (gsi-priority i) (gsi-priority best)) (setf best i))))))

(defun gs-best-guidance (icons)
  (car (stable-sort (copy-list icons) #'> :key #'gsi-guidance)))

(defun gs-best-saccade (vis-mod icons)
  (if (revised-saccades vis-mod)
      (car (stable-sort (copy-list icons) #'>
             :key (lambda (i) (- (gsi-guidance i)
                                (* (saccade-proximity vis-mod)
                                   (gs-ecc-deg vis-mod (gsi-x i) (gsi-y i)))))))
    (gs-best-by-priority icons)))

(defun gs-request-saccade (vis-mod &optional to)
  "Schedule the next saccade unless one is already in flight.

Target order (section 5.5): the oldest item waiting on foveation, then TO if
the caller named one, then the highest-priority candidate inside
:gs-explore-fvf, then the highest-priority candidate anywhere.  A dead end
quits the search, but only when nothing is still being identified: items in
the diffuser are not nothing."
  (unless (saccade-flight vis-mod)
    (let* ((pending (find-if #'gsd-pending (reverse (diffuser vis-mod))))
           (target (cond (pending (gethash (gsd-entry pending) (iconic vis-mod)))
                         (to to)
                         (t (or (gs-best-saccade vis-mod
                                 (gs-saccade-candidates vis-mod (explore-fvf vis-mod)))
                                (gs-best-saccade vis-mod (gs-saccade-candidates vis-mod)))))))
      (cond ((null target)
             (when (null (diffuser vis-mod))
               (gs-quit-search vis-mod 'no-candidate)))
            (t
             (let* ((eye (eye-xyz vis-mod))
                    (dx (- (gsi-x target) (aref eye 0)))
                    (dy (- (gsi-y target) (aref eye 1)))
                    (px (sqrt (+ (* dx dx) (* dy dy))))
                    (amp (pm-pixels-to-angle px))
                    (dir (atan (- dy) dx)))
               (multiple-value-bind (ms prep exe) (gs-saccade-time vis-mod amp dir)
               (declare (ignore ms))
               (setf (saccade-flight vis-mod) t)
               (schedule-event-now nil :module :vision :output 'medium :maintenance t
                                       :details (format nil "GS-SACCADE ~,0f ~,0f -> ~,0f ~,0f amp ~,1f"
                                                        (aref eye 0) (aref eye 1)
                                                        (gsi-x target) (gsi-y target) amp))
               (setf (sacc-event vis-mod)
                     (schedule-event-relative prep 'gs-saccade-execute :time-in-ms t
                                              :module :vision :destination :vision
                                              :output nil :maintenance t
                                              :params (list (gsi-entry target) exe))))))))))

(defun gs-saccade-execute (vis-mod entry duration)
  (when (search-active vis-mod)
    (gs-close-fixation vis-mod)
    (setf (eye-moving vis-mod) t)
    (gs-record-event vis-mod "saccade-execute" entry)
    (setf (sacc-event vis-mod)
          (schedule-event-relative duration 'gs-saccade-land :time-in-ms t
                                   :module :vision :destination :vision
                                   :output nil :maintenance t :params (list entry)))))

(defun gs-saccade-land (vis-mod entry)
  "The eye arrives: redraw acuity, recompute priority, resume the loop."
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (unless (search-active vis-mod) (return-from gs-saccade-land nil))
    (setf (saccade-flight vis-mod) nil
          (eye-moving vis-mod) nil
          (sacc-event vis-mod) nil)
    (let ((icon (gethash entry (iconic vis-mod)))
          (now (mp-time-ms)))
      (when (and icon (search-active vis-mod))
        (let* ((eye (eye-xyz vis-mod))
               (px (sqrt (+ (expt (- (gsi-x icon) (aref eye 0)) 2)
                            (expt (- (gsi-y icon) (aref eye 1)) 2))))
               (sd (* 0.1 px)))                 ; EMMA's landing noise
          (gs-set-eye vis-mod
                      (gs-gaussian (gsi-x icon) sd)
                      (gs-gaussian (gsi-y icon) sd))))
      (incf (n-fixations vis-mod))
      (setf (fix-start vis-mod) now
            (last-landed vis-mod) entry)
      (gs-record-event vis-mod "landing" entry)
      (schedule-event-now nil :module :vision :output 'medium :maintenance t
                              :details (format nil "GS-FIXATE ~,0f ~,0f"
                                               (aref (eye-xyz vis-mod) 0)
                                               (aref (eye-xyz vis-mod) 1)))
      (gs-draw-availability vis-mod)
      (gs-compute-priority vis-mod)
      (gs-schedule-fixation-timeout vis-mod)
      (gs-resume-pending vis-mod entry))))

(defun gs-schedule-fixation-timeout (vis-mod)
  (awhen (fix-event vis-mod) (delete-event it))
  (setf (fix-event vis-mod)
        (schedule-event-relative (max-fixation vis-mod) 'gs-fixation-timeout
                                 :time-in-ms t :module :vision :destination :vision
                                 :output nil :maintenance t)))

(defun gs-fixation-timeout (vis-mod)
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (setf (fix-event vis-mod) nil)
    (when (search-active vis-mod)
      (gs-request-saccade vis-mod)
      (unless (fix-event vis-mod) (gs-schedule-fixation-timeout vis-mod)))))
