;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; gs-params.lisp -- state and parameters of the guided-search vision module.
;;;
;;; Handoff section 6.  Every :gs-* parameter is declared here and mirrored
;;; into a slot of GS-VISION-MODULE, so the hot paths never go through
;;; GET-PARAMETER-VALUE.
;;;
;;; The class definition lives in this file rather than in gs-vision.lisp,
;;; where the handoff's skeleton put it, for one reason: gs-priority.lisp,
;;; gs-diffuser.lisp and gs-eye.lisp are loaded before gs-vision.lisp (they
;;; have to be, because gs-vision.lisp calls DEFINE-MODULE-FCT at load time
;;; and that needs the parameter list), and they use the slot accessors.
;;; Defining the class first is what makes that load order compile clean.
;;;
;;; Times are held in milliseconds inside the module, as ACT-R's own vision
;;; module does, and converted at the parameter boundary.  Mixing seconds and
;;; milliseconds is the timing bug the handoff's section 11 warns about.

(in-package :cl-user)

;;; ------------------------------------------------------------------
;;; Per-item records
;;; ------------------------------------------------------------------

(defstruct (gs-icon (:conc-name gsi-))
  "One entry of iconic memory, keyed by CHUNK-VISICON-ENTRY.

The key is the visicon entry and not the chunk name because
:delete-visicon-chunks defaults to T and deletes location chunks after use
\(handoff section 11)."
  entry                 ; chunk-visicon-entry: the stable identity
  chunk                 ; current visicon chunk name, may be re-created
  (x 0.0) (y 0.0)       ; pixels
  (size-deg 1.0)        ; angular size, mean of width and height
  raw                   ; plist feature -> raw slot value
  channels              ; plist feature -> alist (channel . activation)
  feats                 ; hash feature -> ms at which it was last available
  (prior 0.0)
  salience              ; nil unless the feature supplied one
  (priority 0.0)
  (td 0.0))

(defstruct (gs-diff (:conc-name gsd-))
  "One in-flight item inside the diffuser."
  entry
  event                 ; the scheduled gs-item-decision event
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
   (diffuser       :accessor diffuser       :initform nil)  ; list of gs-diff
   (quit-weight    :accessor quit-weight    :initform 0.0)
   (quit-threshold :accessor quit-threshold :initform nil)  ; unitless, persists
   (search-active  :accessor search-active  :initform nil)
   (search-stop    :accessor search-stop    :initform 'both)
   (search-start   :accessor search-start   :initform 0)
   (search-n-eff   :accessor search-n-eff   :initform 1.0)
   (search-qt      :accessor search-qt      :initform 1.0)  ; this trial's threshold
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
   ;; --- scheduled events -------------------------------------------
   (select-event   :accessor select-event   :initform nil)
   (fix-event      :accessor fix-event      :initform nil)
   (sacc-event     :accessor sacc-event     :initform nil)
   ;; --- adaptive feedback ------------------------------------------
   (feedback-log   :accessor feedback-log   :initform nil)  ; newest first
   ;; --- lock ---------------------------------------------------------
   (gs-lock        :accessor gs-lock
                   :initform (bt:make-recursive-lock "gs-vision"))
   ;; --- parameter mirrors (see gs-vision-params) --------------------
   (gs-enabled     :accessor gs-enabled     :initform t)
   (guiding-features :accessor guiding-features :initform '(color orient size lum))
   (select-interval :accessor select-interval :initform 50)   ; ms
   (diffuser-capacity :accessor diffuser-capacity :initform 5)
   (choice-beta    :accessor choice-beta    :initform 4.0)
   (id-drift       :accessor id-drift       :initform 0.25)
   (id-threshold   :accessor id-threshold   :initform 0.03)
   (quit-delta     :accessor quit-delta     :initform 0.02)
   (gs-memory      :accessor gs-memory      :initform 4)
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
   (qt-init        :accessor qt-init        :initform 1.0)
   (qt-step        :accessor qt-step        :initform 0.05)
   (error-goal     :accessor error-goal     :initform 0.08)
   (feedback-window :accessor feedback-window :initform 50)
   (value-hook     :accessor value-hook     :initform nil)
   (log-fixations  :accessor log-fixations  :initform t))
  (:default-initargs
      :name :VISION
    :version-string "GS-1.0"))

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
     :documentation "Seconds between covert selections while a search is active.")
   (define-parameter :gs-diffuser-capacity
     :valid-test 'gs-posint-p :default-value 5 :warning "a positive integer"
     :documentation "Number of items that can be identified at once.")
   (define-parameter :gs-choice-beta
     :valid-test 'nonneg :default-value 4.0 :warning "a non-negative number"
     :documentation "Luce temperature applied to priorities centred on their mean.")
   (define-parameter :gs-id-drift
     :valid-test 'posnum :default-value 0.25 :warning "a positive number"
     :documentation "Drift rate (mu) of the Wald identification time.")
   (define-parameter :gs-id-threshold
     :valid-test 'posnum :default-value 0.03 :warning "a positive number"
     :documentation "Threshold (theta) of the Wald identification time; sigma is fixed at 0.1.")
   (define-parameter :gs-quit-delta
     :valid-test 'nonneg :default-value 0.02 :warning "a non-negative number"
     :documentation "Increment of the Competitive Guided Search quit weight per rejection.")
   (define-parameter :gs-memory
     :valid-test 'gs-nonneg-int-p :default-value 4 :warning "a non-negative integer"
     :documentation "Size of the inhibition-of-return ring buffer.")
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
   (define-parameter :gs-qt-init
     :valid-test 'nonneg :default-value 1.0 :warning "a non-negative number"
     :documentation "Initial adaptive quitting threshold, in rejections per effective item.")
   (define-parameter :gs-qt-step
     :valid-test 'nonneg :default-value 0.05 :warning "a non-negative number"
     :documentation "Step by which feedback moves the adaptive quitting threshold.")
   (define-parameter :gs-error-goal
     :valid-test 'posnum :default-value 0.08 :warning "a positive number"
     :documentation "Miss rate the adaptive quitting threshold converges on.")
   (define-parameter :gs-feedback-window
     :valid-test 'gs-posint-p :default-value 50 :warning "a positive integer"
     :documentation "Number of recent feedbacks used to estimate target prevalence.")
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

(defun gs-vision-params (vis-mod param)
  "Handle the :gs-* parameters; delegate everything else to the stock handler."
  (flet ((gs-param-name (p) (if (consp p) (car p) p)))
    (let ((name (gs-param-name param)))
      (if (not (member name '(:gs-enabled :gs-guiding-features :gs-select-interval
                              :gs-diffuser-capacity :gs-choice-beta :gs-id-drift
                              :gs-id-threshold :gs-quit-delta :gs-memory
                              :gs-attn-fvf :gs-explore-fvf :gs-max-fixation
                              :gs-iconic-span :gs-acuity-theta :gs-acuity-sigma
                              :gs-w-bu :gs-w-td :gs-w-h :gs-w-v :gs-w-s :gs-w-e
                              :gs-noise :gs-priming-tau :gs-qt-init :gs-qt-step
                              :gs-error-goal :gs-feedback-window :gs-value-hook
                              :gs-log-fixations)))
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
                  (:gs-id-drift (setf (id-drift vis-mod) v))
                  (:gs-id-threshold (setf (id-threshold vis-mod) v))
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
                  (:gs-qt-init (setf (qt-init vis-mod) v)
                   (unless (quit-threshold vis-mod)
                     (setf (quit-threshold vis-mod) v))
                   v)
                  (:gs-qt-step (setf (qt-step vis-mod) v))
                  (:gs-error-goal (setf (error-goal vis-mod) v))
                  (:gs-feedback-window (setf (feedback-window vis-mod) v))
                  (:gs-value-hook (setf (value-hook vis-mod) v))
                  (:gs-log-fixations (setf (log-fixations vis-mod) v))))
            (case name
              (:gs-enabled (gs-enabled vis-mod))
              (:gs-guiding-features (guiding-features vis-mod))
              (:gs-select-interval (ms->seconds (select-interval vis-mod)))
              (:gs-diffuser-capacity (diffuser-capacity vis-mod))
              (:gs-choice-beta (choice-beta vis-mod))
              (:gs-id-drift (id-drift vis-mod))
              (:gs-id-threshold (id-threshold vis-mod))
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
              (:gs-qt-init (qt-init vis-mod))
              (:gs-qt-step (qt-step vis-mod))
              (:gs-error-goal (error-goal vis-mod))
              (:gs-feedback-window (feedback-window vis-mod))
              (:gs-value-hook (value-hook vis-mod))
              (:gs-log-fixations (log-fixations vis-mod)))))))))
