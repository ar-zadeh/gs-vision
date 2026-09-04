;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; test_module_events.lisp -- unit tests for the gs-vision module.
;;;
;;;     sbcl --non-interactive --load tests/test_module_events.lisp
;;;
;;; Exits 0 when everything passes and 1 otherwise, so it can be wired into
;;; CI.  It loads gs-vision itself; do not load anything first.
;;;
;;; Covers scheduling, inhibition of return, both quit rules, buffer states,
;;; the channel and acuity rules, the Wald sampler, the guided location
;;; request, and that a legacy request path is untouched.

(load (merge-pathnames "../gs-vision/load-gs-vision.lisp"
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
;;; Fixtures
;;; ------------------------------------------------------------------

(defparameter *cx* 512)
(defparameter *cy* 384)

(defun deg->px (d)
  "Same conversion as harness/tasks.py, i.e. ACT-R's pm-angle-to-pixels."
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
    (-4.5 4.5) (0.0 9.0) (4.5 4.5) (9.0 0.0) (-9.0 9.0) (9.0 9.0))
  "A fixed 12-item layout on the 22.5 degree field.")

(defun feature-display (n target-present)
  (let ((out nil))
    (dotimes (i n (nreverse out))
      (destructuring-bind (dx dy) (nth i *positions*)
        (push (if (and target-present (= i 2))
                  (feat dx dy 'red 0 0 'bar)
                (feat dx dy 'green 120 0 'bar))
              out)))))

(defun spatial-display (n target-present)
  (let ((out nil))
    (dotimes (i n (nreverse out))
      (destructuring-bind (dx dy) (nth i *positions*)
        (push (digit-feat dx dy (if (and target-present (= i 2)) 'two 'five)) out)))))

(defun new-test-model ()
  (clear-all)
  (eval '(define-model gs-unit-test
          (sgp :v nil :emma t :gs-enabled t :seed (42 0))
          (chunk-type probe state)
          (define-chunks (goal isa probe state idle))
          (goal-focus goal))))

(defun run-search (features template &key (limit 25) (stop 'both))
  "Start one gs-search from Lisp and run until it finishes."
  (delete-all-visicon-features)
  (gs-reset-search-command)
  (apply #'add-visicon-features features)
  (run 0.05)                                     ; let proc-display finish
  (let ((v (get-module :vision)))
    (gs-start-search v template nil stop nil)
    (run limit)
    v))

;;; ------------------------------------------------------------------
;;; 1. Installation
;;; ------------------------------------------------------------------

(format t "~%== installation ==~%")
(new-test-model)
(let ((v (get-module :vision)))
  (check "the vision module is the guided-search subclass"
         (typep v 'gs-vision-module) (type-of v))
  (check "its version is GS-1.0" (string= (version-string v) "GS-1.0"))
  (check "the visual-location buffer still exists" (buffer-exists 'visual-location))
  (check "the visual buffer still exists" (buffer-exists 'visual))
  (check "a stock parameter survived the redefinition"
         (close-to (car (no-output (sgp :visual-attention-latency))) 0.085 1e-6))
  (check "an unowned stock parameter survived"
         (numberp (car (no-output (sgp :viewing-distance))))))

(format t "~%== parameter defaults (handoff section 6) ==~%")
(dolist (spec '((:gs-enabled t) (:gs-select-interval 0.05) (:gs-diffuser-capacity 5)
                (:gs-choice-beta 4.0) (:gs-id-drift 0.25) (:gs-id-threshold 0.03)
                (:gs-quit-delta 0.02) (:gs-memory 4) (:gs-attn-fvf 8.0)
                (:gs-explore-fvf 12.0) (:gs-max-fixation 0.4) (:gs-iconic-span 4.0)
                (:gs-acuity-sigma 0.5) (:gs-w-bu 0.5) (:gs-w-td 1.0) (:gs-w-h 0.3)
                (:gs-w-v 0.0) (:gs-w-s 1.0) (:gs-w-e 0.02) (:gs-noise 0.2)
                (:gs-priming-tau 10.0) (:gs-qt-init 1.0) (:gs-qt-step 0.05)
                (:gs-error-goal 0.08) (:gs-feedback-window 50) (:gs-log-fixations t)))
  (destructuring-bind (name want) spec
    (let ((got (car (no-output (sgp-fct (list name))))))
      (check (format nil "~a defaults to ~a" name want)
             (if (numberp want) (close-to got want 1e-6) (eql got want)) got))))

;;; ------------------------------------------------------------------
;;; 2. Channels and acuity
;;; ------------------------------------------------------------------

(format t "~%== channels (section 5.1) ==~%")
(let ((v (get-module :vision)))
  (setf (display-ranges v) '(size (3.5 . 3.5) lum (0.5 . 0.5)))
  (check "vertical is steep" (equal (gs-orient-channels 0) '((steep . 1.0))))
  (check "horizontal is shallow" (equal (gs-orient-channels 90) '((shallow . 1.0))))
  (check "-45 is left" (equal (gs-orient-channels -45) '((left . 1.0))))
  (check "45 is right" (equal (gs-orient-channels 45) '((right . 1.0))))
  (let ((ramped (gs-orient-channels 20)))
    (check "a near-boundary orientation drives two channels"
           (= 2 (length ramped)) ramped)
    (check "the ramped activations sum to 1"
           (close-to (reduce #'+ ramped :key #'cdr) 1.0 1e-5)))
  (check "hue 0 is the red channel" (equal (gs-color-channels nil 0) '((red . 1.0))))
  (check "hue 120 is the green channel"
         (equal (gs-color-channels nil 120) '((green . 1.0))))
  (check "dark-green folds onto green"
         (equal (gs-color-channels 'dark-green nil) '((green . 1.0))))
  (check "an unknown colour becomes its own channel"
         (equal (gs-color-channels 'chartreuse nil) '((chartreuse . 1.0))))
  (check "identical channels overlap fully"
         (close-to (gs-channel-overlap '((red . 1.0)) '((red . 1.0))) 1.0 1e-6))
  (check "disjoint channels do not overlap"
         (close-to (gs-channel-overlap '((red . 1.0)) '((green . 1.0))) 0.0 1e-6))
  (check "a degenerate size range gives the middle channel"
         (equal (gs-tercile-channels 3.5 '(3.5 . 3.5) *gs-size-names*)
                '((medium . 1.0)))))

(format t "~%== acuity (section 5.2) ==~%")
(check "the normal CDF is 0.5 at zero" (close-to (gs-normal-cdf 0.0) 0.5 1e-4))
(check "the normal CDF is about 0.9772 at 2" (close-to (gs-normal-cdf 2.0) 0.9772 1e-3))
(let* ((s 2.25) (sigma 0.5)
       (p-near (gs-normal-cdf (/ (- s (* 0.40 2.0)) sigma)))
       (p-far (gs-normal-cdf (/ (- s (* 0.40 10.0)) sigma))))
  (check "shape is available near the fovea" (> p-near 0.99) p-near)
  (check "shape is unavailable in the periphery" (< p-far 0.01) p-far)
  (check "colour survives where shape does not"
         (> (gs-normal-cdf (/ (- s (* 0.10 10.0)) sigma)) 0.99)))

(format t "~%== samplers ==~%")
(let* ((mean 0.12) (shape (/ (* 0.03 0.03) (* 0.1 0.1)))
       (draws (loop repeat 4000 collect (gs-wald mean shape))))
  (check "the Wald sampler has the right mean"
         (close-to (/ (reduce #'+ draws) (length draws)) mean 0.02)
         (/ (reduce #'+ draws) (length draws)))
  (check "the Wald sampler is non-negative" (every (lambda (x) (>= x 0)) draws))
  (check "the Wald distribution is right-skewed"
         (> (reduce #'max draws) (* 3 mean))))
(let ((draws (loop repeat 4000 collect (gs-standard-normal))))
  (check "the unit normal has SD near 1"
         (close-to (sqrt (/ (reduce #'+ draws :key (lambda (x) (* x x)))
                            (length draws)))
                   1.0 0.06)))

;;; ------------------------------------------------------------------
;;; 3. Search behaviour
;;; ------------------------------------------------------------------

(format t "~%== a hit (section 5.4) ==~%")
(new-test-model)
(let ((v (run-search (feature-display 12 t) '(color red))))
  (check "the search reports found" (eq (search-result v) 'found) (search-result v))
  (check "the visual buffer holds a chunk" (buffer-read 'visual))
  (check "the query search-result found is true"
         (gs-query-vision-module v 'visual 'search-result 'found))
  (check "the query search-result failed is false"
         (not (gs-query-vision-module v 'visual 'search-result 'failed)))
  (check "state error is false after a hit"
         (not (gs-query-vision-module v 'visual 'state 'error)))
  (check "the module is free again"
         (gs-query-vision-module v 'visual 'state 'free))
  (check "the attended chunk is the red one"
         (let ((c (buffer-read 'visual)))
           (and c (eq (chunk-slot-value-fct c 'color) 'red)))
         (awhen (buffer-read 'visual) (chunk-slot-value-fct it 'color)))
  (check "no gs events are left scheduled"
         (and (null (select-event v)) (null (sacc-event v))
              (null (diffuser v))))
  (let ((stats (gs-search-stats-command)))
    (check "gs-search-stats returns four values" (= 4 (length stats)) stats)
    (check "the quit reason of a hit is hit" (string= (fourth stats) "hit") stats)
    (check "the elapsed time is positive" (plusp (third stats)) stats)))

(format t "~%== a quit (sections 5.6 and 3) ==~%")
(new-test-model)
(let ((v (run-search (feature-display 12 nil) '(color red))))
  (check "the search reports failed" (eq (search-result v) 'failed) (search-result v))
  (check "the visual buffer is empty, not holding a failure chunk"
         (null (buffer-read 'visual)))
  (check "state error is true" (gs-query-vision-module v 'visual 'state 'error))
  (check "the query search-result failed is true"
         (gs-query-vision-module v 'visual 'search-result 'failed))
  (check "the module is free" (gs-query-vision-module v 'visual 'state 'free))
  (check "something was rejected before quitting" (plusp (rejections v))
         (rejections v))
  (check "the quit reason is one of the two rules"
         (member (quit-reason v) '(cgs threshold no-candidate))
         (quit-reason v)))

(format t "~%== inhibition of return (section 5.4) ==~%")
(new-test-model)
(sgp :gs-memory 3)
(let ((v (run-search (spatial-display 12 nil) '(shape two))))
  (check "the IOR ring never exceeds :gs-memory"
         (<= (length (rejected v)) 3) (length (rejected v)))
  (check "more items were rejected than the ring can hold, so items recur"
         (> (rejections v) 3) (rejections v)))
(sgp :gs-memory 4)

(format t "~%== the two quit rules can be selected (section 5.7) ==~%")
(new-test-model)
(let ((v (run-search (feature-display 12 nil) '(color red) :stop 'cgs)))
  (check "stop cgs quits by the competitive rule"
         (member (quit-reason v) '(cgs no-candidate)) (quit-reason v)))
(new-test-model)
(sgp :gs-qt-init 0.5)
(let ((v (run-search (feature-display 12 nil) '(color red) :stop 'adaptive)))
  (check "stop adaptive quits by the threshold"
         (member (quit-reason v) '(threshold no-candidate)) (quit-reason v)))

(format t "~%== eye movements (section 5.5) ==~%")
(new-test-model)
(let ((v (run-search (spatial-display 12 t) '(shape two))))
  (check "an unguided shape search makes saccades" (plusp (n-fixations v))
         (n-fixations v))
  (let ((log (gs-fixation-log-command)))
    (check "the fixation log has one entry per fixation"
           (= (length log) (n-fixations v)) (list (length log) (n-fixations v)))
    (check "every fixation has time, x, y and duration"
           (every (lambda (f) (= 4 (length f))) log))
    (check "no fixation lands outside the display"
           (every (lambda (f) (and (< 100 (second f) 950) (< 50 (third f) 750))) log)
           (subseq log 0 (min 3 (length log))))))

(format t "~%== guidance (section 10, phase 3) ==~%")
(new-test-model)
(let ((hits 0) (n 60))
  (dotimes (i n)
    (let ((v (run-search (feature-display 12 t) '(color red))))
      (when (and (eq (search-result v) 'found)
                 (let ((c (buffer-read 'visual)))
                   (and c (eq (chunk-slot-value-fct c 'color) 'red))))
        (incf hits))))
  (check "feature search finds the target on at least 90 percent of trials"
         (>= hits (* 0.90 n)) (format nil "~d/~d" hits n)))

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

(format t "~%== feedback and the adaptive threshold (section 5.6) ==~%")
(new-test-model)
(let* ((v (get-module :vision))
       (before (quit-threshold v)))
  (gs-feedback v 'tn)
  (check "a true negative lowers the quitting threshold"
         (< (quit-threshold v) before) (list before (quit-threshold v)))
  (let ((mid (quit-threshold v)))
    (gs-feedback v 'miss)
    (check "a miss raises it, and by much more than a true negative lowers it"
           (> (quit-threshold v) (+ mid 0.5)) (list mid (quit-threshold v))))
  (check "prevalence is 0.5 until ten feedbacks exist"
         (close-to (gs-prevalence v) 0.5 1e-6))
  (dotimes (i 12) (gs-feedback v 'tn))
  (check "prevalence follows the feedback window"
         (< (gs-prevalence v) 0.3) (gs-prevalence v))
  (check "the feedback window is capped"
         (<= (length (feedback-log v)) 50) (length (feedback-log v))))

(format t "~%== priming (section 5.3) ==~%")
(new-test-model)
(let ((v (get-module :vision)))
  (check "an unseen value has no trace"
         (close-to (gs-trace-value v (cons 'color 'red) 0.0) 0.0 1e-9))
  (gs-bump-trace v (cons 'color 'red) 0.0)
  (check "a bumped trace is 1" (close-to (gs-trace-value v (cons 'color 'red) 0.0) 1.0 1e-6))
  (check "the trace decays with the priming time constant"
         (close-to (gs-trace-value v (cons 'color 'red) 10.0) (exp -1.0) 1e-3)
         (gs-trace-value v (cons 'color 'red) 10.0)))

;;; ------------------------------------------------------------------
;;; 4. The guided location request and the legacy path
;;; ------------------------------------------------------------------

(format t "~%== the guided location request (section 5.7) ==~%")
(new-test-model)
(let ((hits 0) (n 40))
  (dotimes (i n)
    (delete-all-visicon-features)
    (gs-reset-search-command)
    (apply #'add-visicon-features (feature-display 12 t))
    (run 0.05)
    (eval '(pm-module-request (get-module :vision) 'visual-location
            (define-chunk-spec color red :guided t)))
    (run 1)
    (let ((c (buffer-read 'visual-location)))
      (when (and c (eq (chunk-slot-value-fct c 'color) 'red)) (incf hits)))
    (clear-buffer 'visual-location))
  (check "a guided location request returns the red item at least 90 percent of the time"
         (>= hits (* 0.90 n)) (format nil "~d/~d" hits n)))

(format t "~%== the legacy path is untouched (section 4) ==~%")
(new-test-model)
(delete-all-visicon-features)
(apply #'add-visicon-features (feature-display 12 t))
(run 0.05)
(eval '(pm-module-request (get-module :vision) 'visual-location
        (define-chunk-spec color green)))
(run 1)
(let ((c (buffer-read 'visual-location)))
  (check "a plain location request still filters exactly"
         (and c (eq (chunk-slot-value-fct c 'color) 'green))
         (awhen c (chunk-slot-value-fct it 'color)))
  (check "a plain location request does not start a search"
         (not (search-active (get-module :vision)))))

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
         (not (search-active v)))
  (check "with :gs-enabled nil the search result stays none"
         (eq (search-result v) 'none) (search-result v)))

;;; ------------------------------------------------------------------

(format t "~%~%========================================~%")
(format t "passed ~d, failed ~d~%" *pass* *fail*)
(dolist (f (reverse *failures*)) (format t "  FAILED: ~a~%" f))
(finish-output)
(sb-ext:exit :code (if (zerop *fail*) 0 1) :abort t)
