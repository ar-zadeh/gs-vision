;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; gs-params.lisp (gs6-vision) -- state and parameters of the GS6 vision module.
;;;
;;; The gs-vision file with the Competitive Guided Search identification and
;;; quitting parameters (:gs-id-drift, :gs-id-threshold, :gs-id-sigma,
;;; :gs-id-error, :gs-adaptive-quit-delta) replaced by Wolfe's asynchronous
;;; diffuser and quit signal (GS6publicAsPostedJan2021.m):
;;;
;;;   :gs-diff-step :gs-diff-inc :gs-diff-noise :gs-targ-thresh :gs-dist-thresh
;;;   :gs-similarity-drift :gs-start-prevalence :gs-start-inc :gs-start-dec
;;;   :gs-quit-inc :gs-quit-noise :gs-quit-ss-ref
;;;
;;; and two Guided Search 2 priority-map switches, :gs-orient-dual and
;;; :gs-best-channel.  :gs-qt-init, :gs-qt-step and :gs-memory keep their
;;; names but take the MATLAB's values (1.5, 0.005, 0).
;;;
;;; Every :gs-* parameter is declared here and mirrored into a slot of
;;; GS-VISION-MODULE, so the hot paths never go through GET-PARAMETER-VALUE.
;;; Times are held in milliseconds inside the module and converted at the
;;; parameter boundary.

(in-package :cl-user)

;;; ------------------------------------------------------------------
;;; Per-item records
;;; ------------------------------------------------------------------

(defstruct (gs-icon (:conc-name gsi-))
  "One entry of iconic memory, keyed by CHUNK-VISICON-ENTRY.

The key is the visicon entry and not the chunk name because
:delete-visicon-chunks defaults to T and deletes location chunks after use."
  entry                 ; chunk-visicon-entry: the stable identity
  chunk                 ; current visicon chunk name, may be re-created
  (x 0.0) (y 0.0)       ; pixels
  (size-deg 1.0)        ; angular size, mean of width and height
  raw                   ; plist feature -> raw slot value
  channels              ; plist dimension -> alist (channel . activation)
  feats                 ; hash feature -> ms at which it was last available
  (prior 0.0)
  salience              ; nil unless the feature supplied one
  (priority 0.0)
  (guidance 0.0)         ; priority without noise or eccentricity
  (td 0.0))

(defstruct (gs-diff (:conc-name gsd-))
  "One in-flight item inside the asynchronous diffuser."
  entry
  event                 ; a scheduled gs-item-check, while waiting on a landing
  (evidence 0.0)        ; position between :gs-dist-thresh and :gs-targ-thresh
  (active nil)          ; accumulating; nil while template features are unavailable
  (match nil)           ; does the item match the full template? (sets the drift sign)
  (drift 0.0)           ; per-step drift magnitude, similarity-scaled for distractors
  (pending nil)         ; waiting on a foveation
  (foveated nil))       ; a saccade has already landed on it

;;; ------------------------------------------------------------------
;;; The module
;;; ------------------------------------------------------------------

(defclass gs-vision-module (vision-module)
  (;; --- gaze and iconic memory -------------------------------------
   (eye-xyz        :accessor eye-xyz        :initform (vector 0 0 0))
   (iconic         :accessor iconic         :initform (make-hash-table :test 'equal))
   (icon-order     :accessor icon-order     :initform nil)  ; entries, display order
   (display-ranges :accessor display-ranges :initform nil)  ; plist slot -> (lo . hi)
   ;; --- guidance ----------------------------------------------------
   (template       :accessor template       :initform nil)  ; plist slot -> value
   (guide-set      :accessor guide-set      :initform nil)  ; nil = all guiding template slots
   (priority       :accessor priority       :initform (make-hash-table :test 'equal))
   (history        :accessor history        :initform (make-hash-table :test 'equal))
   ;; --- search state -------------------------------------------------
   (rejected       :accessor rejected       :initform nil)  ; IOR ring, newest first
   (diffuser       :accessor diffuser       :initform nil)  ; list of gs-diff, newest first
   (quit-weight    :accessor quit-weight    :initform 0.0)  ; competitive unit (ablation)
   (quit-sig       :accessor quit-sig       :initform 0.0)  ; GS6 quit signal, this trial
   (quit-started   :accessor quit-started   :initform nil)  ; after the first rejection
   (quit-threshold :accessor quit-threshold :initform nil)  ; persistent scale
   (start-offset   :accessor start-offset   :initform 0.0)  ; persistent start-point offset
   (search-start-point :accessor search-start-point :initform 0.0) ; this trial's start point
   (search-active  :accessor search-active  :initform nil)
   (search-stop    :accessor search-stop    :initform 'adaptive)
   (search-start   :accessor search-start   :initform 0)
   (search-n-eff   :accessor search-n-eff   :initform 1.0)
   (search-qt      :accessor search-qt      :initform 1.0)  ; this trial's scaled threshold
   (rejections     :accessor rejections     :initform 0)
   (search-elapsed :accessor search-elapsed :initform 0)   ; ms, last search
   (search-result  :accessor search-result  :initform 'none)
   (quit-reason    :accessor quit-reason    :initform nil)
   (last-found     :accessor last-found     :initform nil)  ; entry of the last hit
   (search-requested :accessor search-requested :initform t)
   ;; --- eye ------------------------------------------------------------
   (last-saccade   :accessor last-saccade   :initform nil)  ; (amplitude . direction)
   (fix-start      :accessor fix-start      :initform 0)
   (last-landed    :accessor last-landed    :initform nil)
   (n-fixations    :accessor n-fixations    :initform 0)
   (fixation-log   :accessor fixation-log   :initform nil)  ; newest first
   (saccade-flight :accessor saccade-flight :initform nil)
   (eye-moving     :accessor eye-moving :initform nil)
   (delivery-event :accessor delivery-event :initform nil)
   (event-log      :accessor event-log :initform nil)
   ;; --- scheduled events -------------------------------------------
   (select-event   :accessor select-event   :initform nil)
   (tick-event     :accessor tick-event     :initform nil)
   (fix-event      :accessor fix-event      :initform nil)
   (sacc-event     :accessor sacc-event     :initform nil)
   ;; --- adaptive feedback ------------------------------------------
   (feedback-log   :accessor feedback-log   :initform nil)  ; newest first
   ;; --- lock ---------------------------------------------------------
   (gs-lock        :accessor gs-lock
                   :initform (bt:make-recursive-lock "gs6-vision"))
   ;; --- parameter mirrors (see gs-vision-params) --------------------
   (gs-enabled     :accessor gs-enabled     :initform t)
   (guiding-features :accessor guiding-features :initform '(color orient size lum))
   (select-interval :accessor select-interval :initform 50)   ; ms
   (diffuser-capacity :accessor diffuser-capacity :initform 5)
   (choice-beta    :accessor choice-beta    :initform 4.0)
   (saccade-margin :accessor saccade-margin :initform 0.25)
   (saccade-proximity :accessor saccade-proximity :initform 0.10)
   (revised-saccades :accessor revised-saccades :initform t)
   (quit-noise-free :accessor quit-noise-free :initform t)
   (recognition-extra :accessor recognition-extra :initform nil)
   (onset-latency  :accessor onset-latency  :initform 0)      ; ms
   (explore-proximity :accessor explore-proximity :initform t)
   (saccade-trigger :accessor saccade-trigger :initform 0.0)   ; deg, 0 = off
   (quit-delta     :accessor quit-delta     :initform 0.02)
   (gs-memory      :accessor gs-memory      :initform 0)
   (attn-fvf       :accessor attn-fvf       :initform 8.0)
   (explore-fvf    :accessor explore-fvf    :initform 12.0)
   (max-fixation   :accessor max-fixation   :initform 400)    ; ms
   (iconic-span    :accessor iconic-span    :initform 4000)   ; ms
   (acuity-theta   :accessor acuity-theta
                   :initform '(color 0.10 orient 0.20 shape 0.40 size 0.20 lum 0.10))
   (acuity-sigma   :accessor acuity-sigma   :initform 0.5)
   (w-bu           :accessor w-bu           :initform 0.5)
   (w-td           :accessor w-td           :initform 1.0)
   (w-h            :accessor w-h            :initform 0.3)
   (w-v            :accessor w-v            :initform 0.0)
   (w-s            :accessor w-s            :initform 1.0)
   (w-e            :accessor w-e            :initform 0.02)
   (gs-noise       :accessor gs-noise       :initform 0.2)
   (priming-tau    :accessor priming-tau    :initform 10.0)   ; s
   ;; the GS6 diffuser
   (diff-step      :accessor diff-step      :initform 10)     ; ms
   (diff-inc       :accessor diff-inc       :initform 0.05)
   (diff-noise     :accessor diff-noise     :initform 2.5)
   (targ-thresh    :accessor targ-thresh    :initform 1.0)
   (dist-thresh    :accessor dist-thresh    :initform -1.0)
   (similarity-drift :accessor similarity-drift :initform 0.0)
   (start-prevalence :accessor start-prevalence :initform t)
   (start-inc      :accessor start-inc      :initform 0.0008)
   (start-dec      :accessor start-dec      :initform 0.05)
   ;; the GS6 quit signal
   (quit-inc       :accessor quit-inc       :initform 0.018)
   (quit-noise     :accessor quit-noise     :initform 2.5)
   (qt-init        :accessor qt-init        :initform 1.5)
   (quit-ss-ref    :accessor quit-ss-ref    :initform 10.0)
   (qt-step        :accessor qt-step        :initform 0.005)
   (error-goal     :accessor error-goal     :initform 0.08)
   (feedback-window :accessor feedback-window :initform 50)
   ;; Guided Search 2 priority-map rules
   (orient-dual    :accessor orient-dual    :initform t)
   (best-channel   :accessor best-channel   :initform t)
   (value-hook     :accessor value-hook     :initform nil)
   (log-fixations  :accessor log-fixations  :initform t))
  (:default-initargs
      :name :VISION
    :version-string "GS6-1.0"))

;;; ------------------------------------------------------------------
;;; Parameter validation helpers
;;; ------------------------------------------------------------------

(defun gs-symbol-list-p (x)
  (and (listp x) (every 'symbolp x)))

(defun gs-theta-plist-p (x)
  (and (listp x) (evenp (length x))
       (loop for (k v) on x by #'cddr
             always (and (symbolp k) (numberp v) (>= v 0)))))

(defun gs-posint-p (x) (and (integerp x) (plusp x)))
(defun gs-nonneg-int-p (x) (and (integerp x) (>= x 0)))
(defun gs-probability-p (x) (and (numberp x) (<= 0 x 1)))
(defun gs-negnum-p (x) (and (numberp x) (minusp x)))

;;; ------------------------------------------------------------------
;;; Parameter list
;;; ------------------------------------------------------------------

(defun gs-parameter-list ()
  "The :gs-* parameters, appended to the stock vision list in gs-vision.lisp."
  (list
   (define-parameter :gs-enabled
     :valid-test 'tornil :default-value t :warning "T or NIL"
     :documentation "Enable the guided-search API. NIL leaves the default vision module behaviour and refuses gs requests.")
   (define-parameter :gs-guiding-features
     :valid-test 'gs-symbol-list-p :default-value '(color orient size lum)
     :warning "a list of feature slot names"
     :documentation "Features that may guide selection. Everything else is identification-only.")
   (define-parameter :gs-select-interval
     :valid-test 'nonneg :default-value 0.050 :warning "a non-negative number"
     :documentation "Seconds between covert selections while a search is active (GS6: 50 ms).")
   (define-parameter :gs-diffuser-capacity
     :valid-test 'gs-posint-p :default-value 5 :warning "a positive integer"
     :documentation "Number of items in the asynchronous diffuser at once (GS6: 5).")
   (define-parameter :gs-choice-beta
     :valid-test 'nonneg :default-value 4.0 :warning "a non-negative number"
     :documentation "Luce temperature applied to priorities centred on their mean.")
   (define-parameter :gs-saccade-margin
     :valid-test 'nonneg :default-value 0.25 :warning "a non-negative number"
     :documentation "Noise-free guidance advantage needed to prefer a distant item.")
   (define-parameter :gs-saccade-proximity
     :valid-test 'nonneg :default-value 0.10 :warning "a non-negative number"
     :documentation "Saccade destination guidance penalty per degree.")
   (define-parameter :gs-revised-saccades
     :valid-test 'tornil :default-value t :warning "T or NIL"
     :documentation "Use guidance and proximity for eye movements; NIL is the historical ablation.")
   (define-parameter :gs-quit-noise-free
     :valid-test 'tornil :default-value t :warning "T or NIL"
     :documentation "Competitive unit only: noise-free guidance with beta capped at 4 for quit weights.")
   (define-parameter :gs-recognition-extra
     :valid-test 'tornil :default-value nil :warning "T or NIL"
     :documentation "Historical extra EMMA recognition delay, for fixed-parameter ablations only.")
   (define-parameter :gs-onset-latency
     :valid-test 'nonneg :default-value 0.0 :warning "a non-negative number"
     :documentation "Seconds after a search request before the first covert selection.")
   (define-parameter :gs-explore-proximity
     :valid-test 'tornil :default-value t :warning "T or NIL"
     :documentation "When nothing is selectable inside :gs-attn-fvf, choose the saccade destination by guidance minus distance rather than guidance alone.")
   (define-parameter :gs-saccade-trigger
     :valid-test 'nonneg :default-value 0.0 :warning "a non-negative number"
     :documentation "Degrees; when positive, a saccade is requested as soon as the nearest selectable item is farther than this, while covert selection continues.")
   (define-parameter :gs-quit-delta
     :valid-test 'nonneg :default-value 0.02 :warning "a non-negative number"
     :documentation "Competitive unit only (stop cgs or both): quit weight added per rejection.")
   (define-parameter :gs-memory
     :valid-test 'gs-nonneg-int-p :default-value 0 :warning "a non-negative integer"
     :documentation "Inhibition-of-return ring beyond the diffuser. GS6's posted simulation has none.")
   (define-parameter :gs-attn-fvf
     :valid-test 'posnum :default-value 8.0 :warning "a positive number"
     :documentation "Radius in degrees within which an item may be selected covertly.")
   (define-parameter :gs-explore-fvf
     :valid-test 'posnum :default-value 12.0 :warning "a positive number"
     :documentation "Radius in degrees within which the next saccade target is chosen.")
   (define-parameter :gs-max-fixation
     :valid-test 'posnum :default-value 0.4 :warning "a positive number"
     :documentation "Seconds after which a fixation is abandoned even if items remain.")
   (define-parameter :gs-iconic-span
     :valid-test 'nonneg :default-value 4.0 :warning "a non-negative number"
     :documentation "Seconds a feature stays in iconic memory after it was last available.")
   (define-parameter :gs-acuity-theta
     :valid-test 'gs-theta-plist-p
     :default-value '(color 0.10 orient 0.20 shape 0.40 size 0.20 lum 0.10)
     :warning "a plist of feature name and non-negative number"
     :documentation "EPIC availability slope per feature: available with probability P(size > N(theta*ecc, sigma)).")
   (define-parameter :gs-acuity-sigma
     :valid-test 'posnum :default-value 0.5 :warning "a positive number"
     :documentation "Standard deviation of the EPIC availability threshold.")
   (define-parameter :gs-w-bu
     :valid-test 'numberp :default-value 0.5 :warning "a number"
     :documentation "Weight of the bottom-up term of the priority map.")
   (define-parameter :gs-w-td
     :valid-test 'numberp :default-value 1.0 :warning "a number"
     :documentation "Weight of the top-down term of the priority map.")
   (define-parameter :gs-w-h
     :valid-test 'numberp :default-value 0.3 :warning "a number"
     :documentation "Weight of the priming/history term of the priority map.")
   (define-parameter :gs-w-v
     :valid-test 'numberp :default-value 0.0 :warning "a number"
     :documentation "Weight of the value term of the priority map.")
   (define-parameter :gs-w-s
     :valid-test 'numberp :default-value 1.0 :warning "a number"
     :documentation "Weight of the scene-prior term of the priority map.")
   (define-parameter :gs-w-e
     :valid-test 'numberp :default-value 0.02 :warning "a number"
     :documentation "Penalty per degree of eccentricity in the priority map.")
   (define-parameter :gs-noise
     :valid-test 'nonneg :default-value 0.2 :warning "a non-negative number"
     :documentation "Scale of the logistic noise added to every priority value.")
   (define-parameter :gs-priming-tau
     :valid-test 'posnum :default-value 10.0 :warning "a positive number"
     :documentation "Decay constant in seconds of the feature priming traces.")
   ;; --- the GS6 diffuser ---------------------------------------------
   (define-parameter :gs-diff-step
     :valid-test 'posnum :default-value 0.010 :warning "a positive number"
     :documentation "Seconds between diffuser updates (GS6 RTstep: 10 ms).")
   (define-parameter :gs-diff-inc
     :valid-test 'posnum :default-value 0.05 :warning "a positive number"
     :documentation "Evidence gained per step toward the correct bound (GS6 adifInc: 0.05, 20 noiseless steps).")
   (define-parameter :gs-diff-noise
     :valid-test 'posnum :default-value 2.5 :warning "a positive number"
     :documentation "Step noise SD as a multiple of :gs-diff-inc (GS6 adifNoise: 2.5).")
   (define-parameter :gs-targ-thresh
     :valid-test 'posnum :default-value 1.0 :warning "a positive number"
     :documentation "Evidence at which an item is accepted as the target (GS6 TargThresh: 1).")
   (define-parameter :gs-dist-thresh
     :valid-test 'gs-negnum-p :default-value -1.0 :warning "a negative number"
     :documentation "Evidence at which an item is rejected as a distractor (GS6 DistThresh: -1).")
   (define-parameter :gs-similarity-drift
     :valid-test 'gs-probability-p :default-value 0.0 :warning "a number between 0 and 1"
     :documentation "A distractor's drift is :gs-diff-inc * (1 - this * its template similarity). 0 is the posted simulation's fixed rate.")
   (define-parameter :gs-start-prevalence
     :valid-test 'tornil :default-value t :warning "T or NIL"
     :documentation "Start each item at prevalence/2 - 0.25 (GS6) plus the adaptive offset; NIL starts at the offset alone.")
   (define-parameter :gs-start-inc
     :valid-test 'nonneg :default-value 0.0008 :warning "a non-negative number"
     :documentation "Start-point rise after a hit (GS6 StartInc).")
   (define-parameter :gs-start-dec
     :valid-test 'nonneg :default-value 0.05 :warning "a non-negative number"
     :documentation "Start-point fall after a false alarm (GS6 StartDec).")
   ;; --- the GS6 quit signal ----------------------------------------------
   (define-parameter :gs-quit-inc
     :valid-test 'posnum :default-value 0.018 :warning "a positive number"
     :documentation "Quit signal gained per step after the first rejection (GS6 quitInc).")
   (define-parameter :gs-quit-noise
     :valid-test 'posnum :default-value 2.5 :warning "a positive number"
     :documentation "Quit signal step noise SD as a multiple of :gs-quit-inc (GS6 quitNoiseSD).")
   (define-parameter :gs-qt-init
     :valid-test 'nonneg :default-value 1.5 :warning "a non-negative number"
     :documentation "Initial quitting threshold at :gs-quit-ss-ref effective items (GS6 quitThresh(1): 1.5).")
   (define-parameter :gs-quit-ss-ref
     :valid-test 'posnum :default-value 10.0 :warning "a positive number"
     :documentation "The threshold is quit-threshold * N_eff / this (GS6: max(SS) * 0.5 = 10).")
   (define-parameter :gs-qt-step
     :valid-test 'nonneg :default-value 0.005 :warning "a non-negative number"
     :documentation "Threshold fall per true negative, times prevalence (GS6 quitDownStep).")
   (define-parameter :gs-error-goal
     :valid-test 'posnum :default-value 0.08 :warning "a positive number"
     :documentation "Miss rate the quitting threshold converges on (GS6 missDesired).")
   (define-parameter :gs-feedback-window
     :valid-test 'gs-posint-p :default-value 50 :warning "a positive integer"
     :documentation "Number of recent feedbacks used to estimate target prevalence.")
   ;; --- Guided Search 2 priority-map rules ---------------------------------
   (define-parameter :gs-orient-dual
     :valid-test 'tornil :default-value t :warning "T or NIL"
     :documentation "An item drives a steep/shallow and a left/right channel at once (GS2); NIL is the exclusive binning of gs-vision.")
   (define-parameter :gs-best-channel
     :valid-test 'tornil :default-value t :warning "T or NIL"
     :documentation "Top-down guidance uses, per dimension, the template channel that best separates the template from the display (GS2); NIL uses the overlap with the template.")
   (define-parameter :gs-value-hook
     :valid-test 'local-or-remote-function-or-nil :default-value nil
     :warning "a local or remote function, or NIL"
     :documentation "Called with a visual-location chunk; returns the value term of the priority map.")
   (define-parameter :gs-log-fixations
     :valid-test 'tornil :default-value t :warning "T or NIL"
     :documentation "Keep the fixation log, readable through the gs-fixation-log command.")))

;;; ------------------------------------------------------------------
;;; Parameter handling
;;; ------------------------------------------------------------------

(defparameter *gs-parameter-names*
  '(:gs-enabled :gs-guiding-features :gs-select-interval :gs-diffuser-capacity
    :gs-choice-beta :gs-saccade-margin :gs-saccade-proximity :gs-revised-saccades
    :gs-quit-noise-free :gs-recognition-extra :gs-onset-latency
    :gs-explore-proximity :gs-saccade-trigger :gs-quit-delta :gs-memory
    :gs-attn-fvf :gs-explore-fvf :gs-max-fixation :gs-iconic-span
    :gs-acuity-theta :gs-acuity-sigma :gs-w-bu :gs-w-td :gs-w-h :gs-w-v :gs-w-s
    :gs-w-e :gs-noise :gs-priming-tau
    :gs-diff-step :gs-diff-inc :gs-diff-noise :gs-targ-thresh :gs-dist-thresh
    :gs-similarity-drift :gs-start-prevalence :gs-start-inc :gs-start-dec
    :gs-quit-inc :gs-quit-noise :gs-qt-init :gs-quit-ss-ref :gs-qt-step
    :gs-error-goal :gs-feedback-window :gs-orient-dual :gs-best-channel
    :gs-value-hook :gs-log-fixations))

(defun gs-vision-params (vis-mod param)
  "Handle the :gs-* parameters; delegate everything else to the stock handler."
  (flet ((gs-param-name (p) (if (consp p) (car p) p)))
    (let ((name (gs-param-name param)))
      (if (not (member name *gs-parameter-names*))
          (params-vision-module vis-mod param)
        (bt:with-recursive-lock-held ((gs-lock vis-mod))
          (if (consp param)
              (let ((v (cdr param)))
                (case name
                  (:gs-enabled (setf (gs-enabled vis-mod) v))
                  (:gs-guiding-features (setf (guiding-features vis-mod) v))
                  (:gs-select-interval
                   (setf (select-interval vis-mod) (safe-seconds->ms v 'sgp)) v)
                  (:gs-diffuser-capacity (setf (diffuser-capacity vis-mod) v))
                  (:gs-choice-beta (setf (choice-beta vis-mod) v))
                  (:gs-saccade-margin (setf (saccade-margin vis-mod) v))
                  (:gs-saccade-proximity (setf (saccade-proximity vis-mod) v))
                  (:gs-revised-saccades (setf (revised-saccades vis-mod) v))
                  (:gs-quit-noise-free (setf (quit-noise-free vis-mod) v))
                  (:gs-recognition-extra (setf (recognition-extra vis-mod) v))
                  (:gs-onset-latency
                   (setf (onset-latency vis-mod) (safe-seconds->ms v 'sgp)) v)
                  (:gs-explore-proximity (setf (explore-proximity vis-mod) v))
                  (:gs-saccade-trigger (setf (saccade-trigger vis-mod) v))
                  (:gs-quit-delta (setf (quit-delta vis-mod) v))
                  (:gs-memory (setf (gs-memory vis-mod) v))
                  (:gs-attn-fvf (setf (attn-fvf vis-mod) v))
                  (:gs-explore-fvf (setf (explore-fvf vis-mod) v))
                  (:gs-max-fixation
                   (setf (max-fixation vis-mod) (safe-seconds->ms v 'sgp)) v)
                  (:gs-iconic-span
                   (setf (iconic-span vis-mod) (safe-seconds->ms v 'sgp)) v)
                  (:gs-acuity-theta (setf (acuity-theta vis-mod) v))
                  (:gs-acuity-sigma (setf (acuity-sigma vis-mod) v))
                  (:gs-w-bu (setf (w-bu vis-mod) v))
                  (:gs-w-td (setf (w-td vis-mod) v))
                  (:gs-w-h (setf (w-h vis-mod) v))
                  (:gs-w-v (setf (w-v vis-mod) v))
                  (:gs-w-s (setf (w-s vis-mod) v))
                  (:gs-w-e (setf (w-e vis-mod) v))
                  (:gs-noise (setf (gs-noise vis-mod) v))
                  (:gs-priming-tau (setf (priming-tau vis-mod) v))
                  (:gs-diff-step
                   (setf (diff-step vis-mod) (max 1 (safe-seconds->ms v 'sgp))) v)
                  (:gs-diff-inc (setf (diff-inc vis-mod) v))
                  (:gs-diff-noise (setf (diff-noise vis-mod) v))
                  (:gs-targ-thresh (setf (targ-thresh vis-mod) v))
                  (:gs-dist-thresh (setf (dist-thresh vis-mod) v))
                  (:gs-similarity-drift (setf (similarity-drift vis-mod) v))
                  (:gs-start-prevalence (setf (start-prevalence vis-mod) v))
                  (:gs-start-inc (setf (start-inc vis-mod) v))
                  (:gs-start-dec (setf (start-dec vis-mod) v))
                  (:gs-quit-inc (setf (quit-inc vis-mod) v))
                  (:gs-quit-noise (setf (quit-noise vis-mod) v))
                  (:gs-qt-init (setf (qt-init vis-mod) v)
                   (unless (or (search-active vis-mod) (feedback-log vis-mod))
                     (setf (quit-threshold vis-mod) v))
                   v)
                  (:gs-quit-ss-ref (setf (quit-ss-ref vis-mod) v))
                  (:gs-qt-step (setf (qt-step vis-mod) v))
                  (:gs-error-goal (setf (error-goal vis-mod) v))
                  (:gs-feedback-window (setf (feedback-window vis-mod) v))
                  (:gs-orient-dual (setf (orient-dual vis-mod) v))
                  (:gs-best-channel (setf (best-channel vis-mod) v))
                  (:gs-value-hook (setf (value-hook vis-mod) v))
                  (:gs-log-fixations (setf (log-fixations vis-mod) v))))
            (case name
              (:gs-enabled (gs-enabled vis-mod))
              (:gs-guiding-features (guiding-features vis-mod))
              (:gs-select-interval (ms->seconds (select-interval vis-mod)))
              (:gs-diffuser-capacity (diffuser-capacity vis-mod))
              (:gs-choice-beta (choice-beta vis-mod))
              (:gs-saccade-margin (saccade-margin vis-mod))
              (:gs-saccade-proximity (saccade-proximity vis-mod))
              (:gs-revised-saccades (revised-saccades vis-mod))
              (:gs-quit-noise-free (quit-noise-free vis-mod))
              (:gs-recognition-extra (recognition-extra vis-mod))
              (:gs-onset-latency (ms->seconds (onset-latency vis-mod)))
              (:gs-explore-proximity (explore-proximity vis-mod))
              (:gs-saccade-trigger (saccade-trigger vis-mod))
              (:gs-quit-delta (quit-delta vis-mod))
              (:gs-memory (gs-memory vis-mod))
              (:gs-attn-fvf (attn-fvf vis-mod))
              (:gs-explore-fvf (explore-fvf vis-mod))
              (:gs-max-fixation (ms->seconds (max-fixation vis-mod)))
              (:gs-iconic-span (ms->seconds (iconic-span vis-mod)))
              (:gs-acuity-theta (acuity-theta vis-mod))
              (:gs-acuity-sigma (acuity-sigma vis-mod))
              (:gs-w-bu (w-bu vis-mod))
              (:gs-w-td (w-td vis-mod))
              (:gs-w-h (w-h vis-mod))
              (:gs-w-v (w-v vis-mod))
              (:gs-w-s (w-s vis-mod))
              (:gs-w-e (w-e vis-mod))
              (:gs-noise (gs-noise vis-mod))
              (:gs-priming-tau (priming-tau vis-mod))
              (:gs-diff-step (ms->seconds (diff-step vis-mod)))
              (:gs-diff-inc (diff-inc vis-mod))
              (:gs-diff-noise (diff-noise vis-mod))
              (:gs-targ-thresh (targ-thresh vis-mod))
              (:gs-dist-thresh (dist-thresh vis-mod))
              (:gs-similarity-drift (similarity-drift vis-mod))
              (:gs-start-prevalence (start-prevalence vis-mod))
              (:gs-start-inc (start-inc vis-mod))
              (:gs-start-dec (start-dec vis-mod))
              (:gs-quit-inc (quit-inc vis-mod))
              (:gs-quit-noise (quit-noise vis-mod))
              (:gs-qt-init (qt-init vis-mod))
              (:gs-quit-ss-ref (quit-ss-ref vis-mod))
              (:gs-qt-step (qt-step vis-mod))
              (:gs-error-goal (error-goal vis-mod))
              (:gs-feedback-window (feedback-window vis-mod))
              (:gs-orient-dual (orient-dual vis-mod))
              (:gs-best-channel (best-channel vis-mod))
              (:gs-value-hook (value-hook vis-mod))
              (:gs-log-fixations (log-fixations vis-mod)))))))))
