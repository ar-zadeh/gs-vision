;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; legacy-check-model.lisp -- a tutorial unit 3 style model that uses none of
;;; the guided-search API.
;;;
;;; Its whole job is to fail loudly if the subclass changed the stock
;;; behaviour.  It uses the classic sequence -- an unattended visual-location
;;; request, a move-attention, a keypress -- and it must produce exactly the
;;; same trace under the stock vision module and under gs-vision, with
;;; :gs-enabled either t or nil.  tests/test_backcompat.py diffs those traces,
;;; and also runs the real tutorial unit 2 and unit 3 models the same way.
;;;
;;; Deliberately no EMMA here: EMMA changes the timing of a stock model too,
;;; and this file is about the subclass, not about the extra.

(clear-all)

(define-model legacy-check

  (sgp :v t :trace-detail high :seed (100 0) :show-focus t)

  (chunk-type read-letters step)

  (define-chunks (start name start) (find-location name find-location)
                 (attend name attend) (respond name respond) (done name done))

  (define-chunks (goal isa read-letters step start))
  (goal-focus goal)

  (p find-unattended-letter
     =goal>
       isa       read-letters
       step      start
     ==>
     +visual-location>
       :attended nil
     =goal>
       step      find-location)

  (p attend-letter
     =goal>
       isa        read-letters
       step       find-location
     =visual-location>
     ?visual>
       state      free
     ==>
     +visual>
       cmd        move-attention
       screen-pos =visual-location
     =goal>
       step       attend)

  (p encode-letter
     =goal>
       isa       read-letters
       step      attend
     =visual>
       value     =letter
     ==>
     !output!    ("saw ~s" =letter)
     =goal>
       step      respond)

  (p respond
     =goal>
       isa       read-letters
       step      respond
     ?manual>
       state     free
     ==>
     +manual>
       cmd       press-key
       key       "k"
     =goal>
       step      done)

  (p look-again
     =goal>
       isa       read-letters
       step      done
     ==>
     +visual-location>
       :attended nil
     =goal>
       step      find-location)
)
