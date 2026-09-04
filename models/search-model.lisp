;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; search-model.lisp -- the benchmark model for the three Wolfe, Palmer and
;;; Horowitz (2010) tasks, driven through the guided-search buffer API.
;;;
;;; Load gs-vision/load-gs-vision.lisp first; this file only defines the model.
;;;
;;; Every trial is: one production issues the search, the module runs
;;; selection, identification, saccades and quitting on its own events, one
;;; production reads the result and presses a key, and one production reports
;;; the outcome back so the adaptive quitting threshold and the priming traces
;;; can learn.  Those three productions are the 50 ms each that section 11 of
;;; the handoff says must show up in the intercept and must not be tuned away.
;;;
;;; The harness sets up each trial with two remote commands defined at the
;;; bottom of this file: GS-TRIAL-SETUP and GS-TRIAL-FEEDBACK.

(clear-all)

(define-model gs-search-model

  (sgp :v nil :trace-detail medium :er t
       :emma t :gs-enabled t
       :show-focus t :eye-spot-color blue
       :visual-num-finsts 4 :visual-finst-span 3.0)

  ;; --- knowledge -----------------------------------------------------
  (chunk-type trial task state target-color target-orient target-shape outcome)

  ;; Guarded, because some of these already exist: the vision module defines
  ;; its channel names and ACT-R's audio module already knows DIGIT.
  (dolist (c '(start searching responded waiting done
               feature conjunction spatial
               bar digit two five))          ; display vocabulary from tasks.py
    (unless (chunk-p-fct c) (define-chunks-fct `((,c name ,c)))))

  (define-chunks (goal isa trial task feature state waiting))
  (goal-focus goal)

  ;; --- issue the search ----------------------------------------------
  ;; One production per task.  A single production cannot do it because a
  ;; request slot with a nil value is not the same as an absent slot, and the
  ;; three templates have different numbers of slots.

  (p search-feature
     =goal>
       isa          trial
       task         feature
       state        start
       target-color =c
     ?visual>
       state        free
     ==>
     +visual>
       isa          gs-search
       color        =c
     =goal>
       state        searching)

  (p search-conjunction
     =goal>
       isa           trial
       task          conjunction
       state         start
       target-color  =c
       target-orient =o
     ?visual>
       state         free
     ==>
     +visual>
       isa           gs-search
       color         =c
       orient        =o
     =goal>
       state         searching)

  (p search-spatial
     =goal>
       isa           trial
       task          spatial
       state         start
       target-shape  =s
     ?visual>
       state         free
     ==>
     +visual>
       isa           gs-search
       shape         =s
     =goal>
       state         searching)

  ;; --- respond ---------------------------------------------------------
  ;; A hit puts the object in the visual buffer.  A quit leaves it empty with
  ;; state error, exactly like a retrieval failure, because a buffer cannot
  ;; hold a chunk and a failure flag at once.

  (p respond-present
     =goal>
       isa      trial
       state    searching
     =visual>
     ?manual>
       state    free
     ==>
     +manual>
       cmd      press-key
       key      "j"
     -visual>
     =goal>
       state    responded)

  (p respond-absent
     =goal>
       isa      trial
       state    searching
     ?visual>
       state    error
     ?manual>
       state    free
     ==>
     +manual>
       cmd      press-key
       key      "f"
     =goal>
       state    responded)

  ;; --- report the outcome ------------------------------------------------
  ;; The observer cannot know whether a response was right; the experiment
  ;; tells it.  GS-TRIAL-FEEDBACK writes the outcome into the goal and this
  ;; production passes it to the module through the documented buffer API.

  (p report-outcome
     =goal>
       isa      trial
       state    responded
       outcome  =o
     ?visual>
       state    free
     ==>
     +visual>
       isa      gs-feedback
       outcome  =o
     =goal>
       state    waiting
       outcome  nil)
)

;;; ------------------------------------------------------------------
;;; Trial control, for harness/run_batch.py
;;; ------------------------------------------------------------------

(defun gs-trial-setup (task color orient shape)
  "Arm the goal for one trial.  Values arrive as strings over the dispatcher."
  (let ((task (string->name task))
        (color (and color (string->name color)))
        (orient (and orient (string->name orient)))
        (shape (and shape (string->name shape))))
    (dolist (c (remove nil (list task color orient shape)))
      (unless (chunk-p-fct c) (define-chunks-fct `((,c name ,c)))))
    (mod-focus-fct (list 'task task 'state 'start 'outcome nil
                         'target-color color 'target-orient orient
                         'target-shape shape))
    t))

(defun gs-trial-feedback (outcome)
  "Write the trial outcome into the goal so REPORT-OUTCOME can pass it on."
  (let ((o (string->name outcome)))
    (if (member o '(hit miss fa tn))
        (progn (mod-focus-fct (list 'state 'responded 'outcome o)) t)
      (print-warning "gs-trial-feedback expects hit, miss, fa or tn, not ~s." outcome))))

(dolist (c '(("gs-trial-setup" gs-trial-setup
              "Arm the model for one trial. Params: task color orient shape.")
             ("gs-trial-feedback" gs-trial-feedback
              "Report a trial outcome to the model. Params: outcome.")))
  (unless (check-act-r-command (first c))
    (add-act-r-command (first c) (second c) (third c))))
