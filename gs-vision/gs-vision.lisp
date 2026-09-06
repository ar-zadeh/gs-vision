;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; gs-vision.lisp -- the module itself: creation, reset, requests, queries.
;;;
;;; Handoff section 4: subclass VISION-MODULE, then UNDEFINE-MODULE :vision and
;;; DEFINE-MODULE-FCT :vision again with the same buffer names, so the motor
;;; module, the AGI devices, the Environment and EMMA all keep working against
;;; a module they already know.  PAAV did exactly this in ACT-R 6.
;;;
;;; Load this file last: it calls DEFINE-MODULE-FCT while loading, and that
;;; needs GS-PARAMETER-LIST from gs-params.lisp.  It must also run before any
;;; CLEAR-ALL or DEFINE-MODEL, because UNDEFINE-MODULE refuses to do anything
;;; once a model exists.
;;;
;;; Backward compatibility.  With :gs-enabled t a request that does not use the
;;; new API goes straight to CALL-NEXT-METHOD, so tutorial models produce the
;;; same trace as the stock module.  With :gs-enabled nil the new API is
;;; refused with a warning and nothing else changes.  tests/test_backcompat.py
;;; checks both against traces captured from the stock module.

(in-package :cl-user)

;;; ------------------------------------------------------------------
;;; Creation and reset
;;; ------------------------------------------------------------------

(defparameter *gs-extra-chunks*
  '(;; orientation, size and luminance channels, usable as template values
    steep shallow left right small medium large dark mid bright
    ;; feedback outcomes and search-result query values
    hit miss fa tn found failed none
    ;; stop policies
    adaptive cgs both)
  "Symbols the new API accepts as slot values; ACT-R needs them to be chunks.")

(defun create-gs-vision-module (model-name)
  "Everything CREATE-VISION-MODULE does, plus the guided-search chunk-types.

The stock function is called rather than copied so that the chunk-types and
default chunks stay in step with upstream; the VISION-MODULE instance it
returns is discarded."
  (create-vision-module model-name)

  ;; Extended visicon features (handoff section 5.1).  Declaring them here
  ;; means a model or a Python harness can pass hue/orient/lum/shape/salience/
  ;; prior to add-visicon-features without declaring a chunk-type of its own.
  (chunk-type (gs-feature (:include visual-location)) hue orient lum shape
              salience prior)

  ;; Requests on the visual buffer.
  ;; The template slots are listed explicitly so that a model writing
  ;; `+visual> isa gs-search color red` does not draw a "slot invalid for
  ;; type" warning.  Any other valid slot name still works; it is only the
  ;; warning that the declaration removes.
  (chunk-type (gs-search (:include vision-command)) (cmd gs-search)
              guide stop hue orient lum shape salience prior
              color value height width size kind)
  (chunk-type (gs-feedback (:include vision-command)) (cmd gs-feedback) outcome)

  (dolist (c '(gs-search gs-feedback))
    (unless (chunk-p-fct c) (define-chunks-fct `((,c isa ,c)))))
  (dolist (c *gs-extra-chunks*)
    (unless (chunk-p-fct c) (define-chunks-fct `((,c name ,c)))))

  (make-instance 'gs-vision-module))

(defun reset-gs-vision-module (vis-mod)
  "Stock reset, then clear every piece of guided-search state.

A reset is the only thing that wipes the adaptive quitting threshold, the
priming traces and the prevalence window: one model run is one simulated
subject, so those have to survive between trials (handoff section 11)."
  (reset-vision-module vis-mod)
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    ;; do not call DELETE-EVENT here: the queue is being torn down anyway
    (setf (select-event vis-mod) nil
          (fix-event vis-mod) nil
          (sacc-event vis-mod) nil
          (saccade-flight vis-mod) nil
          (diffuser vis-mod) nil
          (rejected vis-mod) nil
          (quit-weight vis-mod) 0.0
          (rejections vis-mod) 0
          (search-active vis-mod) nil
          (search-result vis-mod) 'none
          (quit-reason vis-mod) nil
          (search-elapsed vis-mod) 0
          (last-found vis-mod) nil
          (n-fixations vis-mod) 0
          (fixation-log vis-mod) nil
          (last-saccade vis-mod) nil
          (last-landed vis-mod) nil
          (template vis-mod) nil
          (guide-set vis-mod) nil
          (icon-order vis-mod) nil
          (display-ranges vis-mod) nil
          (feedback-log vis-mod) nil
          (quit-threshold vis-mod) (qt-init vis-mod)
          (eye-xyz vis-mod) (vector 0 0 0))
    (clrhash (iconic vis-mod))
    (clrhash (priority vis-mod))
    (clrhash (history vis-mod))))

;;; ------------------------------------------------------------------
;;; Queries
;;; ------------------------------------------------------------------

(defun gs-query-vision-module (vis-mod buffer slot value)
  (if (and (eq buffer 'visual) (eq slot 'search-result))
      (eq value (search-result vis-mod))
    (query-vision-module vis-mod buffer slot value)))

(defun gs-visual-buffer-status ()
  (let ((v (get-module :vision)))
    (concatenate 'string (visual-buffer-status)
                 (format nil "~%  search-result         : ~S"
                         (if (typep v 'gs-vision-module) (search-result v) 'none)))))

;;; ------------------------------------------------------------------
;;; Request parsing
;;; ------------------------------------------------------------------

(defparameter *gs-request-only-slots* '(cmd guide stop)
  "Slots of a gs-search request that describe the request, not the target.")

(defun gs-spec-plist (chunk-spec &optional exclude)
  "The explicit (= slot value) pairs of CHUNK-SPEC as a plist.

Request parameters are keywords and are skipped, as are slots in EXCLUDE and
anything using a test other than =."
  (let (out)
    (dolist (s (chunk-spec-slot-spec chunk-spec) (nreverse out))
      (let ((op (spec-slot-op s)) (name (spec-slot-name s)))
        (when (and (eq op '=) (not (keywordp name)) (not (member name exclude)))
          (push name out)
          (push (spec-slot-value s) out))))))

(defun gs-spec-guide (chunk-spec)
  "The `guide` restriction, accepting either a list or repeated symbols.

A production cannot write a list as a slot value, so `guide color guide orient`
is accepted as well as the `guide (color)` of section 5.7."
  (let (out)
    (dolist (s (chunk-spec-slot-spec chunk-spec 'guide) out)
      (let ((v (spec-slot-value s)))
        (cond ((listp v) (setf out (append out v)))
              (v (setf out (append out (list v)))))))))

(defun gs-spec-stop (chunk-spec)
  (let ((s (first (chunk-spec-slot-spec chunk-spec 'stop))))
    (if s
        (let ((v (spec-slot-value s)))
          (if (member v '(adaptive cgs both)) v
            (progn (print-warning "gs-search stop must be adaptive, cgs or both, not ~s. Using both." v)
                   'both)))
      'both)))

(defun gs-search-request (vis-mod chunk-spec)
  (let ((template (gs-spec-plist chunk-spec *gs-request-only-slots*))
        (guide (gs-spec-guide chunk-spec))
        (stop (gs-spec-stop chunk-spec)))
    (if (null template)
        (print-warning "A gs-search request needs at least one target feature.")
      (gs-start-search vis-mod template guide stop t))))

(defun gs-feedback-request (vis-mod chunk-spec)
  (let ((o (verify-single-explicit-value chunk-spec 'outcome :vision 'gs-feedback)))
    (if (member o '(hit miss fa tn))
        (gs-feedback vis-mod o)
      (print-warning "gs-feedback outcome must be hit, miss, fa or tn, not ~s." o))))

(defmethod pm-module-request ((vis-mod gs-vision-module) buffer-name chunk-spec)
  (let ((cmd (and (eq buffer-name 'visual)
                  (= 1 (length (chunk-spec-slot-spec chunk-spec 'cmd)))
                  (spec-slot-value (first (chunk-spec-slot-spec chunk-spec 'cmd))))))
    (if (not (member cmd '(gs-search gs-feedback)))
        (call-next-method)
      (progn
        ;; WARN-VISION locked the module when this request was warned; the
        ;; stock visual branch unlocks it and so must this one.
        (when (visual-lock vis-mod)
          (setf (visual-lock vis-mod) nil)
          (schedule-event-now 'unlock-vision :module :vision :destination :vision
                                             :priority :min :output nil :maintenance t))
        (cond ((not (gs-enabled vis-mod))
               (print-warning "A ~a request was made but :gs-enabled is nil." cmd))
              ((eq cmd 'gs-search)
               (schedule-event-now 'gs-search-request :module :vision
                                                      :destination :vision
                                                      :output 'medium :details "Gs-search"
                                                      :params (list chunk-spec)))
              (t
               (schedule-event-now 'gs-feedback-request :module :vision
                                                        :destination :vision
                                                        :output 'medium :details "Gs-feedback"
                                                        :params (list chunk-spec))))))))

;;; ------------------------------------------------------------------
;;; Guided visual-location requests (section 5.7)
;;; ------------------------------------------------------------------

(defun gs-guided-request-p (vis-mod chunk-spec)
  (and (gs-enabled vis-mod)
       (let ((s (first (chunk-spec-slot-spec chunk-spec :guided))))
         (and s (eq (spec-slot-op s) '=) (spec-slot-value s)))))

(defun gs-position-slots (vis-mod)
  (bt:with-lock-held ((vis-loc-lock vis-mod)) (copy-list (vis-loc-slots vis-mod))))

(defun gs-reduced-spec (vis-mod chunk-spec)
  "The part of a :guided request that still filters exactly.

Position slots and the standard request parameters keep their usual meaning;
every feature slot becomes a template constraint instead, so that
`shape two :guided t` ranks the display rather than filtering it, which is
what makes the first selection in 2-vs-5 land at chance (section 10, phase 3)."
  (let ((keep (gs-position-slots vis-mod))
        (specs nil))
    (dolist (s (chunk-spec-slot-spec chunk-spec))
      (let ((name (spec-slot-name s)))
        (cond ((eq name :guided))                       ; consumed here
              ((member name '(:attended :nearest :center))
               (setf specs (append specs (list (spec-slot-op s) name (spec-slot-value s)))))
              ((member name keep)
               (setf specs (append specs (list (spec-slot-op s) name (spec-slot-value s)))))
              (t))))                                    ; feature slot: template
    (when specs (define-chunk-spec-fct specs))))

(defun gs-guided-find-location (vis-mod chunk-spec)
  "Rank the display by priority and put the winner in the visual-location buffer.

Costs one :gs-select-interval rather than the stock 0 ms, because it runs one
module-internal selection step."
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (setf (template vis-mod) (gs-spec-plist chunk-spec
                                            (append '(:guided)
                                                    (gs-position-slots vis-mod)))
          (guide-set vis-mod) nil)
    (gs-refresh-iconic vis-mod)
    (gs-centre-eye vis-mod)
    (gs-draw-availability vis-mod)
    (gs-compute-priority vis-mod)
    (let* ((reduced (gs-reduced-spec vis-mod chunk-spec))
           (allowed (when reduced (find-current-locs-with-spec vis-mod reduced)))
           (icons (remove-if-not
                   (lambda (i) (or (null reduced)
                                   (member (gsi-chunk i) allowed)))
                   (gs-eligible vis-mod))))
      (bt:with-recursive-lock-held ((marker-lock vis-mod))
        (if (null icons)
            (progn
              (set-buffer-failure 'visual-location)
              (setf (loc-failure vis-mod) t)
              (schedule-event-now nil :module :vision :output 'low
                                      :details "find-loc-failure"))
          ;; Section 5.7 says a guided location request returns the
          ;; *highest-priority* matching location, so this is winner-take-all
          ;; over the noisy priorities (Guided Search 2's rule) rather than the
          ;; soft Luce competition that section 5.4 uses for covert selection.
          ;; With the Luce pick the target wins only about 87 percent of the
          ;; time in feature search, below the 95 percent phase 3 asks for.
          (let* ((pick (gs-best-by-priority icons))
                 (loc (construct-location vis-mod (gsi-chunk pick) chunk-spec))
                 (vl-loc (convert-visicon-chunk-to-vis-loc loc)))
            (setf (loc-failure vis-mod) nil)
            (gs-trace "GS-SELECT ~a priority ~,3f (guided)"
                      (gsi-chunk pick) (gsi-priority pick))
            (schedule-set-buffer-chunk 'visual-location vl-loc
                                       (select-interval vis-mod)
                                       :time-in-ms t :module :vision :priority 10)
            (lock-vision vis-mod)
            (schedule-event-relative (select-interval vis-mod) 'unlock-vision
                                     :time-in-ms t :module :vision :destination :vision
                                     :priority 9 :output nil :maintenance t)
            loc))))))

(defmethod find-location ((vis-mod gs-vision-module) chunk-spec)
  (if (gs-guided-request-p vis-mod chunk-spec)
      (gs-guided-find-location vis-mod chunk-spec)
    (call-next-method)))

;;; ------------------------------------------------------------------
;;; Encoding
;;; ------------------------------------------------------------------

(defmethod encoding-complete :after ((vis-mod gs-vision-module) loc position scale
                                     &key (requested t))
  (declare (ignore loc position scale requested))
  (bt:with-recursive-lock-held ((gs-lock vis-mod))
    (when (search-active vis-mod) (gs-end-search vis-mod))))

;;; ------------------------------------------------------------------
;;; Commands for the Python harness (section 6)
;;; ------------------------------------------------------------------

(defun gs-fixation-log-command ()
  "Oldest-first list of (time-ms x y duration-ms)."
  (let ((v (get-module :vision)))
    (when (typep v 'gs-vision-module)
      (reverse (fixation-log v)))))

(defun gs-event-log-command ()
  (reverse (event-log (get-module :vision))))

(defun gs-cancel-search-command ()
  "Close and cancel a timed-out trial, preserving its diagnostics."
  (gs-quit-search (get-module :vision) 'timeout))

(defun gs-benchmark-gaze-command (x y)
  "Untimed fixation-cross placement. Reset preparation history, retain learning."
  (let ((v (get-module :vision)))
    (gs-set-eye v x y)
    (setf (last-saccade v) nil)
    t))

(defun gs-search-stats-command ()
  "(fixations rejections elapsed-ms quit-reason) for the last search."
  (let ((v (get-module :vision)))
    (when (typep v 'gs-vision-module)
      (list (n-fixations v) (rejections v) (search-elapsed v)
            (string-downcase (princ-to-string (or (quit-reason v) 'none)))))))

(defun gs-reset-search-command ()
  "Clear the per-trial state without a full model reset.

run_batch.py uses this between trials so that the adaptive threshold, the
priming traces and the prevalence window survive, as section 8.2 requires.

It also puts the module back into the free state.  A trial that is cut short
mid-search -- an experiment timeout, say -- leaves EXEC busy, and every later
trial's search production would then be blocked on ?visual> state free.  One
abandoned trial would silently take the rest of the block with it."
  (let ((v (get-module :vision)))
    (when (typep v 'gs-vision-module)
      (bt:with-recursive-lock-held ((gs-lock v))
        (gs-clear-search v)
        (setf (search-result v) 'none
              (search-elapsed v) 0)
        (bt:with-recursive-lock-held ((marker-lock v))
          (setf (attend-failure v) nil
                (loc-failure v) nil))
        (change-state v :exec 'free :proc 'free)
        t))))

(defun gs-state-command ()
  "Adaptive state, for logging: (quit-threshold prevalence n-feedbacks)."
  (let ((v (get-module :vision)))
    (when (typep v 'gs-vision-module)
      (list (quit-threshold v) (gs-prevalence v) (length (feedback-log v))))))

(dolist (c '(("gs-fixation-log" gs-fixation-log-command
              "Fixations of the last search as (time x y duration). No params.")
             ("gs-event-log" gs-event-log-command "Timestamped search events. No params.")
             ("gs-cancel-search" gs-cancel-search-command "Cancel a timeout and retain diagnostics.")
             ("gs-benchmark-gaze" gs-benchmark-gaze-command "Untimed fixation cross. Params: x y.")
             ("gs-search-stats" gs-search-stats-command
              "Last search as (fixations rejections elapsed-ms quit-reason). No params.")
             ("gs-reset-search" gs-reset-search-command
              "Clear per-trial search state, keeping adaptive state. No params.")
             ("gs-state" gs-state-command
              "Adaptive state as (quit-threshold prevalence n-feedbacks). No params.")))
  (unless (check-act-r-command (first c))
    (add-act-r-command (first c) (second c) (third c))))

;;; ------------------------------------------------------------------
;;; Redefine the module
;;; ------------------------------------------------------------------

(defun gs-capture-vision-parameters ()
  "Rebuild the stock :vision parameter list from the live parameter table.

Copying the DEFINE-PARAMETER forms out of vision.lisp would make this file a
derivative of ACT-R's LGPL source and would go stale on the next upstream
release (handoff section 12, decision 4).  Reading the registered structs does
neither.  Must be called before UNDEFINE-MODULE, which drops them."
  (let (owned watched)
    (bt:with-lock-held (*parameters-table-lock*)
      (maphash
       (lambda (name param)
         (cond ((eq (act-r-parameter-owner param) :vision)
                (push (list name
                            (act-r-parameter-test param)
                            (act-r-parameter-default param)
                            (act-r-parameter-warning param)
                            (act-r-parameter-details param))
                      owned))
               ((member :vision (act-r-parameter-users param))
                (push name watched))))
       *act-r-parameters-table*))
    (append
     (mapcar (lambda (p)
               (destructuring-bind (name test default warning details) p
                 (define-parameter name :owner t :valid-test test
                                        :default-value default :warning warning
                                        :documentation details)))
             (sort owned #'string< :key (lambda (p) (symbol-name (first p)))))
     (mapcar (lambda (name) (define-parameter name :owner nil))
             (sort watched #'string< :key #'symbol-name)))))

(defun gs-install-module ()
  "Replace :vision with the guided-search subclass.  Idempotent."
  (if (mp-models)
      (print-warning "gs-vision cannot replace the vision module while models exist. ~
                      Load gs-vision before any clear-all or define-model.")
    (let ((stock (gs-capture-vision-parameters)))
      (undefine-module :vision)
      (define-module-fct :vision
          (list (define-buffer-fct 'visual-location
                    :request-params (list :attended :nearest :center :guided)
                  :queries '(attended)
                  :status-fn 'visual-location-status)
                (define-buffer-fct 'visual
                    :queries '(scene-change-value scene-change modality preparation
                               execution processor last-command search-result)
                  :status-fn 'gs-visual-buffer-status))
        (append stock (gs-parameter-list))
        :version (version-string (make-instance 'gs-vision-module))
        :documentation "Guided-search vision module (GS6 + CGS + PAAV + EMMA)"
        :creation 'create-gs-vision-module
        :reset '(reset-gs-vision-module dont-query-vis-loc)
        :query 'gs-query-vision-module
        :request 'pm-module-request
        :params 'gs-vision-params
        :warning 'warn-vision)
      t)))

(gs-install-module)
