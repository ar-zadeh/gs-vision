;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; gs-diffuser.lisp (gs6-vision) -- covert selection, Wolfe's asynchronous
;;; diffuser, the quit-signal diffuser and feedback.
;;;
;;; This is where gs6-vision differs most from gs-vision.  gs-vision used
;;; Competitive Guided Search (Moran et al. 2013) for identification and
;;; quitting: one Wald-distributed completion time per item with a fixed
;;; outcome, a rejection counter against an adaptive threshold, and a
;;; per-rejection quit lottery.  Here the engine is the one Wolfe (2021)
;;; posted as GS6publicAsPostedJan2021.m:
;;;
;;;   * every :gs-diff-step (10 ms) each in-flight item moves by
;;;       sign * (N(0,1) * :gs-diff-inc * :gs-diff-noise + drift)
;;;     between :gs-dist-thresh (-1, reject) and :gs-targ-thresh (+1, accept),
;;;     where sign is +1 for an item that matches the full template and -1
;;;     otherwise.  Outcomes are emergent: a distractor that reaches +1 is a
;;;     false alarm, a target that reaches -1 is a miss.  :gs-similarity-drift
;;;     slows a distractor in proportion to its similarity to the template,
;;;     which the paper describes and the posted code fixes (default 0).
;;;   * an item starts at prevalence/2 - 0.25 plus an adaptive offset that
;;;     rises by :gs-start-inc after a hit and falls by :gs-start-dec after a
;;;     false alarm (:gs-start-prevalence nil drops the prevalence term).
;;;   * after the first rejection a quit signal grows every step by
;;;       N(0,1) * :gs-quit-inc * :gs-quit-noise + :gs-quit-inc
;;;     and the search quits when it exceeds
;;;       quit-threshold * N_eff / :gs-quit-ss-ref.
;;;     The MATLAB divides by max(SS) * 0.5 = 10 and scales by the raw set
;;;     size; this module scales by the effective set size it already
;;;     computes (items with TD >= 0.5, at least 1), because it has guidance
;;;     and the MATLAB has none.
;;;   * feedback follows the MATLAB exactly: a true negative lowers the
;;;     threshold by :gs-qt-step * prevalence, a miss raises it by
;;;     :gs-qt-step / (:gs-error-goal * prevalence * 2) * (1 - prevalence).
;;;   * memory is the diffuser (:gs-memory 0): a rejected item is selectable
;;;     again at once.  The IOR ring is still there for the few-item memory
;;;     the GS4/GS6 text allows.
;;;
;;; The competitive quit unit survives as an ablation (`stop cgs' or `both').
;;; There is no draining: the trial ends when the quit signal fires.
;;;
;;; One deliberate departure from the MATLAB: when an item crosses the target
;;; bound and the quit signal crosses its threshold on the same step, the hit
;;; wins.  In the MATLAB the quit test overwrites the yes response; that is an
;;; artefact of two independent IF blocks, not a claim of the theory.
;;;
;;; A selected item whose template features are not available is handled at
;;; selection time: it waits in the diffuser for a saccade to itself and
;;; starts accumulating once its features can be seen; if they still cannot
;;; be seen at the fovea it is rejected.

(in-package :cl-user)

;; Forward references: to gs-eye.lisp, which is loaded after this file, and
;; to functions defined lower down in this one.
(declaim (ftype function gs-request-saccade gs-schedule-fixation-timeout
                gs-draw-availability gs-refresh-iconic gs-centre-eye
                gs-encoding-time gs-set-eye gs-best-by-priority gs-best-guidance
                gs-schedule-select gs-schedule-tick gs-reject gs-check-quit
                gs-enter-diffuser gs-check-item gs-diffuser-tick
                gs-close-fixation gs-prevalence gs-quit-weights))

(defparameter *gs-post-saccade-delay* 50
  "Milliseconds after a landing before a pending item is re-examined.")

(defparameter *gs-tick-priority* -10
  "Scheduler priority of the diffuser tick: below every other module event, so
that a selection, a landing or a re-examination scheduled for the same
millisecond runs first and the tick sees its result, as the MATLAB's selection
step precedes its diffusion step.")

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
  (dolist (acc (list #'select-event #'fix-event #'sacc-event #'delivery-event #'tick-event))
    (awhen (funcall acc vis-mod) (delete-event it)))
  (setf (select-event vis-mod) nil
        (fix-event vis-mod) nil
        (sacc-event vis-mod) nil
        (delivery-event vis-mod) nil
        (tick-event vis-mod) nil
        (eye-moving vis-mod) nil
        (saccade-flight vis-mod) nil)
  (dolist (d (diffuser vis-mod))
    (awhen (gsd-event d) (delete-event it)))
  (setf (diffuser vis-mod) nil))

(defun gs-clear-search (vis-mod)
  "Reset the per-trial state.  The adaptive threshold, the start-point offset,
priming and the feedback window deliberately survive: one model run is one
simulated subject.

The attended-location marker is dropped as well; see gs-vision for why."
  (gs-close-fixation vis-mod)
  (gs-cancel-events vis-mod)
  (bt:with-recursive-lock-held ((marker-lock vis-mod))
    (set-current-marker vis-mod nil)
    (setf (currently-attended vis-mod) nil))
  (setf (rejected vis-mod) nil
        (quit-weight vis-mod) 0.0
        (quit-sig vis-mod) 0.0
        (quit-started vis-mod) nil
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
  "Items in iconic memory that may be selected: not in the IOR ring, not in the
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
  "exp(beta (P_i - mean P)), the Luce weights of covert selection."
  (when icons
    (let* ((beta (choice-beta vis-mod))
           (mean (/ (reduce #'+ icons :key #'gsi-priority) (length icons))))
      (mapcar (lambda (i) (exp (min 50.0 (* beta (- (gsi-priority i) mean))))) icons))))

(defun gs-diffuser-oldest-first (vis-mod)
  "The diffuser in insertion order; the list itself is newest first."
  (reverse (diffuser vis-mod)))

;;; ------------------------------------------------------------------
;;; Starting and ending a search
;;; ------------------------------------------------------------------

(defun gs-start-point (vis-mod)
  "GS6's start point: prevalence/2 - 0.25 plus the adaptive offset, kept
strictly inside the bounds."
  (let ((s (+ (if (start-prevalence vis-mod)
                  (- (/ (gs-prevalence vis-mod) 2.0) 0.25)
                0.0)
              (start-offset vis-mod))))
    (min (- (targ-thresh vis-mod) 1e-3) (max (+ (dist-thresh vis-mod) 1e-3) s))))

(defun gs-start-search (vis-mod template guide stop requested)
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (gs-clear-search vis-mod)
    (setf (template vis-mod) template
          (guide-set vis-mod) guide
          (search-stop vis-mod) (or stop 'adaptive)
          (search-requested vis-mod) requested
          (search-active vis-mod) t
          (search-start vis-mod) (mp-time-ms)
          (fix-start vis-mod) (mp-time-ms)
          (search-result vis-mod) 'none
          (search-start-point vis-mod) (gs-start-point vis-mod))
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
            (search-qt vis-mod) (/ (* (or (quit-threshold vis-mod) (qt-init vis-mod))
                                      (max 1.0 (float n)))
                                   (quit-ss-ref vis-mod))))
    (gs-trace "GS-SEARCH start template ~a n-eff ~,0f qt ~,3f start ~,3f"
              (template vis-mod) (search-n-eff vis-mod) (search-qt vis-mod)
              (search-start-point vis-mod))
    (gs-schedule-fixation-timeout vis-mod)
    (gs-schedule-select vis-mod (onset-latency vis-mod))
    (gs-schedule-tick vis-mod)))

(defun gs-schedule-select (vis-mod &optional (extra-ms 0))
  "Schedule the next covert selection; EXTRA-MS delays the first one (:gs-onset-latency)."
  (setf (select-event vis-mod)
        (schedule-event-relative (+ extra-ms (select-interval vis-mod)) 'gs-select
                                 :time-in-ms t :module :vision :destination :vision
                                 :output nil :maintenance t)))

(defun gs-schedule-tick (vis-mod)
  (setf (tick-event vis-mod)
        (schedule-event-relative (diff-step vis-mod) 'gs-diffuser-tick
                                 :time-in-ms t :module :vision :destination :vision
                                 :priority *gs-tick-priority*
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
    (gs-trace-wake "GS-QUIT ~a after ~d rejections, ~d fixations, ~d ms, quit signal ~,3f of ~,3f"
                   reason (rejections vis-mod) (n-fixations vis-mod)
                   (- (mp-time-ms) (search-start vis-mod))
                   (quit-sig vis-mod) (search-qt vis-mod))))

(defun gs-finish-hit (vis-mod icon)
  ;; The diffuser has completed recognition.  Buffer construction is ACT-R's
  ;; existing encoding-complete operation.  A peripheral recognition does not
  ;; teleport gaze to the identified item.
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
                 (gs-enter-diffuser vis-mod (gs-luce-pick vis-mod near)))
                ((null near) (gs-request-saccade vis-mod)))))
      (when (search-active vis-mod) (gs-schedule-select vis-mod)))))

;;; ------------------------------------------------------------------
;;; Identification: the asynchronous diffuser
;;; ------------------------------------------------------------------

(defun gs-template-slots (vis-mod)
  (loop for (slot nil) on (template vis-mod) by #'cddr collect slot))

(defun gs-missing-features (vis-mod icon now)
  "Raw template features not currently available for ICON."
  (remove-if (lambda (slot) (gs-available-p vis-mod icon slot now))
             (gs-template-slots vis-mod)))

(defun gs-item-matches-p (vis-mod icon)
  "Does ICON match the full template, dimension by dimension?"
  (let ((tmpl (gs-template-channels vis-mod (template vis-mod))))
    (loop for (slot nil) on tmpl by #'cddr
          always (> (gs-channel-overlap (getf (gsi-channels icon) slot)
                                        (getf tmpl slot))
                    0.5))))

(defun gs-item-similarity (vis-mod icon)
  "Mean channel overlap with the full template over its dimensions."
  (let ((tmpl (gs-template-channels vis-mod (template vis-mod)))
        (s 0.0) (n 0))
    (loop for (slot nil) on tmpl by #'cddr
          do (incf s (gs-channel-overlap (getf (gsi-channels icon) slot) (getf tmpl slot)))
             (incf n))
    (if (plusp n) (/ s n) 0.0)))

(defun gs-enter-diffuser (vis-mod icon)
  "Select ICON: it enters the diffuser at the trial's start point."
  (let ((match (gs-item-matches-p vis-mod icon)))
    (gs-trace "GS-SELECT ~a priority ~,3f" (gsi-chunk icon) (gsi-priority icon))
    (gs-record-event vis-mod "select" (gsi-chunk icon))
    (push (make-gs-diff :entry (gsi-entry icon)
                        :evidence (search-start-point vis-mod)
                        :match match
                        :drift (if match
                                   (diff-inc vis-mod)
                                 (* (diff-inc vis-mod)
                                    (- 1.0 (* (similarity-drift vis-mod)
                                              (gs-item-similarity vis-mod icon))))))
          (diffuser vis-mod))
    (gs-check-item vis-mod (gsi-entry icon))))

(defun gs-check-item (vis-mod entry)
  "Start an item accumulating if its template features are available; else
wait for a saccade to it, or reject it when the fovea could not help."
  (let ((d (find entry (diffuser vis-mod) :key #'gsd-entry :test 'equal))
        (icon (gethash entry (iconic vis-mod)))
        (now (mp-time-ms)))
    (cond ((null d) nil)
          ((null icon)
           (setf (diffuser vis-mod) (remove d (diffuser vis-mod))))
          ((or (gsd-active d) (not (search-active vis-mod))) nil)
          (t
           (let ((missing (gs-missing-features vis-mod icon now)))
             (cond ((null missing)
                    (setf (gsd-active d) t))
                   ((or (gsd-foveated d) (equal entry (last-landed vis-mod)))
                    ;; still invisible at the fovea: give up on it
                    (gs-trace "GS-DECIDE ~a reject (unresolved ~a)" (gsi-chunk icon) missing)
                    (gs-reject vis-mod entry))
                   (t
                    (setf (gsd-pending d) t)
                    (gs-trace "GS-DECIDE ~a pending ~a" (gsi-chunk icon) missing)
                    (gs-request-saccade vis-mod))))))))

(defun gs-item-check (vis-mod entry)
  "Scheduled re-examination of a pending item after a landing."
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (let ((d (find entry (diffuser vis-mod) :key #'gsd-entry :test 'equal)))
      (when d (setf (gsd-event d) nil)))
    (when (search-active vis-mod)
      (gs-check-item vis-mod entry))))

(defun gs-resume-pending (vis-mod landed-entry)
  "After a landing, re-examine everything that was waiting on foveation."
  (dolist (d (gs-diffuser-oldest-first vis-mod))
    (when (gsd-pending d)
      (setf (gsd-pending d) nil)
      (when (equal (gsd-entry d) landed-entry) (setf (gsd-foveated d) t))
      (setf (gsd-event d)
            (schedule-event-relative *gs-post-saccade-delay* 'gs-item-check
                                     :time-in-ms t :module :vision
                                     :destination :vision :output nil
                                     :maintenance t
                                     :params (list (gsd-entry d)))))))

(defun gs-diffuser-tick (vis-mod)
  "One step of the asynchronous diffuser and of the quit signal.

Order within a step, as in the MATLAB: every active item moves; items below
the distractor bound are rejected; the quit signal moves; an item above the
target bound ends the search with a hit; otherwise a quit signal above the
threshold ends it with nothing found."
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (setf (tick-event vis-mod) nil)
    (when (search-active vis-mod)
      (let ((sd (* (diff-inc vis-mod) (diff-noise vis-mod))))
        (dolist (d (gs-diffuser-oldest-first vis-mod))
          (when (gsd-active d)
            (incf (gsd-evidence d)
                  (* (if (gsd-match d) 1.0 -1.0)
                     (+ (* (gs-standard-normal) sd) (gsd-drift d))))))
        (dolist (d (gs-diffuser-oldest-first vis-mod))
          (when (and (gsd-active d) (< (gsd-evidence d) (dist-thresh vis-mod))
                     (find d (diffuser vis-mod)))
            (let ((icon (gethash (gsd-entry d) (iconic vis-mod))))
              (gs-trace "GS-DECIDE ~a reject" (and icon (gsi-chunk icon))))
            (gs-reject vis-mod (gsd-entry d))
            (unless (search-active vis-mod) (return-from gs-diffuser-tick nil))))
        (when (quit-started vis-mod)
          (incf (quit-sig vis-mod)
                (+ (* (gs-standard-normal) (* (quit-inc vis-mod) (quit-noise vis-mod)))
                   (quit-inc vis-mod))))
        (let ((best nil))
          (dolist (d (gs-diffuser-oldest-first vis-mod))
            (when (and (gsd-active d) (> (gsd-evidence d) (targ-thresh vis-mod))
                       (or (null best) (> (gsd-evidence d) (gsd-evidence best))))
              (setf best d)))
          (when best
            (let ((icon (gethash (gsd-entry best) (iconic vis-mod))))
              (gs-record-event vis-mod "decision" (and icon (gsi-chunk icon)))
              (if icon
                  (gs-finish-hit vis-mod icon)
                (gs-quit-search vis-mod 'target-vanished))
              (return-from gs-diffuser-tick nil))))
        (when (and (member (search-stop vis-mod) '(adaptive both))
                   (quit-started vis-mod)
                   (> (quit-sig vis-mod) (search-qt vis-mod)))
          (gs-quit-search vis-mod 'threshold)
          (return-from gs-diffuser-tick nil))
        (gs-schedule-tick vis-mod)))))

;;; ------------------------------------------------------------------
;;; Rejection and the competitive quit unit
;;; ------------------------------------------------------------------

(defun gs-reject (vis-mod entry)
  (let ((d (find entry (diffuser vis-mod) :key #'gsd-entry :test 'equal))
        (icon (gethash entry (iconic vis-mod))))
    (when (and d (gsd-event d)) (delete-event (gsd-event d)))
    (setf (diffuser vis-mod)
          (remove entry (diffuser vis-mod) :key #'gsd-entry :test 'equal))
    (when (plusp (gs-memory vis-mod))
      (push entry (rejected vis-mod))
      (when (> (length (rejected vis-mod)) (gs-memory vis-mod))
        (setf (rejected vis-mod) (subseq (rejected vis-mod) 0 (gs-memory vis-mod)))))
    (incf (rejections vis-mod))
    (setf (quit-started vis-mod) t)
    (gs-record-event vis-mod "decision" (and icon (gsi-chunk icon)))
    (when (member (search-stop vis-mod) '(cgs both))
      (incf (quit-weight vis-mod) (quit-delta vis-mod))
      (gs-check-quit vis-mod))))

(defun gs-check-quit (vis-mod)
  "The Competitive Guided Search quit lottery; an ablation in this module."
  (let* ((live (loop for e in (icon-order vis-mod)
                     for i = (gethash e (iconic vis-mod))
                     when (and i (not (member e (rejected vis-mod) :test 'equal)))
                       collect i))
         (w (if (quit-noise-free vis-mod)
                (gs-quit-weights vis-mod live) (gs-centred-weights vis-mod live)))
         (denom (+ (if w (reduce #'+ w) 0.0) (quit-weight vis-mod))))
    (when (and (plusp denom)
               (< (act-r-random 1.0) (/ (quit-weight vis-mod) denom)))
      (gs-quit-search vis-mod 'cgs))))

(defun gs-quit-weights (vis-mod icons)
  "Unresolved items retain weights; noise and eccentricity cannot dominate quitting."
  (when icons
    (let ((mean (/ (reduce #'+ icons :key #'gsi-guidance) (length icons)))
          (beta (min 4.0 (choice-beta vis-mod))))
      (mapcar (lambda (i) (exp (min 50.0 (* beta (- (gsi-guidance i) mean))))) icons))))

;;; ------------------------------------------------------------------
;;; Feedback (GS6)
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
  "Apply a gs-feedback request: threshold scale on absent responses, start
point on present ones, priming traces on hits."
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (let ((prev (gs-prevalence vis-mod))
          (qt (or (quit-threshold vis-mod) (qt-init vis-mod))))
      (case outcome
        (tn (setf (quit-threshold vis-mod) (max 0.0 (- qt (* (qt-step vis-mod) prev)))))
        (miss (setf (quit-threshold vis-mod)
                    (+ qt (* (/ (qt-step vis-mod)
                                (max 1e-6 (* (error-goal vis-mod) prev 2.0)))
                             (- 1.0 prev)))))
        (hit (incf (start-offset vis-mod) (start-inc vis-mod)))
        (fa (decf (start-offset vis-mod) (start-dec vis-mod))))
      ;; hits refresh the priming traces of the found item's guiding channels
      (when (and (eq outcome 'hit) (last-found vis-mod))
        (let ((icon (gethash (last-found vis-mod) (iconic vis-mod)))
              (now-s (ms->seconds (mp-time-ms))))
          (when icon
            (dolist (k (gs-guiding vis-mod))
              (dolist (c (getf (gsi-channels icon) k))
                (gs-bump-trace vis-mod (cons k (car c)) now-s))))))
      (push outcome (feedback-log vis-mod))
      (when (> (length (feedback-log vis-mod)) (feedback-window vis-mod))
        (setf (feedback-log vis-mod)
              (subseq (feedback-log vis-mod) 0 (feedback-window vis-mod))))
      (gs-trace "GS-FEEDBACK ~a qt ~,3f start-offset ~,4f prevalence ~,2f"
                outcome (quit-threshold vis-mod) (start-offset vis-mod) prev))))
