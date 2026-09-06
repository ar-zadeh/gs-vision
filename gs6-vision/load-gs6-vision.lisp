;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER -*-
;;; load-gs6-vision.lisp -- the single entry point of gs6-vision.
;;;
;;;     sbcl --load G:/VisualSearchModeling/gs6-vision/load-gs6-vision.lisp
;;;
;;; Loads ACT-R, then EMMA, then the module, and replaces :vision while no
;;; model exists.  UNDEFINE-MODULE prints a warning and does nothing once a
;;; model has been defined, so nothing may call CLEAR-ALL or DEFINE-MODEL
;;; before this file finishes.
;;;
;;; Models then set (sgp :emma t :gs-enabled t).

(in-package :cl-user)

(defvar *gs-root*
  (namestring (make-pathname :name nil :type nil
                             :defaults (or *load-truename*
                                           *default-pathname-defaults*))))

(load (merge-pathnames "../actr7.x/load-act-r.lisp" *gs-root*))

(require-extra "emma")

(dolist (f '("gs-params" "gs-priority" "gs-diffuser" "gs-eye" "gs-vision"))
  (load (merge-pathnames (format nil "~a.lisp" f) *gs-root*)))

;;; Remote command so harness/run_batch.py can stop this Lisp cleanly.
(unless (check-act-r-command "gs-quit-lisp")
  (add-act-r-command "gs-quit-lisp"
                     (lambda () (sb-ext:exit :abort t))
                     "Exit SBCL. No params."))

(format t "~%######### gs6-vision loaded: :vision is now ~a #########~%"
        (let ((m (bt:with-recursive-lock-held ((act-r-modules-lock *modules-lookup*))
                   (gethash :vision (act-r-modules-table *modules-lookup*)))))
          (if m (act-r-module-version m) "NOT INSTALLED")))
(finish-output)
