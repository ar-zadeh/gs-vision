;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; test_gs6_events.lisp -- unit tests for the gs6-vision module.
;;;
;;;     sbcl --non-interactive --load tests/test_gs6_events.lisp
;;;
;;; Exits 0 when everything passes and 1 otherwise.  It loads gs6-vision
;;; itself; do not load anything first.
;;;
;;; Covers the GS6 parameter defaults, the Guided Search 2 orientation
;;; channels and best-channel rule, the asynchronous diffuser (timing with the
;;; noise switched off, emergent false alarms with it turned up), the quit
;;; signal, the GS6 feedback rules, memory-free reselection, eye movements,
;;; guidance, and the buffer states of a hit and a quit.

(load (merge-pathnames "../gs6-vision/load-gs6-vision.lisp"
                       (or *load-truename* *default-pathname-defaults*)))

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* nil)

(defun check (name ok &optional detail)
  (if ok
      (progn (incf *pass*) (format t "  ok   ~a~%" name))
    (progn (incf *fail*)
           (push (format nil "~a~@[ -- ~a~]" name detail) *failures*)
           (format t "  FAIL ~a~@[ -- ~a~]~%" name detail))))

(defun close-to (a b tol) (and (numberp a) (numberp b) (<= (abs (- a b)) tol)))

;;; ------------------------------------------------------------------
;;; Fixtures (same displays as tests/test_module_events.lisp)
;;; ------------------------------------------------------------------

(defparameter *cx* 512)
(defparameter *cy* 384)

(defun deg->px (d)
  (round (* 2 1080 (tan (/ (* pi (/ d 2.0)) 180.0)))))

(defun feat (dx dy color hue orient shape)
  (list 'isa '(gs-feature)
        'screen-x (+ *cx* (deg->px dx)) 'screen-y (+ *cy* (deg->px dy))
        'kind 'bar 'color color 'hue hue 'orient orient 'lum 0.5
        'shape shape 'value shape
        'width (deg->px 1.0) 'height (deg->px 3.5) 'size 3.5))

(defun digit-feat (dx dy shape)
  (list 'isa '(gs-feature)
        'screen-x (+ *cx* (deg->px dx)) 'screen-y (+ *cy* (deg->px dy))
        'kind 'digit 'color 'white 'hue 0 'orient 0 'lum 0.9
        'shape shape 'value shape
        'width (deg->px 1.5) 'height (deg->px 2.7) 'size 4.05))

(defparameter *positions*
  '((-9.0 -9.0) (-4.5 -4.5) (0.0 -9.0) (4.5 -4.5) (9.0 -9.0) (-9.0 0.0)
    (-4.5 4.5) (0.0 9.0) (4.5 4.5) (9.0 0.0) (-9.0 9.0) (9.0 9.0)))

(defparameter *near-positions*
  '((-3.0 -3.0) (0.0 -3.0) (3.0 -3.0) (-3.0 0.0) (3.0 0.0) (-3.0 3.0)
    (0.0 3.0) (3.0 3.0) (-6.0 0.0) (6.0 0.0) (0.0 -6.0) (0.0 6.0))
  "Twelve items inside the 8 degree attentional field, so no saccade is needed.")

(defun feature-display (n target-present &optional (positions *positions*))
  (let ((out nil))
    (dotimes (i n (nreverse out))
      (destructuring-bind (dx dy) (nth i positions)
        (push (if (and target-present (= i 2))
                  (feat dx dy 'red 0 0 'bar)
                (feat dx dy 'green 120 0 'bar))
              out)))))

(defun orient-display (n target-orient distractor-orient)
  "Same colour everywhere; item 2 has TARGET-ORIENT, the rest DISTRACTOR-ORIENT."
  (let ((out nil))
    (dotimes (i n (nreverse out))
      (destructuring-bind (dx dy) (nth i *near-positions*)
        (push (feat dx dy 'green 120 (if (= i 2) target-orient distractor-orient) 'bar) out)))))

(defun spatial-display (n target-present)
  (let ((out nil))
    (dotimes (i n (nreverse out))
      (destructuring-bind (dx dy) (nth i *positions*)
        (push (digit-feat dx dy (if (and target-present (= i 2)) 'two 'five)) out)))))

(defun new-test-model ()
  (clear-all)
  (eval '(define-model gs6-unit-test
          (sgp :v nil :emma t :gs-enabled t :seed (42 0))
          (chunk-type probe state)
          (define-chunks (goal isa probe state idle))
          (goal-focus goal))))

(defun run-search (features template &key (limit 25) (stop 'adaptive))
  "Start one gs-search from Lisp and run until it finishes."
  (delete-all-visicon-features)
  (gs-reset-search-command)
  (apply #'add-visicon-features features)
  (run 0.05)
  (let ((v (get-module :vision)))
    (gs-start-search v template nil stop nil)
    (run limit)
    v))

(defun elapsed-ms (v) (search-elapsed v))

;;; ------------------------------------------------------------------
;;; 1. Installation and defaults
;;; ------------------------------------------------------------------

(format t "~%== installation ==~%")
(new-test-model)
(let ((v (get-module :vision)))
  (check "the vision module is the guided-search subclass"
         (typep v 'gs-vision-module) (type-of v))
  (check "its version is GS6-1.0" (string= (version-string v) "GS6-1.0") (version-string v))
  (check "the visual-location buffer still exists" (buffer-exists 'visual-location))
  (check "the visual buffer still exists" (buffer-exists 'visual))
  (check "a stock parameter survived the redefinition"
         (close-to (car (no-output (sgp :visual-attention-latency))) 0.085 1e-6)))

(format t "~%== GS6 parameter defaults (GS6publicAsPostedJan2021.m) ==~%")
(dolist (spec '((:gs-select-interval 0.05) (:gs-diffuser-capacity 5)
                (:gs-diff-step 0.01) (:gs-diff-inc 0.05) (:gs-diff-noise 2.5)
                (:gs-targ-thresh 1.0) (:gs-dist-thresh -1.0) (:gs-similarity-drift 0.0)
                (:gs-start-prevalence t) (:gs-start-inc 0.0008) (:gs-start-dec 0.05)
                (:gs-quit-inc 0.018) (:gs-quit-noise 2.5) (:gs-qt-init 1.5)
                (:gs-quit-ss-ref 10.0) (:gs-qt-step 0.005) (:gs-error-goal 0.08)
                (:gs-memory 0) (:gs-orient-dual t) (:gs-best-channel t)
                (:gs-explore-proximity t) (:gs-attn-fvf 8.0) (:gs-noise 0.2)))
  (destructuring-bind (name want) spec
    (let ((got (car (no-output (sgp-fct (list name))))))
      (check (format nil "~a defaults to ~a" name want)
             (if (numberp want) (close-to got want 1e-6) (eql got want)) got))))
(check "the Wald parameters are gone"
       (not (numberp (ignore-errors (car (no-output (sgp-fct (list :gs-id-drift)))))))
       (ignore-errors (car (no-output (sgp-fct (list :gs-id-drift))))))

;;; ------------------------------------------------------------------
;;; 2. Guided Search 2 channels
;;; ------------------------------------------------------------------

(format t "~%== GS2 orientation channels ==~%")
(let ((v (get-module :vision)))
  (multiple-value-bind (o tl) (gs-orient-dual-channels 0)
    (check "vertical is steep" (equal o '((steep . 1.0))) o)
    (check "vertical has no tilt" (null tl) tl))
  (multiple-value-bind (o tl) (gs-orient-dual-channels 90)
    (check "horizontal is shallow" (equal o '((shallow . 1.0))) o)
    (check "horizontal has no tilt" (null tl) tl))
  (multiple-value-bind (o tl) (gs-orient-dual-channels 45)
    (check "45 degrees is half steep, half shallow"
           (and (close-to (cdr (assoc 'steep o)) 0.5 1e-6)
                (close-to (cdr (assoc 'shallow o)) 0.5 1e-6)) o)
    (check "45 degrees is fully right" (and (equal (mapcar #'car tl) '(right))
                                            (close-to (cdr (first tl)) 1.0 1e-6)) tl))
  (multiple-value-bind (o tl) (gs-orient-dual-channels -20)
    (check "-20 degrees is steep" (equal o '((steep . 1.0))) o)
    (check "-20 degrees is partly left"
           (and (eq (car (first tl)) 'left) (close-to (cdr (first tl)) (/ 15.0 17.5) 1e-4)) tl))
  (check "the exclusive binning is still available"
         (equal (gs-orient-channels 45) '((right . 1.0))))
  (check "a numeric template drives orient and tilt"
         (let ((tc (gs-template-channels v '(orient 20))))
           (and (equal (getf tc 'orient) '((steep . 1.0)))
                (eq (car (first (getf tc 'tilt))) 'right)))
         (gs-template-channels v '(orient 20)))
  (check "the channel name right names the tilt dimension"
         (equal (gs-template-channels v '(orient right)) '(tilt ((right . 1.0)))))
  (check "the channel name steep names the orient dimension"
         (equal (gs-template-channels v '(orient steep)) '(orient ((steep . 1.0)))))
  (check "tilt guides when orient guides" (member 'tilt (gs-guiding v))))

(format t "~%== GS2 best-channel rule ==~%")
(new-test-model)
(delete-all-visicon-features)
(gs-reset-search-command)
(apply #'add-visicon-features (orient-display 12 20 0))
(run 0.05)
(let ((v (get-module :vision)))
  (setf (template v) '(orient 20) (guide-set v) nil)
  (gs-refresh-iconic v)
  (gs-centre-eye v)
  (gs-draw-availability v)
  (gs-compute-priority v)
  (let* ((icons (gs-eligible v))
         (target (find 20 icons :key (lambda (i) (getf (gsi-raw i) 'orient))))
         (distractors (remove target icons)))
    (check "a 20 degree target among verticals is guided through the tilt channel"
           (and target (close-to (gsi-td target) 1.0 1e-6)) (and target (gsi-td target)))
    (check "the vertical distractors get no top-down guidance from tilt"
           (every (lambda (i) (< (gsi-td i) 0.51)) distractors)
           (mapcar #'gsi-td distractors))
    (check "the target holds the highest guidance"
           (eq target (gs-best-guidance icons)))))

;;; ------------------------------------------------------------------
;;; 3. The asynchronous diffuser
;;; ------------------------------------------------------------------

(format t "~%== diffuser timing with the noise switched off ==~%")
;; Choice temperature 50 makes the guided target the first selection with
;; certainty; at the default 4 a distractor goes first on about one trial in six.
(new-test-model)
(sgp :gs-diff-noise 1e-6 :gs-quit-noise 1e-6 :gs-noise 0.0 :gs-w-bu 0.0 :gs-choice-beta 50.0)
(let ((v (run-search (feature-display 12 t *near-positions*) '(color red))))
  (check "the target is found" (eq (search-result v) 'found) (search-result v))
  (check "twenty steps of 0.05 after the first selection at 50 ms: about 250 ms"
         (<= 240 (elapsed-ms v) 270) (elapsed-ms v))
  (check "no tick is left scheduled" (null (tick-event v)))
  (check "the diffuser is empty" (null (diffuser v))))
(let ((v (run-search (feature-display 12 nil *near-positions*) '(color red))))
  (check "an absent display quits by the quit signal"
         (eq (quit-reason v) 'threshold) (quit-reason v))
  (check "the first rejection at about 250 ms plus 9 quit steps of 0.018 to 0.15: about 340 ms"
         (<= 320 (elapsed-ms v) 370) (elapsed-ms v))
  (check "the quit signal exceeded this trial's threshold"
         (> (quit-sig v) (search-qt v)) (list (quit-sig v) (search-qt v)))
  (check "the effective set size of an absent feature display is 1"
         (close-to (search-n-eff v) 1.0 1e-6) (search-n-eff v))
  (check "the threshold is qt-init times n-eff over the reference set size"
         (close-to (search-qt v) 0.15 1e-6) (search-qt v)))
(sgp :gs-diff-noise 2.5 :gs-quit-noise 2.5 :gs-noise 0.2 :gs-w-bu 0.5 :gs-choice-beta 4.0)

(format t "~%== emergent false alarms ==~%")
(new-test-model)
(sgp :gs-diff-noise 40.0)
(let ((found 0) (green 0) (n 20))
  (dotimes (i n)
    (let ((v (run-search (feature-display 12 nil *near-positions*) '(color red))))
      (when (eq (search-result v) 'found)
        (incf found)
        (let ((c (buffer-read 'visual)))
          (when (and c (eq (chunk-slot-value-fct c 'color) 'green)) (incf green))))))
  (check "with huge step noise an absent display yields false alarms"
         (plusp found) (format nil "~d/~d" found n))
  (check "every false alarm delivered a green distractor" (= found green)
         (list found green)))
(sgp :gs-diff-noise 2.5)

(format t "~%== the start point ==~%")
(new-test-model)
(let ((v (get-module :vision)))
  (check "with prevalence 0.5 and no offset the start point is 0"
         (close-to (gs-start-point v) 0.0 1e-9) (gs-start-point v))
  (setf (start-offset v) 5.0)
  (check "the start point stays inside the bounds"
         (< (gs-start-point v) (targ-thresh v)) (gs-start-point v))
  (setf (start-offset v) 0.0)
  (sgp :gs-start-prevalence nil)
  (dotimes (i 12) (gs-feedback v 'tn))
  (setf (start-offset v) 0.0)
  (check "with :gs-start-prevalence nil the estimated prevalence does not move the start"
         (close-to (gs-start-point v) 0.0 1e-9) (gs-start-point v))
  (sgp :gs-start-prevalence t)
  (check "with :gs-start-prevalence t a low prevalence lowers the start"
         (< (gs-start-point v) -0.1) (gs-start-point v)))

;;; ------------------------------------------------------------------
;;; 4. Quitting, memory and feedback
;;; ------------------------------------------------------------------

(format t "~%== memory is the diffuser ==~%")
(new-test-model)
(let ((v (run-search (spatial-display 12 nil) '(shape two))))
  (check "the search quits" (eq (search-result v) 'failed) (search-result v))
  (check "the quit reason is the quit signal" (eq (quit-reason v) 'threshold) (quit-reason v))
  (check "with :gs-memory 0 nothing is held in the IOR ring" (null (rejected v)) (rejected v))
  (check "something was rejected before quitting" (plusp (rejections v)) (rejections v))
  (check "the visual buffer is empty, not holding a failure chunk"
         (null (buffer-read 'visual)))
  (check "state error is true" (gs-query-vision-module v 'visual 'state 'error))
  (check "the module is free" (gs-query-vision-module v 'visual 'state 'free)))
(sgp :gs-memory 3)
(let ((v (run-search (spatial-display 12 nil) '(shape two))))
  (check "the IOR ring never exceeds :gs-memory"
         (<= (length (rejected v)) 3) (length (rejected v))))
(sgp :gs-memory 0)

(format t "~%== the competitive unit is still available as an ablation ==~%")
(new-test-model)
(let ((v (run-search (feature-display 12 nil) '(color red) :stop 'cgs)))
  (check "stop cgs quits by the competitive rule"
         (member (quit-reason v) '(cgs no-candidate)) (quit-reason v)))

(format t "~%== GS6 feedback rules ==~%")
(new-test-model)
(let* ((v (get-module :vision))
       (before (quit-threshold v)))
  (gs-feedback v 'tn)
  (check "a true negative lowers the threshold by qt-step times prevalence"
         (close-to (quit-threshold v) (- before (* 0.005 0.5)) 1e-9)
         (list before (quit-threshold v)))
  (let ((mid (quit-threshold v)))
    (gs-feedback v 'miss)
    (check "a miss raises it by qt-step / (error-goal prev 2) times (1 - prev)"
           (close-to (quit-threshold v) (+ mid (* (/ 0.005 (* 0.08 0.5 2.0)) 0.5)) 1e-9)
           (list mid (quit-threshold v))))
  (check "a hit raises the start-point offset by start-inc"
         (progn (gs-feedback v 'hit) (close-to (start-offset v) 0.0008 1e-9))
         (start-offset v))
  (check "a false alarm lowers it by start-dec"
         (progn (gs-feedback v 'fa) (close-to (start-offset v) (- 0.0008 0.05) 1e-9))
         (start-offset v))
  (check "hits and false alarms leave the threshold alone"
         (close-to (quit-threshold v) (+ (- before 0.0025) (* (/ 0.005 0.08) 0.5)) 1e-9)
         (quit-threshold v))
  (check "prevalence is 0.5 until ten feedbacks exist"
         (close-to (gs-prevalence v) 0.5 1e-6))
  (dotimes (i 12) (gs-feedback v 'tn))
  (check "prevalence follows the feedback window"
         (< (gs-prevalence v) 0.3) (gs-prevalence v))
  (check "the feedback window is capped"
         (<= (length (feedback-log v)) 50) (length (feedback-log v))))

;;; ------------------------------------------------------------------
;;; 5. Eye movements, guidance and the buffer API
;;; ------------------------------------------------------------------

(format t "~%== eye movements ==~%")
(new-test-model)
(let ((v (run-search (spatial-display 12 t) '(shape two))))
  (check "an unguided shape search makes saccades" (plusp (n-fixations v))
         (n-fixations v))
  (let ((log (gs-fixation-log-command)))
    (check "the fixation log has one entry per fixation"
           (= (length log) (n-fixations v)) (list (length log) (n-fixations v)))
    (check "no fixation lands outside the display"
           (every (lambda (f) (and (< 100 (second f) 950) (< 50 (third f) 750))) log))))

(format t "~%== guidance ==~%")
(new-test-model)
(sgp :gs-qt-init 6.0)
(let ((hits 0) (red 0) (n 60))
  (dotimes (i n)
    (let ((v (run-search (feature-display 12 t) '(color red))))
      (when (eq (search-result v) 'found)
        (incf hits)
        (let ((c (buffer-read 'visual)))
          (when (and c (eq (chunk-slot-value-fct c 'color) 'red)) (incf red))))))
  (check "feature search finds the target on at least 90 percent of trials"
         (>= hits (* 0.90 n)) (format nil "~d/~d" hits n))
  (check "what it finds is the red item on at least 95 percent of hits"
         (>= red (* 0.95 hits)) (format nil "~d/~d" red hits)))
(sgp :gs-qt-init 1.5)

(new-test-model)
(let ((first-is-target 0) (n 60))
  (dotimes (i n)
    (delete-all-visicon-features)
    (gs-reset-search-command)
    (apply #'add-visicon-features (spatial-display 12 t))
    (run 0.05)
    (let* ((v (get-module :vision)))
      (setf (template v) '(shape two) (guide-set v) nil)
      (gs-refresh-iconic v)
      (gs-centre-eye v)
      (gs-draw-availability v)
      (gs-compute-priority v)
      (let ((best (gs-best-by-priority (gs-eligible v))))
        (when (and best (eq (getf (gsi-raw best) 'shape) 'two))
          (incf first-is-target)))))
  (check "2-vs-5 gives no guidance, so the winner is near chance"
         (< first-is-target (* 0.35 n))
         (format nil "~d/~d picked the target first" first-is-target n)))

(format t "~%== the buffer API ==~%")
(new-test-model)
(let ((v (get-module :vision)))
  (delete-all-visicon-features)
  (gs-reset-search-command)
  (apply #'add-visicon-features (feature-display 12 t *near-positions*))
  (run 0.05)
  (eval '(pm-module-request (get-module :vision) 'visual
          (define-chunk-spec isa gs-search color red)))
  (run 5)
  (check "a gs-search request through the buffer runs to a result"
         (member (search-result v) '(found failed)) (search-result v))
  (check "the default stop policy is the GS6 quit signal alone"
         (eq (search-stop v) 'adaptive) (search-stop v))
  (let ((stats (gs-search-stats-command)))
    (check "gs-search-stats returns four values" (= 4 (length stats)) stats))
  (check "gs-state reports the start-point offset as a fourth value"
         (= 4 (length (gs-state-command))) (gs-state-command)))

(new-test-model)
(sgp :gs-enabled nil)
(let ((v (get-module :vision)))
  (delete-all-visicon-features)
  (apply #'add-visicon-features (feature-display 12 t))
  (run 0.05)
  (eval '(pm-module-request (get-module :vision) 'visual
          (define-chunk-spec isa gs-search color red)))
  (run 1)
  (check "with :gs-enabled nil a gs-search is refused and starts nothing"
         (not (search-active v))))

;;; ------------------------------------------------------------------

(format t "~%~%========================================~%")
(format t "passed ~d, failed ~d~%" *pass* *fail*)
(dolist (f (reverse *failures*)) (format t "  FAILED: ~a~%" f))
(finish-output)
(sb-ext:exit :code (if (zerop *fail*) 0 1) :abort t)
