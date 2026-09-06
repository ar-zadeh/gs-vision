;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; gs-diffuser.lisp -- covert selection, identification and quitting.
;;;
;;; Handoff sections 5.4 and 5.6.  Everything here runs on module events, not
;;; on productions: one selection every :gs-select-interval while a search is
;;; active and the diffuser has room, one Wald-distributed identification per
;;; selected item, and two quit rules racing the search.
;;;
;;; Three readings of the handoff are recorded in the module README and in
;;; reference/gs_hybrid.py, which makes the same three choices:
;;;
;;;   * the adaptive threshold is kept as a persistent unitless scale and
;;;     multiplied by the effective set size at test time, as the GS6 MATLAB
;;;     does, rather than stored in rejections and shifted by a step that
;;;     depends on a set size that may since have changed;
;;;   * the Competitive Guided Search quit denominator runs over every item
;;;     that has not been rejected, items being identified included, because
;;;     CGS zeroes a weight on rejection.  Restricting it to items outside the
;;;     diffuser and inside the attentional field empties it mid-search and
;;;     makes p(quit) exactly 1;
;;;   * selection consults the priority map globally.  When the winner is
;;;     outside the attentional field the module looks at it instead of
;;;     covertly grabbing a loser, which is how peripheral guidance reaches a
;;;     target that section 5.6's own worked example requires to be found
;;;     before anything is rejected.

(in-package :cl-user)

;; Forward references: to gs-eye.lisp, which is loaded after this file, and
;; to functions defined lower down in this one.
(declaim (ftype function gs-request-saccade gs-schedule-fixation-timeout
                gs-draw-availability gs-refresh-iconic gs-centre-eye
                gs-encoding-time gs-set-eye gs-best-by-priority
                gs-schedule-select gs-reject gs-check-quit))

(defparameter *gs-post-saccade-delay* 50
  "Milliseconds after a landing before a pending item is re-examined.")

;;; ------------------------------------------------------------------
;;; Bookkeeping
;;; ------------------------------------------------------------------

(defun gs-trace (fmt &rest args)
  (schedule-event-now nil :module :vision :output 'medium :maintenance t
                          :details (apply #'format nil fmt args)))

(defun gs-trace-wake (fmt &rest args)
  "A trace event that is not maintenance, so conflict resolution runs after it.

The end of a search has to wake the procedural module: a quit only sets the
buffer failure flag, and nothing else would prompt the productions to look."
  (schedule-event-now nil :module :vision :output 'medium
                          :details (apply #'format nil fmt args)))

(defun gs-cancel-events (vis-mod)
  (dolist (acc (list #'select-event #'fix-event #'sacc-event #'delivery-event))
    (awhen (funcall acc vis-mod) (delete-event it)))
  (setf (select-event vis-mod) nil
        (fix-event vis-mod) nil
        (sacc-event vis-mod) nil
        (delivery-event vis-mod) nil
        (eye-moving vis-mod) nil
        (saccade-flight vis-mod) nil)
  (dolist (d (diffuser vis-mod))
    (awhen (gsd-event d) (delete-event it)))
  (setf (diffuser vis-mod) nil))

(defun gs-clear-search (vis-mod)
  "Reset the per-trial state.  Adaptive threshold, priming and the feedback
window deliberately survive: one model run is one simulated subject.

The attended-location marker is dropped as well.  A hit leaves the *visicon*
chunk as the current marker, and :delete-visicon-chunks deletes and uninterns
that chunk as soon as the display changes; ACT-R's own buffer stuffing then
reads CHUNK-VISICON-ENTRY off a name that no longer exists and warns on every
later trial.  The stock module never hits this because MOVE-ATTENTION marks
the visual-location buffer's copy, which outlives the visicon.  Clearing the
marker when a search starts or when the experiment resets the trial is both
the fix and the right semantics: a new display has no attended location."
  (gs-close-fixation vis-mod)
  (gs-cancel-events vis-mod)
  (bt:with-recursive-lock-held ((marker-lock vis-mod))
    (set-current-marker vis-mod nil)
    (setf (currently-attended vis-mod) nil))
  (setf (rejected vis-mod) nil
        (quit-weight vis-mod) 0.0
        (rejections vis-mod) 0
        (search-active vis-mod) nil
        (quit-reason vis-mod) nil
        (last-saccade vis-mod) nil
        (last-landed vis-mod) nil))

(defun gs-record-event (vis-mod kind &optional item)
  (push (list (mp-time-ms) kind (and item (princ-to-string item))) (event-log vis-mod)))

(defun gs-close-fixation (vis-mod)
  "Close the stationary interval at its occupied position, once."
  (when (and (fix-start vis-mod) (search-active vis-mod))
    (when (log-fixations vis-mod)
      (push (list (fix-start vis-mod) (aref (eye-xyz vis-mod) 0)
                  (aref (eye-xyz vis-mod) 1)
                  (max 0 (- (mp-time-ms) (fix-start vis-mod))))
            (fixation-log vis-mod)))
    (setf (fix-start vis-mod) nil)))

(defun gs-eligible (vis-mod &optional radius)
  "Items in iconic memory that may be selected: not rejected, not in the
diffuser, and within RADIUS degrees of the gaze when one is given."
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

(defun gs-centred-weights (vis-mod icons)
  "exp(beta (P_i - mean P)).  Centring is what keeps a typical distractor's
weight near 1, which is the scale the quit weight assumes; without it the
quit weight is negligible and the search never stops."
  (when icons
    (let* ((beta (choice-beta vis-mod))
           (mean (/ (reduce #'+ icons :key #'gsi-priority) (length icons))))
      (mapcar (lambda (i) (exp (min 50.0 (* beta (- (gsi-priority i) mean))))) icons))))

;;; ------------------------------------------------------------------
;;; Starting and ending a search
;;; ------------------------------------------------------------------

(defun gs-start-search (vis-mod template guide stop requested)
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (gs-clear-search vis-mod)
    (setf (template vis-mod) template
          (guide-set vis-mod) guide
          (search-stop vis-mod) (or stop 'both)
          (search-requested vis-mod) requested
          (search-active vis-mod) t
          (search-start vis-mod) (mp-time-ms)
          (fix-start vis-mod) (mp-time-ms)
          (search-result vis-mod) 'none)
    (setf (fixation-log vis-mod) nil (n-fixations vis-mod) 1
          (event-log vis-mod) nil)
    (gs-record-event vis-mod "request")
    (setf (attend-failure vis-mod) nil)
    (change-state vis-mod :exec 'BUSY :proc 'BUSY)
    (gs-refresh-iconic vis-mod)
    (gs-centre-eye vis-mod)
    (gs-draw-availability vis-mod)
    (let ((td (gs-compute-priority vis-mod))
          (n 0))
      (maphash (lambda (k v) (declare (ignore k)) (when (>= v 0.5) (incf n))) td)
      (setf (search-n-eff vis-mod) (max 1.0 (float n))
            (search-qt vis-mod) (* (or (quit-threshold vis-mod) (qt-init vis-mod))
                                   (max 1.0 (float n)))))
    (gs-trace "GS-SEARCH start template ~a n-eff ~,0f qt ~,2f"
              (template vis-mod) (search-n-eff vis-mod) (search-qt vis-mod))
    (gs-schedule-fixation-timeout vis-mod)
    (gs-schedule-select vis-mod (onset-latency vis-mod))))

(defun gs-schedule-select (vis-mod &optional (extra-ms 0))
  "Schedule the next covert selection; EXTRA-MS delays the first one (:gs-onset-latency)."
  (setf (select-event vis-mod)
        (schedule-event-relative (+ extra-ms (select-interval vis-mod)) 'gs-select
                                 :time-in-ms t :module :vision :destination :vision
                                 :output nil :maintenance t)))

(defun gs-end-search (vis-mod)
  (gs-close-fixation vis-mod)
  (gs-cancel-events vis-mod)
  (setf (search-elapsed vis-mod) (- (mp-time-ms) (search-start vis-mod))
        (search-active vis-mod) nil))

(defun gs-quit-search (vis-mod reason)
  "End the search with nothing found.

A buffer cannot hold a chunk and a failure flag at once (handoff section 3),
so a failed search leaves the visual buffer empty with state error, exactly
like a retrieval failure."
  (when (search-active vis-mod)
    (gs-record-event vis-mod "failure" reason)
    (gs-end-search vis-mod)
    (setf (search-result vis-mod) 'failed
          (quit-reason vis-mod) reason)
    (bt:with-recursive-lock-held ((marker-lock vis-mod))
      (setf (attend-failure vis-mod) t))
    (change-state vis-mod :exec 'free :proc 'free)
    (set-buffer-failure 'visual :ignore-if-full t
                                :requested (search-requested vis-mod))
    (gs-trace-wake "GS-QUIT ~a after ~d rejections, ~d fixations, ~d ms"
              reason (rejections vis-mod) (n-fixations vis-mod)
              (- (mp-time-ms) (search-start vis-mod)))))

(defun gs-finish-hit (vis-mod icon)
  ;; Wald completes recognition once all template features are available.
  ;; Buffer construction is ACT-R's existing encoding-complete operation.
  ;; A peripheral recognition does not teleport gaze to the identified item.
  (gs-cancel-events vis-mod)
  (setf (search-result vis-mod) 'found
        (quit-reason vis-mod) 'hit
        (last-found vis-mod) (gsi-entry icon))
  (let* ((ecc (gs-ecc-deg vis-mod (gsi-x icon) (gsi-y icon)))
         (secs (if (recognition-extra vis-mod) (gs-encoding-time vis-mod ecc) 0))
         (chunk (gsi-chunk icon)))
    (gs-record-event vis-mod "identified" chunk)
    (gs-trace "GS-DECIDE ~a hit" chunk)
    (if (and chunk (chunk-p-fct chunk))
        (setf (delivery-event vis-mod)
        (schedule-event-relative (seconds->ms secs) 'gs-deliver-hit
                                 :time-in-ms t :module :vision :destination :vision
                                 :output 'medium
                                 :params (list chunk)
                                 :details (concatenate 'string "Encoding-complete "
                                                       (symbol-name chunk))))
      (gs-quit-search vis-mod 'target-vanished))))

(defun gs-deliver-hit (vis-mod chunk)
  (setf (delivery-event vis-mod) nil)
  (when (search-active vis-mod)
    (if (and (chunk-p-fct chunk)
             (find chunk (visicon-chunks vis-mod) :test 'eq))
        (progn
          (encoding-complete vis-mod chunk (xyz-loc chunk vis-mod) nil
                             :requested (search-requested vis-mod))
          (gs-record-event vis-mod "buffer" chunk))
      (gs-quit-search vis-mod 'target-vanished))))

;;; ------------------------------------------------------------------
;;; Selection (section 5.4 step 1)
;;; ------------------------------------------------------------------

(defun gs-luce-pick (vis-mod icons)
  (let* ((w (gs-centred-weights vis-mod icons))
         (total (reduce #'+ w))
         (r (act-r-random (float total))))
    (loop for i in icons for wi in w
          do (decf r wi)
             (when (<= r 0.0) (return i))
          finally (return (car (last icons))))))

(defun gs-select (vis-mod)
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (setf (select-event vis-mod) nil)
    (when (search-active vis-mod)
      (when (and (not (eye-moving vis-mod))
                 (not (and (member (search-stop vis-mod) '(adaptive both))
                           (>= (rejections vis-mod) (search-qt vis-mod))
                           (diffuser vis-mod)))
                 (< (length (diffuser vis-mod)) (diffuser-capacity vis-mod)))
        (let* ((everywhere (gs-eligible vis-mod))
               (winner (if (revised-saccades vis-mod)
                           (gs-best-guidance everywhere) (gs-best-by-priority everywhere)))
               (near (gs-eligible vis-mod (attn-fvf vis-mod))))
          ;; :gs-saccade-trigger -- everything close has been dealt with:
          ;; start moving the eye (distance-penalised destination) while
          ;; covert selection continues during the preparation.
          (when (and (plusp (saccade-trigger vis-mod)) near (not (saccade-flight vis-mod))
                     (> (loop for i in near minimize (gs-ecc-deg vis-mod (gsi-x i) (gsi-y i)))
                        (saccade-trigger vis-mod)))
            (gs-request-saccade vis-mod))
          (when (and winner (not (member winner near))
                     (or (not (revised-saccades vis-mod)) (null near)
                         (> (gsi-guidance winner)
                            (+ (gsi-guidance (gs-best-guidance near)) (saccade-margin vis-mod)))))
            ;; With :gs-explore-proximity and an empty attentional field the
            ;; destination is gs-best-saccade's guidance-minus-distance choice
            ;; rather than the guidance winner with icon-order tie-breaking.
            (gs-request-saccade vis-mod (if (and (explore-proximity vis-mod) (null near))
                                            nil winner))
            ;; Weak distractors are not useful preparation work when a known
            ;; stronger candidate is being approached (effective N can be 1).
            (when (revised-saccades vis-mod) (setf near nil)))
          (cond ((and near (or (revised-saccades vis-mod) (member winner near)))
                 (let* ((pick (gs-luce-pick vis-mod near))
                        (mean (/ (id-threshold vis-mod) (id-drift vis-mod)))
                        (shape (/ (expt (id-threshold vis-mod) 2)
                                  (expt (id-sigma vis-mod) 2)))
                        (ms (max 0 (round (seconds->ms (gs-wald mean shape))))))
                   (gs-trace "GS-SELECT ~a priority ~,3f" (gsi-chunk pick)
                             (gsi-priority pick))
                   (gs-record-event vis-mod "select" (gsi-chunk pick))
                   (push (make-gs-diff
                          :entry (gsi-entry pick)
                          :event (schedule-event-relative
                                  ms 'gs-item-decision :time-in-ms t
                                  :module :vision :destination :vision
                                  :output nil :maintenance t
                                  :params (list (gsi-entry pick))))
                         (diffuser vis-mod))))
                ((null near) (gs-request-saccade vis-mod)))))
      (when (search-active vis-mod) (gs-schedule-select vis-mod)))))

;;; ------------------------------------------------------------------
;;; Identification (section 5.4 steps 2 and 3)
;;; ------------------------------------------------------------------

(defun gs-template-slots (vis-mod)
  (loop for (slot nil) on (template vis-mod) by #'cddr collect slot))

(defun gs-missing-features (vis-mod icon now)
  (remove-if (lambda (slot) (gs-available-p vis-mod icon slot now))
             (gs-template-slots vis-mod)))

(defun gs-item-matches-p (vis-mod icon)
  (let ((tmpl (gs-template-channels vis-mod (template vis-mod))))
    (loop for (slot nil) on (template vis-mod) by #'cddr
          always (> (gs-channel-overlap (getf (gsi-channels icon) slot)
                                        (getf tmpl slot))
                    0.5))))

(defun gs-item-decision (vis-mod entry)
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (let ((d (find entry (diffuser vis-mod) :key #'gsd-entry :test 'equal))
          (icon (gethash entry (iconic vis-mod)))
          (now (mp-time-ms)))
      (when (and d icon (search-active vis-mod))
        (gs-record-event vis-mod "decision" (gsi-chunk icon))
        (setf (gsd-event d) nil)
        (let ((missing (gs-missing-features vis-mod icon now)))
          (cond
            ((and missing (or (gsd-foveated d)
                              (equal entry (last-landed vis-mod))))
             ;; still invisible at the fovea: give up on it
             (gs-trace "GS-DECIDE ~a reject (unresolved ~a)" (gsi-chunk icon) missing)
             (gs-reject vis-mod entry))
            (missing
             (setf (gsd-pending d) t)
             (gs-trace "GS-DECIDE ~a pending ~a" (gsi-chunk icon) missing)
             (gs-request-saccade vis-mod))
            (t
             ;; :gs-id-error is the second decision boundary: with that
             ;; probability the decision flips, rejecting a target (a miss)
             ;; or accepting a distractor (a false alarm).
             (let ((match (gs-item-matches-p vis-mod icon)))
               (when (and (plusp (id-error vis-mod))
                          (< (act-r-random 1.0) (id-error vis-mod)))
                 (setf match (not match))
                 (gs-trace "GS-DECIDE ~a decision error" (gsi-chunk icon)))
               (if match
                   (gs-finish-hit vis-mod icon)
                 (progn
                   (gs-trace "GS-DECIDE ~a reject" (gsi-chunk icon))
                   (gs-reject vis-mod entry)))))))))))

(defun gs-resume-pending (vis-mod landed-entry)
  "After a landing, re-examine everything that was waiting on foveation."
  (dolist (d (diffuser vis-mod))
    (when (gsd-pending d)
      (setf (gsd-pending d) nil)
      (when (equal (gsd-entry d) landed-entry) (setf (gsd-foveated d) t))
      (setf (gsd-event d)
            (schedule-event-relative *gs-post-saccade-delay* 'gs-item-decision
                                     :time-in-ms t :module :vision
                                     :destination :vision :output nil
                                     :maintenance t
                                     :params (list (gsd-entry d)))))))

;;; ------------------------------------------------------------------
;;; Quitting (section 5.6)
;;; ------------------------------------------------------------------

(defun gs-reject (vis-mod entry)
  (setf (diffuser vis-mod)
        (remove entry (diffuser vis-mod) :key #'gsd-entry :test 'equal))
  (push entry (rejected vis-mod))
  (when (> (length (rejected vis-mod)) (gs-memory vis-mod))
    (setf (rejected vis-mod) (subseq (rejected vis-mod) 0 (gs-memory vis-mod))))
  (incf (rejections vis-mod))
  ;; With :gs-adaptive-quit-delta the increment is divided by the persistent
  ;; adaptive scale, so a miss (which raises the scale) also makes competitive
  ;; quitting rarer; otherwise the two quit rules are independent and the
  ;; feedback controller cannot reach its error goal once competitive quits
  ;; dominate.
  (incf (quit-weight vis-mod)
        (if (adaptive-quit-delta vis-mod)
            (/ (quit-delta vis-mod)
               (max 0.05 (or (quit-threshold vis-mod) (qt-init vis-mod))))
          (quit-delta vis-mod)))
  (gs-check-quit vis-mod))

(defun gs-check-quit (vis-mod)
  (let ((stop (search-stop vis-mod)))
    (when (member stop '(cgs both))
      (let* ((live (loop for e in (icon-order vis-mod)
                         for i = (gethash e (iconic vis-mod))
                         when (and i (not (member e (rejected vis-mod) :test 'equal)))
                           collect i))
             (w (if (quit-noise-free vis-mod)
                    (gs-quit-weights vis-mod live) (gs-centred-weights vis-mod live)))
             (denom (+ (if w (reduce #'+ w) 0.0) (quit-weight vis-mod))))
        (when (and (plusp denom)
                   (< (act-r-random 1.0) (/ (quit-weight vis-mod) denom)))
          (gs-quit-search vis-mod 'cgs)
          (return-from gs-check-quit))))
    (when (and (member stop '(adaptive both))
               (null (diffuser vis-mod))
               (>= (rejections vis-mod) (search-qt vis-mod)))
      (gs-quit-search vis-mod 'threshold))))

(defun gs-quit-weights (vis-mod icons)
  "Unresolved items retain weights; noise and eccentricity cannot dominate quitting."
  (when icons
    (let ((mean (/ (reduce #'+ icons :key #'gsi-guidance) (length icons)))
          (beta (min 4.0 (choice-beta vis-mod))))
      (mapcar (lambda (i) (exp (min 50.0 (* beta (- (gsi-guidance i) mean))))) icons))))

;;; ------------------------------------------------------------------
;;; Feedback (section 5.6)
;;; ------------------------------------------------------------------

(defun gs-prevalence (vis-mod)
  "Proportion of target-present feedbacks in the window; 0.5 until 10 exist."
  (let ((log (feedback-log vis-mod)))
    (if (< (length log) 10)
        0.5
      (max 0.02 (min 0.98
                     (/ (float (count-if (lambda (o) (member o '(hit miss))) log))
                        (length log)))))))

(defun gs-feedback (vis-mod outcome)
  "Apply a gs-feedback request: adaptive threshold and priming traces."
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (let ((prev (gs-prevalence vis-mod))
          (qt (or (quit-threshold vis-mod) (qt-init vis-mod))))
      (case outcome
        (tn (setf (quit-threshold vis-mod) (max 0.0 (- qt (qt-step vis-mod)))))
        (miss (setf (quit-threshold vis-mod)
                    (+ qt (/ (qt-step vis-mod)
                             (max 1e-6 (* (error-goal vis-mod) prev 2.0))))))
        ((hit fa) nil))
      ;; hits refresh the priming traces of the found item's guiding channels
      (when (and (eq outcome 'hit) (last-found vis-mod))
        (let ((icon (gethash (last-found vis-mod) (iconic vis-mod)))
              (now-s (ms->seconds (mp-time-ms))))
          (when icon
            (dolist (k (guiding-features vis-mod))
              (dolist (c (getf (gsi-channels icon) k))
                (gs-bump-trace vis-mod (cons k (car c)) now-s))))))
      (push outcome (feedback-log vis-mod))
      (when (> (length (feedback-log vis-mod)) (feedback-window vis-mod))
        (setf (feedback-log vis-mod)
              (subseq (feedback-log vis-mod) 0 (feedback-window vis-mod))))
      (gs-trace "GS-FEEDBACK ~a qt ~,3f prevalence ~,2f"
                outcome (quit-threshold vis-mod) prev))))
