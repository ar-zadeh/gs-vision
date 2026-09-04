;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;
;;;;;;    ACT-R module for Pre-Attentive and Attentive Vision.
;;;;;;    Copyright (C) 2013  Enkhbold Nyamsuren
;;;;;;
;;;;;;    This program is free software: you can redistribute it and/or modify
;;;;;;    it under the terms of the GNU General Public License as published by
;;;;;;    the Free Software Foundation, either version 3 of the License, or any later version.
;;;;;;
;;;;;;    This program is distributed in the hope that it will be useful,
;;;;;;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;;;;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;;;;;    GNU General Public License for more details.
;;;;;;
;;;;;;    You should have received a copy of the GNU General Public License
;;;;;;    along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 
;;; Author          : Enkhbold Nyamsuren
;;; Contributors    :
;;;                   Ryan Hope (rmh3093 AT gmail DOT com)
;;; Last modified   : 2014.01.08
;;; Availability    : Free
;;; Copyright       : GNU General Public License
;;; Address         : Department of Artificial Intelligence 
;;;                 : University of Groningen
;;;                 : e.nyamsuren AT rug DOT nl
;;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 
;;; Filename        : paav-visual-module.lisp
;;; Version         : 0.98e
;;; 
;;; Description     : [TODO]
;;;                 : Pre-attentive And Attentive Vision - extends visual module
;;;
;;;
;;; Bugs            : [TODO]
;;;
;;; To do           : 1. Maybe have similarity between values of the same feature types:
;;;                            Example: (black vs gray) (rectangle vs square) (oval vs circle) (big vs medium) (medium vs small)
;;;                         
;;;                        
;;;                      1b. Validity test for the parameters.
;;;                   2b. Not all features can be visible at the moment of spreading activation.
;;;                      Spreading activation should be calculated only from visible chunks.
;;;                      [Extending visual module is required.]
;;;                   3b. Current implementation assumes that all types of features have same impact
;;;                      on spreading activation.
;;;                      Color VS Shape? Each feature type should have its own activation impact weight.
;;;                      [Extending visual module is required.]
;;;                   4b. Output with details of activation computation.
;;;                   5b. Parameter for choosing two chunk equality mode.
;;; 
;;; ----- History -----
;;; 2011.10.03 Enkhbold [0.0]
;;;                     : * Created skeleton code: a wrapper around existing visual location module
;;;                     : The wrapper includes several several new feature slots: color, size, shading, orientation and shape
;;; 2011.10.14 Enkhbold [0.6]
;;;                     : Created visual memory in form of hashtable
;;;                     : Implemented pre-attentive vision described in "Modeling Visual Search of Display of Many Objects: The Role of Differential Acuity and Fixation Memory" (Kieras, 2010)
;;;                     : Implemented update of visual memory at moment of move-attention
;;; 2011.10.30 Enkhbold [0.8]
;;;                     : Implemented spreading activation from visual memory [not tested]
;;;                     : Implemented visual regions [not tested]
;;;                     : Gaze location is calculated as the center of an abstract-location rather than its top-left corner [not tested]
;;;                     : Created abstract-location buffer
;;;                     : It is possible to send request abstract-location buffer by specifying:
;;;                             - specific feature values or location coordinates
;;;                             - attended state for abstract location
;;;                             - attended state for individual features of the same abstract-location
;;;                     : Given request to abstract-location buffer the module creates abtract-location chunk and visual-location chunk for visual-location buffer
;;;                     : Implemented finst-span time during which abstract-location's attended state can stay NEW
;;;                     : Moved update of visual memory to encoding-complete
;;;                     : Eye gaze location updated is moved to encodign-complete
;;;                     : Removal of expired abstract-locations is moved to pm-module-request
;;;                     : Distance between gaze position and abstract-location is calculated by taking center coordinates of abstract-location insted of top-left
;;; 2011.11.02 Enkhbold [0.9]
;;;                     : implemented saccade (similar to EMMA)
;;;                     : implemented saccade landing position as a function of Gaussian distribution around the mean of abstract-location with SD calculated based on object's size
;;;                     : implemented similarity and dissimilarity based search of abstract-lcoation through :similar parameter
;;; 2011.11.17 Enkhbold [0.95]
;;; 2011.12.01 Enkhbold [0.98a]
;;;                     : visual region from which object was encoded is automatically copied to region slot of a chunk in a visual buffer
;;;                     : visual-feature chunk types include slot-name slot
;;;                     : visual-feature chunks have respective slot names at slot-name slots
;;;                     : parameter :region in abstract-location request accepts a negation - to include all abstract-lcoations that are not within that visual region
;;; 2011.12.23 Enkhbold [0.98b]
;;;                    : implementing a slightly modified version of threshold function
;;; 2012.01.09 Enkhbold [0.98b]
;;;                     : new implementation of a top-down visual threshold function
;;;                             - modeler can explicitly indicate within move-attention request whether to store top-down activation as a threshold
;;;                             - modified syntax for specifying relevancy parameter in abstract-location request; includes possibility to specify >, >=, <= or <
;;;                             - relevancy parameter takes as a value either:
;;;                                     a) a feature name to specify threshold for individual feature dimension
;;;                                     b) "current" keyword to specify threshold as a sum of top-down activations of features comprising the threshold
;;; 2012.01.17 Enkhbold [0.98b]
;;;                     : added instanteneous noise component to the sum of top-down and bottom-up activations (inside the get-most-activ-abstr-locs method)
;;; 2012.03.01 Enkhbold [0.98c]
;;;                     : added acuity threshold for a text
;;; 2012.03.26 Enkhbold [0.98c]
;;;                     : now iconic memory maintains location information of objects that were inside the iconic memory but were removed due to decay
;;; 2013.03.14 Enkhbold [0.98d]
;;;                     : Visual Short-Term Memory (VSTM) is implemented
;;;                             - all visual-object chunks cleared from VISUAL buffer go to VSTM instead of DM
;;;                             - all visual-object chunks cleared from VSTM go to DM
;;;                             - introduced vstm-persist-time parameter that can be set vis SGP call
;;;                                 - sets the time duration after which visual-object chunk is cleared from VSTM
;;;                                 - default value is 10000 ms
;;;                             - introduced vstm-capacity parameter that can be set vis SGP call
;;;                                 - sets the maximum number of visual-object chunks VSTM can have at any given time
;;;                                 - default value is 4 chunks
;;;                             - introduced a VISUAL-MEMORY buffer to query content of VSTM
;;;                     : PAAV module is modified to work with HRM module
;;;                             - Chunk-types VISUAL-FEATURE, FEATURE-LOCATION and FEATURE-OBJECT are all subtypes or R-INSTANCE
;;;                             - HRM can access VSTM to derive spatial relations between visual objects
;;;                     : Ability to create imaginary/abstract visual-objects
;;;                             - PAAV can create ABSTRACT-VISUAL-OBJECT chunks inside VSTM as a result of its imagination running wild
;;;                             - ABSTRACT-VISUAL-OBJECT chunk has the same slots as the VISUAL-OBJECT chunk plus one additional slot called REFERENCE-CHUNK
;;;                                 - REFERENCE-CHUNK slot value refers to other chunk encapsulated by current ABSTRACT-VISUAL-OBJECT chunk
;;;                             - ABSTRACT-VISUAL-OBJECT chunk can be used 
;;;                                 - to encapsulate any other chunk to temporarily give it spatial and visual properties 
;;;                                 - to indirectly change spatial or visual properties of VISUAL-OBJECT chunks already existing inside VSTM
;;;                                     - change is indirent since it is done via encapsulation rather than direct modification of slot values in VISUAL-OBJECT chunk
;;;                                 - as a standalone visual object without any encapsulation
;;;                             - ABSTRACT-VISUAL-OBJECT can be created via ADD-ABSTRACT-OBJECT request to VISUAL-MEMORY buffer
;;;                             - ABSTRACT-VISUAL-OBJECT chunks cleared from VSTM do not go to DM
;;;                                 - Is it a right way to approach it?
;;; 2013.04.09 Ryan Hope [0.98d]
;;;                     : added a method purge-abstract-locations to purge content of iconic memory
;;; 2013.12.23 Enkhbold [0.98e]
;;;                     : Visual Short-Term Memory (VSTM) functionality has become optional
;;;                            - it is turned off by default
;;;                            - it can be turned off/on using :enable-vstm parameter in SGP call
;;; 2014.01.06 Enkhbold [0.98e]
;;;                     : added PRINT-GAZE-LOC function for printing current gaze's X and Y coordinates
;;;                     : added VSTM-RETRIEVAL-FAILURE function that announces in a trace a failure of retrieval from VSTM
;;;                     : VIS-MEMORY hashtable has been renamed to ICONIC-MEMORY
;;;                     : VIS-MEMORY prefixes in all variable names have been renamed to ICONIC-MEMORY
;;;                     : some indentation changes in the source code that affects overall number of lines
;;; 2014.01.08 Enkhbold [0.98e]
;;;                     : added CLEAR-VISICON, a utility function to remove all visual-location chunks from visicon
;;;
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Things to consider while compiling, loading, and using PAAV module:
;;;
;;; - GET-BUFFER-PLACEHOLDER-VALUE function body is defined within HRM method; You can safely ignore the related warning during a compilation if you are not planning to use HRM.
;;;
;;;
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; [SC] concept of PAAV visual memory
;;;;            visual memory is an incomplete representation of chunks in visicon
;;;;            however the abstract-locations that are visible in visual memory should always be consistent with corresponding chunks in visicon
;;;;                PROBLEM: features can remain in visual memory for 4 secs even if not visible anymore what if the corresponding feature in visicon changes during that time?
;;;;                            this case violates the rule of consistency
;;;;                            [TODO] also how the visual memory should be updated?


;;;; [SC] References
; Information needed for object analysis is acquired within the first 45-75 ms of a fixation (van Diepen, DeGraef, & d'Ydewalle, 1995)
; Sufficient information is encoded in the first 50-70 ms of a fixation for object identification to occur (Rayner, 1998; Diepen, 1998a and 1998b)

;;;; [TODO] TO CORRECT
;;;;        PLAYED AROUND WITH DISTANCE FACTOR
;;;;        PLAYED AROUND WITH TOP-DOWN-ACTIVATION-CALCULATION
;;;;        PLAYED AROUND WITH LAST-ATTENDED-RELEVANT
;;;;        PLAYED AROUND WITH LAST-LOCATED-RELEVANT

;;;; [TODO] [ERROR] need to limit access to slot values in chunk within abstract-location buffer
;;;; [TODO] [ERROR] make sure that the copy-list is used to avoid pass by reference
;;;; [TODO] [PRIORITY] check for consistency in abstract-location request between feature type and supplied value (error if fcolor vf-oval)
;;;; [TODO] [PRIORITY]            should NIL be allowed as a value in feature type request?
;;;; [TODO] make sure that variables are not referenced instead of creating a new copy
;;;; [TODO] need to check the difference between nonneg and posnum flags for module parameters
;;;; [TODO] [PRIORITY] make sure that necessary variables are reset when the module is reset
;;;; [TODO] should I implement left-hand side condition test for visual-memory?
;;;; [TODO] How should reseting of visual memory be handled between trials?
;;;; [TODO] When an item is encoded its value is assumed to be put in visual memory?
;;;;            [SC] VISUAL MEMORY IS NOT DECLARATIVE MEMORY?
;;;; [TODO] At the start the location of the eye is assumed to be at 0 0 point of the screen; 
;;;;                the visual memory should stuffed at the beginning of the model run before any production fires
;;;;                the buffer stuffing for visual location buffer is not considered
;;;; [TODO] need to prevent visual location chunks from being stored in declarative memory
;;;; [TODO] maybe need to override the default function for calculating the size
;;;; [TODO] current assumption is that the items in visicon are static
;;;; [TODO]
;;;; Need to provide some means for setting values for feature slots in visual-location chunk
;;;    [TODO] text-property is a special type that also extends visual-property type
;;;        [TODO] this property has frequency
;;;        [TODO] this property has word-length
;;;        [TODO] saliency is calculated from frequency and word-length; calculation should be done only once

;;;; [LOWER PRIORITY]
;;;; [TODO] need a smarter way to calculate the noise for saccade landing position
;;;;            current approach can result in inability to to see visual feature of the encoded item due to far landing position
;;;; [TODO] [PRIORITY] request with attended NIL should also include attended NEW



;;;; [TODO] [2012.03.09] [PRIORITY] When visual-location chunk is created in visual-location buffer, incorrect value is put in the value slot
  ; [SC] text in icon memory spreading activation
  ; [SC] text in calculation of bottom-up activation
  ; [SC] text in calculation of top-down activation
  ; [SC] text in feature attended state checking
  ; [SC] text in relevancy flag

;;;; [TODO] [2012.03.12] [PRIORITY]
    ; [SC] need to implement double saccade in case if the first landing position for the fixation is not enough to encode some elements of the visual object

;;;; [TODO] [2012.03.27] [PRIORITY]
    ; [SC] need to check for errors since now iconic memory includes abstract-locations that have none of the features visible
        ;;;; particularly need to make sure that there are no unexpected shenanigans in:
        ;        - top-down and bottom-up activation calculations
        ;        - spreading activation
        ;        - attended states



#+:packaged-actr (in-package :act-r)
#+(and :clean-actr (not :packaged-actr) :ALLEGRO-IDE) (in-package :cg-user)
#-(or (not :clean-actr) :packaged-actr :ALLEGRO-IDE) (in-package :cl-user)

;;; [SC] checks if :apa is already in the *features* list and if not then pushes it to the list
;;; [SC] probably *features* is module registry list
;;; [TODO] need to check content of *features*
(pushnew :paav *features*)  ;;mjs indicate emma module

(defvar *print-flag* nil)

(defvar *attended-new* 'NEW)
(defvar *attended-nil* 'NIL)
(defvar *attended-t* 't)

(defvar *relevant-higher* 'HIGHER)
(defvar *relevant-lower* 'LOWER)

(defvar *loc-slot-list* '(size width height value color kind distance screen-y screen-x fsize forient fshading fshape fcolor))

;;;; [SC] apa-vis-mode extends existing visual module therefore it should be able to run normaly if I do not override any of the functions and methods
;;;; [TODO] might not need some of these variables
(defclass paav-vis-mod (vision-module)
    (
        ;;;; [SC] this is a hashtable representing visual memory
        ;;;; [SC] it contains all abstract-locations that entered visual memory and still not decayed
        ;;;; [SC] the key is the abstract-location name and value is chunk specification
        ;;;; vis-memory -> iconic-memory
        (iconic-memory :accessor iconic-memory :initarg :iconic-memory :initform (make-hash-table :test #'equalp))

        ;;;; [SC] this hashtable is used to register time of entry or update of abstract location features to iconic memory (iconic-memory)
        ;;;; [SC] the key is the [abstract location name]-[f[feature name]] and value is (the update time, x and y coordinates of gaze, entry time and state of :attended)
        ;;;; [SC] when abstract-location feature enters the registry then its update time is same as the entry time
        (vm-feature-reg :accessor vm-feature-reg :initarg :vm-feature-reg :initform (make-hash-table :test #'equalp))

        ;;;; [SC] this hashtable registers the attended state of each abstract-location in visual memory
        (vm-loc-reg :accessor vm-loc-reg :initarg :vm-loc-reg :initform (make-hash-table :test #'equalp))

        ;;;; [SC] this hashtable is used to tack the abstract-location chunk ID created from the same chunk
        ;;;; [SC] the key is the abtract-location name and value is the ID for next chunk created
        (abstr-loc-id :accessor abstr-loc-id :initarg :abstr-loc-id :initform (make-hash-table :test #'equalp))
        
        ;;;; [SC] a hashtable storing a dissimilarity value for pair of feature values
        (fval-dissim-ht :accessor fval-dissim-ht :initarg :fval-dissim-ht :initform (make-hash-table :test #'equalp))
        
        ;;;; [SC] a hashtable for bottom-up activation lists for each abstract-location
        ;;;; [SC] the key is an abstract-location name and value is list of activation-values (list color, shape, shading, orient, size)
        (bottom-up-activ-ht :accessor bottom-up-activ-ht :initarg :bottom-up-activ-ht :initform (make-hash-table :test #'equalp))
        
        ;;;; [SC] a hashtable for top-down activation lists for each abstract-location
        ;;;; [SC] Key is the abstract-location name is value is a top-down activation record.
        ;;;; [SC] Format of a top-down activation record: 
        ;;;; [SC]      (list (list '(feature-test1 similarity-value) '(feature-test2 similarity-value) ...) distance-factor-value)
        ;;;; [SC] Example of top-down activation record:
        ;;;; [SC]      (list (list '(fcolor 0.5) '(fshape 1)) 0.56)
        (top-down-activ-ht :accessor top-down-activ-ht :initarg :top-down-activ-ht :initform (make-hash-table :test #'equalp))

        ;;;; [SC] a hashtable to store information about visual regions
        ;;;; [SC] a key is an ID of an region as given by modeler and value is (x-loc y-loc width height priority category)
        (vis-region-ht :accessor vis-region-ht :initarg :vis-region-ht :initform (make-hash-table :test #'equalp))

        ;;;; [SC] an extension that will be used to generate abstract location name from visual location name (from key in visicon hashtable)
        (abstr-loc-ext :accessor abstr-loc-ext :initform '-ABSTR)

        ;;;; [SC] the flag indicating whether the request to abstr-location buffer failed
        (abstr-loc-failure :accessor abstr-loc-failure :initform nil)

        ;;;; [SC] this parameter stores an abstract location name and boolean flag which set to true if location is being encoded
        (abstr-loc-encode :accessor abstr-loc-encode :initform nil)


        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;;;;; START: [TODO][HRM] related codes

        ;;;; [SC][2013.12.20][ENABLE-VSTM] a flag indicating whether VSTM is enabled or disabled; it is disabled by default
        (enable-vstm :accessor enable-vstm :initform nil)

        ;;;; [SC][2013.07.15]
        ;;;; [TODO] should be adjustable by modeler as high, low or medium
        (vstm-trace :accessor vstm-trace :initform nil)
        
        ;;;; [SC] this a visual short-term memory
        ;;;; [SC] the content of this short-term memory are visual-objects encoded via attention shifts
        (vstm-memory :accessor vstm-memory :initarg :vstm-memory :initform (make-hash-table :test #'equalp))

        ;;;; [SC] this is a persistence time for the content of visual short-term memory
        ;;;; [SC] a duration the visual-object remains in vstm since it entered it
        ;;;; [TODO] should be adjustable by modeler
        (vstm-persist-time :accessor vstm-persist-time :initform 10000)

        ;;;; [SC] capacity of the visual short-term memory measured in number of visual-objects it can hold
        ;;;; [TODO] should be adjustable by modeler
        (vstm-capacity :accessor vstm-capacity :initform 4)

        ;;;; [SC] a boolean flag indicating if there is a retrieval failure from vstm
        (vstm-failure :accessor vstm-failure :initform nil)

        ;;;;;; END: [HRM] related codes
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;;;;; [START] parameters adjustable by modeler

        ;;;; [SC] distance (in degrees of visual angle) from current gaze position within which the value slot is filled with the text value
        ;;;; [SC] 1 degree is defined as a radius for a foveal vision
        (text-acuity-dist :accessor text-acuity-dist :initform 1.0)

        (default-acuity-a :accessor default-acuity-a :initform 0)
        (default-acuity-b :accessor default-acuity-b :initform 0)
        ;;;; [SC] fitted [maybe need refitting, not sure]
        (fcolor-acuity-a :accessor fcolor-acuity-a :initform 0.104)
        (fcolor-acuity-b :accessor fcolor-acuity-b :initform 0.85)
        ;;;; [SC] fitted [maybe need refitting, not sure]
        (fshape-acuity-a :accessor fshape-acuity-a :initform 0.142)
        (fshape-acuity-b :accessor fshape-acuity-b :initform 0.96)
        ;;;; [SC] fitted [maybe need refitting, not sure]
        (fshading-acuity-a :accessor fshading-acuity-a :initform 0.147)
        (fshading-acuity-b :accessor fshading-acuity-b :initform 0.96)
        ;;;; [SC] fitted [maybe need refitting, not sure]
        (fsize-acuity-a :accessor fsize-acuity-a :initform 0.14)
        (fsize-acuity-b :accessor fsize-acuity-b :initform 0.96)
        ;;;; [SC] not fitted
        (forient-acuity-a :accessor forient-acuity-a :initform 0.1)
        (forient-acuity-b :accessor forient-acuity-b :initform 0.601)

        ;;;; [SC] the feature similarity weights used for bottom-up and top-down activation calculations
        (default-sim-w :accessor default-sim-w :initform 1)
        (fcolor-sim-w :accessor fcolor-sim-w :initform 1)
        (fshape-sim-w :accessor fshape-sim-w :initform 1)
        (fshading-sim-w :accessor fshading-sim-w :initform 1)
        (fsize-sim-w :accessor fsize-sim-w :initform 1)
        (forient-sim-w :accessor forient-sim-w :initform 1)
        
        ;;;; [SC] top-down and bottom-up activation weight and noise parameters
        (top-down-act-w :accessor top-down-act-w :initform 0.45)
        (bottom-up-act-w :accessor bottom-up-act-w :initform 1.1)
        (vis-act-s :accessor vis-act-s :initform 0.0) ; [SC] instantenious noise parameter for visual activation
        
        ;;;; [SC] this parameters indicates how long the abstract location's feature should be kept in visual memory (iconic-memory hashtable) if it is not visible anymore
        ;;;; [SC] the value should be in seconds
        (persistence-time :accessor persistence-time :initform 4000)

        ;;;; [SC] parameters for visual memory buffer and querying
        (num-finst-abstr :accessor num-finst-abstr :initarg :num-finst-abstr :initform 4)
        (finst-span-abstr :accessor finst-span-abstr :initarg :num-finst-abstr :initform 3000)

        ;;;; [SC] parameters for spreading activation from visual memory
        (iconic-memory-mas :accessor iconic-memory-mas :initform 0)    ; minimum associative strength of chunks in visual memory to chunks in declarative memory
        (iconic-memory-w :accessor iconic-memory-w :initform 1)        ; overall weight of activation spreading from visual memory
        (vm-fcolor-w :accessor vm-fcolor-w :initform 1)
        (vm-fshape-w :accessor vm-fshape-w :initform 1)
        (vm-fshading-w :accessor vm-fshading-w :initform 1)
        (vm-fsize-w :accessor vm-fsize-w :initform 1)
        (vm-forient-w :accessor vm-forient-w :initform 1)
        (vm-ftext-w :accessor vm-ftext-w :initform 1)
        
        ;;;; [SC] EMMA borrowed code
        ;;;; [SC] this parameter indicates current gaze location (can be different from location of currently attended visual location)
        (gaze-loc :accessor gaze-loc :initform #(0 0))
        ;;;; [SC] weight of a noise used to calculate gaze's variable landing position
        (gaze-noise-weight :accessor gaze-noise-weight :initform 0.5)
        
        ;;;; [SC] PAAV version of move-attention-latency parameter
        ;;;; [SC] basically the time it takes to encode a visual object
        (move-attn-latency-new :accessor move-attn-latency-new :initarg :move-attn-latency-new :initform 0.05)

        (eye-tracking :accessor eye-tracking :initform nil)

        ;;;;;; [END] parameters adjustable by modeler
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        
        ;;;; [SC] [PAAV] this code stores the eye-tracking protocols created by model run
        ;(eye-track-protocols :accessor eye-track-protocols :initarg :eye-track-protocols :initform (make-hash-table :test #'equalp))
        (eye-track-protocols :accessor eye-track-protocols :initform nil)
        (sacc-counter :accessor sacc-counter :initform 0)
        (fx-counter :accessor fx-counter :initform 0)

        ;;;; [SC] EMMA borrowed code
        (sacc-base-exe :accessor sacc-base-exe :initarg :base-exe :initform 0.020) ; [SC] base time for saccade execution is 20 ms

        ;;;; [SC] EMMA borrowed code
        (sacc-rate :accessor sacc-rate :initarg :sacc-rate :initform 0.002)    ; [SC] rate at which the saccade duration increases for each degree of visual angle
        
        ;;;; [SC] top-down activation value for the last encoded visual-object
        (last-attended-relevancy :accessor last-attended-relevancy :initform nil)
        ;;;; [SC] top-down activation value for the last located abstract-location
        (last-located-relevancy :accessor last-located-relevancy :initform nil)

        ;;;; [SC] [NEW] [WORD] stores the matching region-id and region-categoty values that where used to locate abstract-location
        ;;;; [SC] value is (list region-id region-category)
        (last-located-region-info :accessor last-located-region-info :initform nil)
        ;;;; [SC] [NEW] [WORD] stores the matching region-id and region-categoty values that where used to locate abstract-location and is being attended
        ;;;; [SC] value is (list region-id region-category)
        (last-attended-region-info :accessor last-attended-region-info :initform nil)

        ;(enc-factor :accessor enc-factor :initarg :enc-factor :initform 0.010)
        ;(enc-exponent :accessor enc-exponent :initarg :enc-exponent :initform 1.0)
        ;(eye-trace :accessor eye-trace :initform nil)
        ;(sacc-rate :accessor sacc-rate :initarg :sacc-rate :initform 0.002)
        ;(shift-start :accessor shift-start :initarg :shift-start :initform 0)
        ;(shift-duration :accessor shift-duration :initarg :shift-duration :initform nil)
        ;(shift-target :accessor shift-target :initarg :shift-target :initform nil)
        ;(trace-eye-p :accessor trace-eye-p :initarg :trace-eye-p :initform nil)
        ;(prep-event :accessor prep-event :initform nil) ;;holds current preparation-complete event
        ;(next-loc :accessor next-loc :initform nil) ;;holds the next landing loc
       
        ;(default-freq :accessor default-freq :initform 0.01)
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Utility functions

;;;; [SC][2014.01.08] a utility function to remove all visual-location chunks from visicon
;;;; [SC] should be used with a CARE since it does not automatically reset finsts and attended state; not yet anyway
;;;; [SC][TODO] reset finsts and attended state 
(defun clear-visicon ()
    (verify-current-mp "clear-visicon is called with no current meta-process."
        (verify-current-model "clear-visicon is called with no current model."
            (maphash 
                (lambda (key value)
                    (declare (ignore key))
                    (when (chunk-p-fct value)
                        (purge-chunk-fct value)
                    )
                )
                (visicon (get-module :vision))
            )
            (clrhash (visicon (get-module :vision)))
        )
    )
)

(defun to-string (something)
    (cond
        ((symbolp something)
            (string something)
        )
        ((numberp something)
            (write-to-string something)
        )
        ((stringp something)
            something
        )
    )
)

;;;; [SC] calculates the center point given an abstract-location
(defun get-abstr-loc-center (abstr-loc)
    (get-vis-loc-center
        (get-abstr-loc-slot-val 'screen-x abstr-loc)
        (get-abstr-loc-slot-val 'screen-y abstr-loc)
        (get-abstr-loc-slot-val 'width abstr-loc)
        (get-abstr-loc-slot-val 'height abstr-loc)
    )
)

;;;; [SC] calculates center point of a visual-location given its upper left coordinates, width and height
;;;; [TODO] change the method name to get-center
;;;; [TESTED]
(defun get-vis-loc-center (x-loc y-loc width height)
    (if (and (numberp x-loc) (numberp y-loc) (numberp width) (numberp height))
        (list (+ x-loc (/ width 2)) (+ y-loc (/ height 2)))
        nil
    )
)

;;;; [TODO] this function just for debugging purpose; delete if not necessary anymore
;;;; [SC][2013.12.23][ICONIC-NAME]
(defmethod print-iconic-memory-registries ((paav-mod paav-vis-mod))
    ;(format t "~%Content of a visual memory at the gaze location ~a:~%" (gaze-loc paav-mod))
    (let ((iconic-memory (iconic-memory paav-mod)))
        (maphash #'(lambda (k v) (format t "~a => ~a~%" k v)) iconic-memory)
    )
    (format t "~%Content of a visual feature registry at the gaze location ~a:~%" (gaze-loc paav-mod))
    (let ((vm-feature-reg (vm-feature-reg paav-mod)))
        (maphash #'(lambda (k v) (format t "~a => ~a~%" k v)) vm-feature-reg)
    )
    (format t "~%Content of a location registry at the gaze location ~a:~%" (gaze-loc paav-mod))
    (let ((vm-loc-reg (vm-loc-reg paav-mod)))
        (maphash #'(lambda (k v) (format t "~a => ~a~%" k v)) vm-loc-reg)
    )
    (format t "~%")
)

;;;;;; END: Utility functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: [HRM][TODO] Visual Short-Term Memory related functions and methods

;;;; [TODO]
#|(defmethod get-vstm-vis-obj-by-name ((paav-mod paav-vis-mod) vis-obj-chnk-name)
    (let
        (
            (vstm-persist-time (vstm-persist-time paav-mod))
            (curr-actr-time (mp-time-ms))
            (vis-obj-value nil)
        )

        ;;;; [TODO][CORE] maybe it is better to standardize the chunk name before recording it in vstm, the "standardize-chnk-name" function is a stub
        ;;;; [TODO] no need to iterate through hashtable if name is standardazied
        (setf vis-obj-chnk-name (standardize-chnk-name vis-obj-chnk-name))

        ;;;; [SC] trying to retrieve the visual object from vstm by its chunk name
        (setf vis-obj-value (gethash vis-obj-chnk-name (vstm-memory paav-mod)))

        ;;;; [TODO] this might not be required if chunk name was standardized
        ;;;;; [SC] if object was not retrieved then checking if there is the same object stored under different name
        (if (not vis-obj-value)
            (maphash
                #'(lambda (curr-vis-obj-name value)
                    (if (equal-vis-objects curr-vis-obj-name vis-obj-chnk-name)
                        (progn
                            (setf vis-obj-chnk-name curr-vis-obj-name)
                            (setf vis-obj-value value)
                            ;;;; [TODO] make sure the return really works
                            (return)
                        )
                    )
                )
                (vstm-memory paav-mod)
            )
        )

        ;;;; [SC] no matching object was found
        (if (not vis-obj-value)
            (return-from get-vstm-vis-obj-by-name nil)
        )
        
        ;;;; [TODO][CORE] make sure correct time for visual object is used
        ;;;; [SC] if true then visual object is overdue the persistence time
        (if (> (- curr-actr-time (get-vis-obj-entry-ts vis-obj-value)) vstm-persist-time)
            (progn
                ;;;; [SC] removing visual object
                (remove-vis-obj-from-vstm paav-mod vis-obj-chnk-name)
                (return-from get-vstm-vis-obj-by-name nil)
            )
        )
    )
)|#

;;;; [TODO]
;(defmethod set-vis-obj-leave-ts ((paav-mod paav-vis-mod) vis-obj-chnk-name leave-time)
;    (let ((vis-obj-record (gethash vis-obj-chnk-name (vstm-memory paav-mod))))
;        (if    vis-obj-record
;            ;;;; [TODO] [TEST] make sure it actually changes the list in hashtable
;            (setf (nth 2 vis-obj-record) leave-time)
;        )
;    )
;)

;;;; [TODO]
;(defun get-vis-obj-leave-ts (value-list)
;    (return (third value-list))
;)

;;;; [TODO]
;;;; [SC][ENABLE-VSTM] get visual object's timestamp for VSTM entry/update
(defun get-vis-obj-entry-ts (value-list)
    (return-from get-vis-obj-entry-ts (first value-list))
)

;;;; [TODO]
;;;; [SC][ENABLE-VSTM] get visual object's retrieved state for VSTM
(defun get-vis-obj-retrieved (value-list)
    (return-from get-vis-obj-retrieved (second value-list))
)

;;;; [TODO]
;;;; [SC][ENABLE-VSTM] set visual object's timestamp for VSTM entry/update
(defmethod set-vis-obj-entry-ts ((paav-mod paav-vis-mod) vis-obj-chnk-name entry-time)
    (if (vstm-trace paav-mod)
        (progn
            (format t "~%Entry/Update time for ~s is being updated to ~s" vis-obj-chnk-name entry-time)
        )
    )

    (let ((vis-obj-record (gethash vis-obj-chnk-name (vstm-memory paav-mod))))
        (if vis-obj-record
            (setf (nth 0 vis-obj-record) entry-time)
        )
    )
)

;;;; [TODO]
;;;; [SC][ENABLE-VSTM] set visual object's retrieved state for VSTM
(defmethod set-vis-obj-retrieved ((paav-mod paav-vis-mod) vis-obj-chnk-name retrieved-state)
    (let ((vis-obj-record (gethash vis-obj-chnk-name (vstm-memory paav-mod))))
        (if vis-obj-record
            (setf (nth 1 vis-obj-record) retrieved-state)
        )
    )
)

;;;; [TODO]
;;;; [SC][ENABLE-VSTM] visual object record is (list entry-timestamp retrieved-flag leave-timestamp)
(defun create-vis-obj-record ()
    (list (mp-time-ms) nil nil)
)

;;;; [TODO][CORE][ENABLE-VSTM]
(defun standardize-chnk-name (vis-obj-chnk-name)
    vis-obj-chnk-name
)

;;;; [TODO][CORE] what if it is the same chunk but its location has changed since it entered iconic-memory
;;;; [TODO][CORE] should the equality of two chunk be decided by position rather than slot values (example it is the same chunk but its feature was changed)?
;;;; [SC][ENABLE-VSTM] checks the equality of two visual objects, parameters are the chunk names
(defun equal-vis-objects (vis-obj-one vis-obj-two)
    (equal-chunks-fct vis-obj-one vis-obj-two)
)

;;;; [SC] set recently-retrieved state of all visual objects in VSTM to NIL 
;;;; [TODO] This method is not used anywhere currently.
(defun remove-vstm-finsts ()
    (verify-current-mp "remove-vstm-finsts is called with no current meta-process."
        (verify-current-model "remove-vstm-finsts is called with no current model."
            (let ((paav-mod (get-module :vision)))
                (maphash 
                    #'(lambda (vis-obj-chnk-name record)
                        (declare (ignore record))
                        (set-vis-obj-retrieved paav-mod vis-obj-chnk-name nil)
                    )
                    (vstm-memory paav-mod)
                )
            )
        )
    )
)

;;;; [SC] checks whether given chunk is inside VSTM either as a visual object or general concept that is referred by an abstract visual object
;;;; [TODO] This method is not used anywhere currently.
(defun is-inside-vstm (chunk-name)
    (verify-current-mp "is-inside-vstm is called with no current meta-process."
        (verify-current-model "is-inside-vstm is called with no current model."
            (let ((paav-mod (get-module :vision)))
                (cond
                    
                    ((chunk-type-subtype-p-fct (chunk-chunk-type-fct chunk-name) 'visual-object)
                        (maphash 
                            #'(lambda (vis-obj-chnk-name record)
                                (declare (ignore record))
                                (if
                                    (or
                                        (equal-vis-objects chunk-name vis-obj-chnk-name)
                                        (and 
                                            (chunk-type-subtype-p-fct (chunk-chunk-type-fct vis-obj-chnk-name) 'abstract-visual-object)
                                            (equal (chunk-slot-value-fct vis-obj-chnk-name 'reference-chunk) chunk-name) ;;;; [TODO] should I use equal-vis-objects?
                                        )
                                    )
                                    (return-from is-inside-vstm vis-obj-chnk-name)
                                )
                            )
                            (vstm-memory paav-mod)
                        )
                    )

                    ((chunk-type-subtype-p-fct (chunk-chunk-type-fct chunk-name) 'abstract-visual-object)
                        (maphash 
                            #'(lambda (vis-obj-chnk-name record)
                                (declare (ignore record))
                                (if (equal-vis-objects chunk-name vis-obj-chnk-name)
                                    (return-from is-inside-vstm vis-obj-chnk-name)
                                )
                            )
                            (vstm-memory paav-mod)
                        )
                    )

                    (t
                        (maphash 
                            #'(lambda (vis-obj-chnk-name record)
                                (declare (ignore record))
                                (if
                                    (and 
                                        (chunk-type-subtype-p-fct (chunk-chunk-type-fct vis-obj-chnk-name) 'abstract-visual-object)
                                        (equal (chunk-slot-value-fct vis-obj-chnk-name 'reference-chunk) chunk-name) ;;;; [TODO] should I use equal-vis-objects?
                                    )
                                    (return-from is-inside-vstm vis-obj-chnk-name)
                                )
                            )
                            (vstm-memory paav-mod)
                        )
                    )
                )
                nil
            )
        )
    )
)

;;;; [SC][2013.03.07][ENABLE-VSTM] returns true if chunk vis-obj-name is abstract visual object, otherwise nil
(defun is-abstr-vis-obj (vis-obj-name)
    (if (equal (chunk-chunk-type-fct vis-obj-name) 'abstract-visual-object)
        t
        nil
    )
)

;;;; [SC][2013.03.07][ENABLE-VSTM] returns true if chunk vis-obj-name is real visual object, otherwise nil
(defun is-real-vis-obj (vis-obj-name)
    (if (equal (chunk-chunk-type-fct vis-obj-name) 'visual-object)
        t
        nil
    )
)

;;;; [SC][ENABLE-VSTM] removes a visual object from VSTM and merges the removed chunk with chunks in DM
(defmethod remove-vis-obj-from-vstm ((paav-mod paav-vis-mod) vis-obj-name)
    ;;;; [TODO] make if a trace message that is shown depending on the level of message detail set by modeler
    ;;;; [SC][2013.07.15]
    (if (vstm-trace paav-mod)
        (progn
            (format t "~%'~a' is being removed from VSTM.~%" vis-obj-name)
            (pprint-chunks-fct (list vis-obj-name))
        )
    )

    (if (is-real-vis-obj vis-obj-name)
        ;;;; [SC][2013.03.07] if real visual object then merge the chunk with chunk in DM
        (merge-chunk-into-dm (get-module declarative) 'vstm vis-obj-name)

        ;;;; [SC][2013.03.07] otherwise it is an abstract visual object so purge the chunk from model
        (purge-chunk-fct vis-obj-name)
    )
    (remhash vis-obj-name (vstm-memory paav-mod))
)

;;;; [SC][ENABLE-VSTM] deletes all decayed visual objects from VSTM
(defmethod delete-decayed-vis-obj-from-vstm ((paav-mod paav-vis-mod))
    (let
        (
            (vstm-persist-time (vstm-persist-time paav-mod))
            (vstm-memory (vstm-memory paav-mod))
            (curr-actr-time (mp-time-ms))
            (remove-list nil)
            (remain-list nil)
        )
        
        (maphash
            #'(lambda (curr-vis-obj-name value)
                ;;;; [SC] if true then the visual object is overdue the persistence time
                ;;;; [TODO][CORE] make sure that return actually exists the loop 
                (if 
                    (> 
                        (- curr-actr-time (get-vis-obj-entry-ts value))
                        vstm-persist-time
                    )
                    (push curr-vis-obj-name remove-list)
                    (push curr-vis-obj-name remain-list)
                )
            )
            vstm-memory
        )

        (dolist (curr-vis-obj-name remove-list)
            (remove-vis-obj-from-vstm paav-mod curr-vis-obj-name)
        )

        remain-list
    )
)

;;;; [SC][ENABLE-VSTM] returns from VSTM a visual object that matches the specification provided by vis-obj-chnk-spec
;;;; [SC] returns NIL if no matches are found
(defmethod get-vstm-vis-obj-by-spec ((paav-mod paav-vis-mod) vis-obj-chnk-spec)
    (let
        (
            (main-spec (strip-request-parameters-from-chunk-spec vis-obj-chnk-spec))
            (recently-retrieved
                (when (slot-in-chunk-spec-p vis-obj-chnk-spec :recently-retrieved)
                    (car (chunk-spec-slot-spec vis-obj-chnk-spec :recently-retrieved)))
            )
            (vis-obj-chnk-name nil)
            (vis-obj-list nil)
        )

        ;;;; [SC] removing expired visual objects from vstm and collecting chunk names for remaining visual objects into a list
        (delete-decayed-vis-obj-from-vstm paav-mod)

        ;;;; [SC] filtering visual objects by value of recently-retrieved
        (maphash
            #'(lambda (curr-vis-obj-name value)
                (if recently-retrieved
                    (if 
                        (or
                            (and 
                                (eq t (third recently-retrieved))
                                (eq t (get-vis-obj-retrieved value))
                            )
                            (and
                                (eq nil (third recently-retrieved))
                                (eq nil (get-vis-obj-retrieved value))
                            )
                        )
                        (push curr-vis-obj-name vis-obj-list)
                    )
                    (push curr-vis-obj-name vis-obj-list)
                )
            )
            (vstm-memory paav-mod)
        )
        
        ;;;; [SC] looking from the list for visual objects matching the chunk specs
        (setf vis-obj-list (find-matching-chunks main-spec :chunks vis-obj-list))
        
        (if vis-obj-list
            ;;;; [SC] get a random visual object name from the list of matching visual objects
            (setf vis-obj-chnk-name (random-item vis-obj-list))
        )

        ;;;; [SC] if "vis-obj-chnk-name" is nil then all visual objects in vstm have expired persistence time
        vis-obj-chnk-name
    )
)

;;;; [TODO]
;;;;    - any retrieval
;;;;    + finsts
;;;;    + adding visual object to vstm
;;;;    +/- updating the timestamp when corresponding abstract-location/visual-location is not available
;;;;    - how retrieved state for visual chunk in vstm should change if it is already t but was updated with new encoding of the same object?
;chunk-copied-from-fct

;;;; [SC][ENABLE-VSTM] adds vis-obj-chnk-name into VSTM
(defmethod add-vis-object-to-vstm ((paav-mod paav-vis-mod) vis-obj-chnk-name)
    (let 
        (
            (vstm-capacity (vstm-capacity paav-mod))
            (vstm-memory (vstm-memory paav-mod))
            (oldest-vis-obj-name nil)
            (oldest-vis-obj-timestamp nil)
        )

        ;;;; [SC] deleting decayed visual objects from vstm, it is necessary since decayed is not equivalent to the oldest
        (delete-decayed-vis-obj-from-vstm paav-mod)

        ;;;; [TODO][CORE] maybe it is better to standardize the chunk name before recording it in vstm
        ;;;; [TODO] no need to iterate through hashtable if name is standardazied
        (setf vis-obj-chnk-name (standardize-chnk-name vis-obj-chnk-name))

        (maphash
            #'(lambda (curr-vis-obj-name value)
                
                (cond
                    ;;;; [SC] if true then visual object is already in vstm, do nothing except updating entrance time (for example, it is the same chunk but with a different chunk name)
                    ;;;;            - [TODO][CORE] what to do if the chunk name is the same but the some slot values have been changed?
                    ((and (is-real-vis-obj curr-vis-obj-name) (equal-vis-objects curr-vis-obj-name vis-obj-chnk-name))
                        ;;;; [SC] 1. just update the timestamp of the object already inside VSTM
                        (set-vis-obj-entry-ts paav-mod curr-vis-obj-name (mp-time-ms))
                        (return-from add-vis-object-to-vstm nil)
                    )

                    ;;;; [SC] there is an abstract visual object that already refers to vis-obj-chnk-name
                    ;;;; [TODO][TEST] make sure both add and removal work since the maphash is still looping
                    ((and (is-abstr-vis-obj curr-vis-obj-name) (equal (chunk-slot-value-fct curr-vis-obj-name 'reference-chunk) vis-obj-chnk-name))
                        ;;;; [SC] 1. remove abstract visual object
                        (remove-vis-obj-from-vstm paav-mod curr-vis-obj-name)
                        ;;;; [SC] 2. add the real visual-object to vstm
                        (setf (gethash vis-obj-chnk-name vstm-memory) (create-vis-obj-record))
                        (return-from add-vis-object-to-vstm nil)
                    )
                )

                ;;;; [SC] save chunk name if current visual object is the oldest visual object in VSTM
                (if (or (not oldest-vis-obj-name) (> oldest-vis-obj-timestamp (get-vis-obj-entry-ts value)))
                    (progn
                        (setf oldest-vis-obj-name curr-vis-obj-name)
                        (setf oldest-vis-obj-timestamp (get-vis-obj-entry-ts value))
                    )
                )
            )
            vstm-memory
        )        
        
        ;;;; [SC] if true then vstm has reached its maximum capacity
        (if (>= (hash-table-count vstm-memory) vstm-capacity)
            ;;;; [SC] removing the oldest visual-object from vstm
            ;;;; [TEST] make sure that visual-object was actually removed
            (remove-vis-obj-from-vstm paav-mod oldest-vis-obj-name)
        )

        ;;;; [SC] adding the visual-object to vstm
        (setf (gethash vis-obj-chnk-name vstm-memory) (create-vis-obj-record))
    )
)

;;;; [SC][2013.03.08][ENABLE-VSTM]
;;;; [SC] checks if slot with slot-name exists inside specifications slot-specs; returns (list of true and value of the slot) if slot exists 
(defun has-slot-spec (slot-specs slot-name)
    (dolist (slot-spec slot-specs)
        (if (equal slot-name (second slot-spec))
            (return-from has-slot-spec (list t (third slot-spec)))
        )
    )
    (list nil nil)
)

;;;; [SC][2013.03.08][ENABLE-VSTM]
;;;; [TODO] need optimization!!!
(defun delete-slot-spec (slot-specs slot-names)
    (let (temp-slot-specs)
        (dolist (slot-spec slot-specs)
            (let ((push-flag t))
                (dolist (slot-name slot-names)
                    (if (equal (second slot-spec) slot-name)
                        (setf push-flag nil)
                        (return)
                    )
                )
                (if push-flag
                    (push slot-spec temp-slot-specs)
                )
            )
        )
        (reverse temp-slot-specs)
    )
)

;;;; [SC][2013.03.08][ENABLE-VSTM]
;;;; [SC] returns from VSTM any existing abstract visual object that has referred to chunk with chunk name given in ref-chunk-name
(defmethod get-exist-abstr-vis-obj ((paav-mod paav-vis-mod) ref-chunk-name)
    (let (matching-vis-objects)
        (maphash
            #'(lambda (curr-vis-obj-name value)
                (declare (ignore value))
                (if 
                    (and 
                        (is-abstr-vis-obj curr-vis-obj-name)
                        (chunk-slot-value-fct curr-vis-obj-name 'reference-chunk)
                        (equal (chunk-slot-value-fct curr-vis-obj-name 'reference-chunk) ref-chunk-name)
                    )

                    (push curr-vis-obj-name matching-vis-objects)
                )
            )
            (vstm-memory paav-mod)
        )
        matching-vis-objects
    )
)

;;;; [SC][2013.03.08][ENABLE-VSTM]
;;;; [SC] creates abstract-visual-object chunk with given slot specification and chunk-name; returns the name of the created chunk
(defun create-abstr-vis-obj-definition (slot-specs ref-chunk-name abstr-vis-obj-name)
    (let (abstract-chunk-def)
        (dolist (slot-spec slot-specs)
            (push (third slot-spec) abstract-chunk-def)
            (push (second slot-spec) abstract-chunk-def)
        )

        (if ref-chunk-name
            (progn
                (push ref-chunk-name abstract-chunk-def)
                (push 'reference-chunk abstract-chunk-def)
            )
        )

        (push 'abstract-visual-object abstract-chunk-def)
        (push 'isa abstract-chunk-def)
                                    
        (if abstr-vis-obj-name
            (push abstr-vis-obj-name abstract-chunk-def)
        )

        ;;;; [SC] adding the visual-object to vstm
        (car (define-chunks-fct (list abstract-chunk-def)))
    )
)

;;;; [SC][2013.03.08][ENABLE-VSTM]
;;;; [SC] checks whether VSTM has exceeded its capacity, and if it does it removes the oldest visual object
(defmethod do-vstm-capacity-check ((paav-mod paav-vis-mod))
    (let 
        (
            (vstm-capacity (vstm-capacity paav-mod))
            (vstm-memory (vstm-memory paav-mod))
            (oldest-vis-obj-name nil)
            (oldest-vis-obj-timestamp nil)
        )

        ;;;; [SC] if true then vstm is above its maximum capacity
        (if (> (hash-table-count vstm-memory) vstm-capacity)
            ;;;; [SC] removing the oldest visual-object from vstm
            (progn
                (maphash
                    #'(lambda (curr-vis-obj-name value)
                        ;;;; [SC] save chunk name if current visual object is the oldest visual object in VSTM
                        (if (or (not oldest-vis-obj-name) (> oldest-vis-obj-timestamp (get-vis-obj-entry-ts value)))
                            (progn
                                (setf oldest-vis-obj-name curr-vis-obj-name)
                                (setf oldest-vis-obj-timestamp (get-vis-obj-entry-ts value))
                            )
                        )
                    )
                    vstm-memory
                )

                ;;;; [TEST] make sure that visual-object was actually removed
                (remove-vis-obj-from-vstm paav-mod oldest-vis-obj-name)
            )
        )
    )
)

;;;; [SC][ENABLE-VSTM] a function to add abstract visual object to visual memory
;;;; Pseudocode for algorithm used:
;;;;    new-abstr-obj - an abstract object that is to be added to VSTM
;;;;    old-abstr-obj - an abstract object already inside VSTM
;;;;    real-vis-obj - a real visual object already inside VSTM
;;;;    A.all_slot_values -  list of all slot values (excluding reference-chunk slot AND (x y) position slots) of an abstract object A
;;;;
;;;;    IF new-abstr-obj.reference-chunk != NULL:
;;;;        IF (new-abstr-obj.reference-chunk == real-vis-obj) AND (new-abstr-obj.all_slot_values == real-vis-obj.all_slot_values):
;;;;            1. will result in potential inconsistency during reasoning, so declare error and do not add abstract object into DM
;;;;            OR
;;;;            IF new-abstr-obj.position is not equal to position of any object in VSTM except real-vis-obj:
;;;;                1. fill missing slot values of new-abstr-obj with slot values from real-vis-obj
;;;;                2. delete real-vis-obj from VSTM
;;;;                3. add new-abstr-obj to VSTM
;;;;            ELSE
;;;;                1. declare error and do not add abstract object into VSTM
;;;;        ELSE IF (new-abstr-obj.reference-chunk == real-vis-obj) AND (new-abstr-obj.all_slot_values != real-vis-obj.all_slot_values):
;;;;            1. will also result in potential inconsistency during reasoning, so declare error and do not add abstract object into VSTM
;;;;            OR
;;;;            IF new-abstr-obj.position is not equal to position of any object in VSTM except real-vis-obj:
;;;;                1. fill missing slot values of new-abstr-obj with slot values from real-vis-obj
;;;;                2. delete real-vis-obj from VSTM
;;;;                3. add new-abstr-obj to VSTM
;;;;            ELSE
;;;;                1. declare error and do not add abstract object into VSTM
;;;;        ELSE IF (new-abstr-obj.reference-chunk == old-abstr-obj.reference-chunk) AND (new-abstr-obj.all_slot_values == old-abstr-obj.all_slot_values):
;;;;            1. update old-abstr-obj' timestamp with current time
;;;;            2. update (x y) position of old-abstr-obj with (x y) position of new-abstr-obj
;;;;            OR
;;;;            1. delete old-abstr-obj
;;;;                need to consider possibility that deleted abstract object may go to DM
;;;;            2. add new-abstr-obj to VSTM
;;;;                [DOES NOT WORK] what if new-abstr-obj is just being partially updated and does not have all slot values
;;;;        ELSE IF (new-abstr-obj.reference-chunk == old-abstr-obj.reference-chunk) AND (new-abstr-obj.all_slot_values != old-abstr-obj.all_slot_values):
;;;;            1. show error AND do not add new-abstr-obj to VSTM
;;;;            OR
;;;;            1. add new-abstr-obj to VSTM
;;;;            OR
;;;;            1. update slot values of old-abstr-obj with new slot values of new-abstr-obj 
;;;;            2. update old-abstr-obj' timestamp with current time
;;;;            3. update (x y) position of old-abstr-obj with (x y) position of new-abstr-obj
;;;;                - [PREFERRED]
;;;;            OR
;;;;            1. delete old-abstr-obj
;;;;                need to consider possibility that deleted abstract object may go to DM
;;;;            2. add new-abstr-obj to VSTM
;;;;                [DOES NOT WORK] what if new-abstr-obj is just being partially updated and does not have all slot values
;;;;        ELSE IF (new-abstr-obj.reference-chunk != old-abstr-obj.reference-chunk) AND (new-abstr-obj.all_slot_values == old-abstr-obj.all_slot_values):
;;;;            IF (new-abstr-obj.position != old-abstr-obj.position) AND (new-abstr-obj.position != real-vis-obj.position):
;;;;                1. add new-abstr-obj to VSTM
;;;;            ELSE:
;;;;                1. declare error and do not add abstract object into VSTM
;;;;        ELSE IF (new-abstr-obj.reference-chunk != old-abstr-obj.reference-chunk) AND (new-abstr-obj.all_slot_values != old-abstr-obj.all_slot_values):
;;;;            IF (new-abstr-obj.position != old-abstr-obj.position) AND (new-abstr-obj.position != real-vis-obj.position):
;;;;                1. add new-abstr-obj to VSTM
;;;;            ELSE:
;;;;                1. declare error and do not add abstract object into VSTM
;;;;    ELSE IF new-abstr-obj.reference-chunk == NULL:
;;;;        IF (new-abstr-obj.position != old-abstr-obj.position) AND (new-abstr-obj.position != real-vis-obj.position):
;;;;            1. add new-abstr-obj to VSTM
;;;;        ELSE:
;;;;            1. declare error and do not add abstract object into VSTM
;;;;
(defmethod add-abstr-vis-object-to-vstm ((paav-mod paav-vis-mod) slot-specs ref-chunk-name abstr-vis-obj-name)
    (let ((vstm-memory (vstm-memory paav-mod)))

        ;;;; [SC] deleting decayed visual objects from vstm, it is necessary since decayed is not equivalent to the oldest
        (delete-decayed-vis-obj-from-vstm paav-mod)

        (if ref-chunk-name
            (cond
                ;;;; [SC] reference-chunk refers to real visual object that already exists inside VSTM
                ((and (gethash ref-chunk-name vstm-memory) (is-real-vis-obj ref-chunk-name))
                    
                    ;;;; [SC] 1. fill missing slot values of new-abstr-obj with slot values from real-vis-obj
                    ;;;; [SC] getting slot names of the real visual object
                    (let ((curr-obj-slot-names (chunk-type-slot-names-fct (chunk-chunk-type-fct ref-chunk-name))))
                        ;;;; [SC] iterate through slot names of real visual object
                        (dolist (curr-obj-slot-name curr-obj-slot-names)
                            ;;;; [SC] getting the value of the current slot from real visual object
                            (let ((curr-obj-slot-val (chunk-slot-value-fct ref-chunk-name curr-obj-slot-name)))
                                ;;;; [SC] making sure the slot value is not nil
                                (if curr-obj-slot-val
                                    (cond
                                        ;;;; [SC] this is screen-pos slot, and chunk specification does not have valid position specified
                                        ((equal curr-obj-slot-name 'screen-pos)
                                            (if
                                                (and
                                                    (chunk-type-subtype-p-fct (chunk-chunk-type-fct curr-obj-slot-val) 'feature-location)
                                                    (or (not (first (has-slot-spec slot-specs 'screen-x))) (not (first (has-slot-spec slot-specs 'screen-y))))
                                                )

                                                (let ((xy-loc (xy-loc curr-obj-slot-val)))
                                                    (setf slot-specs (delete-slot-spec slot-specs '(screen-x screen-y)))

                                                    (push (list '= 'screen-x (aref xy-loc 0)) slot-specs)
                                                    (push (list '= 'screen-y (aref xy-loc 1)) slot-specs)
                                                )
                                            )
                                        )

                                        ;;;; [SC] chunk specification does not have value specification for this slot
                                        ((not (first (has-slot-spec slot-specs curr-obj-slot-name)))
                                            ;;;; [SC] use the value that is within reference chunk
                                            (push (list '= curr-obj-slot-name curr-obj-slot-val) slot-specs)
                                        )
                                    )
                                )
                            )
                        )
                    )

                    ;;;; [SC] 2. delete real visual object from VSTM
                    (remove-vis-obj-from-vstm paav-mod ref-chunk-name)
                
                    ;;;; [SC] 3. add new-abstr-obj to VSTM
                    (setf (gethash (create-abstr-vis-obj-definition slot-specs ref-chunk-name abstr-vis-obj-name) vstm-memory) (create-vis-obj-record))
                )
    
                ;;;; [TODO]
                ;;;; [SC] reference-chunk slot refers to another abstract visual object already existing inside VSTM
                ((and (gethash ref-chunk-name vstm-memory) (is-abstr-vis-obj ref-chunk-name))
                    ;;;; [SC] currently do nothing
                )

                (t
                    ;;;; [SC] get from VSTM any existing abstract visual object that has referred to ref-chunk-name
                    (let ((exist-abstr-vis-obj (get-exist-abstr-vis-obj paav-mod ref-chunk-name)))
                        (cond

                            ;;;; [TODO]
                            ;;;; [SC] there are more than one abstract visual objects inside VSTM that already refer to ref-chunk-name
                            ((and exist-abstr-vis-obj (> (length exist-abstr-vis-obj) 1))
                                ;;;; [SC] this is an error situation
                            )

                            ;;;; [SC] abstract visual object that refers to ref-chunk-name chunk already exists inside VSTM
                            (exist-abstr-vis-obj
                                (setf exist-abstr-vis-obj (first exist-abstr-vis-obj))

                                ;;;; [SC] 1. updating slot values of exist-abstr-vis-obj with values from slot specifications
                                (dolist (slot-spec slot-specs)
                                    (set-chunk-slot-value-fct exist-abstr-vis-obj (second slot-spec) (third slot-spec))
                                )
                            
                                ;;;; [SC] 2. updating the entry time for exist-abstr-vis-obj
                                (set-vis-obj-entry-ts paav-mod exist-abstr-vis-obj (mp-time-ms))
                            )

                            ;;;; [SC] there is no abstract visual object in VSTM that refers to ref-chunk-name chunk
                            (t
                                ;;;; [SC] 1. add new-abstr-obj to VSTM
                                (setf (gethash (create-abstr-vis-obj-definition slot-specs ref-chunk-name abstr-vis-obj-name) vstm-memory) (create-vis-obj-record))
                            )
                        )
                    )
                )
            )

            ;;;; [SC] no value was provided for reference-chunk slot; the abstract visual object is standalone
            (progn
                ;;;; [SC] 1. add new-abstr-obj to VSTM
                (setf (gethash (create-abstr-vis-obj-definition slot-specs ref-chunk-name abstr-vis-obj-name) vstm-memory) (create-vis-obj-record))
            )
        )

        ;;;; [SC] making sure VSTM has not exceeded its capacity
        (do-vstm-capacity-check paav-mod)
    )
)

;;;; [SC][ENABLE-VSTM]
(defmethod vstm-retrieval-callback ((paav-mod paav-vis-mod) chunk-specs)
    (setf (vstm-failure paav-mod) nil)
        
    (let ((vis-obj-chnk-name (get-vstm-vis-obj-by-spec paav-mod chunk-specs)))
        (if vis-obj-chnk-name
            ;;;; [SC] successfully retrieved a matching visual object from VSTM
            (progn
                ;;;; [SC] setting a buffer-scheduler to put a matching chunk to visual memory buffer
                (schedule-set-buffer-chunk 'visual-memory vis-obj-chnk-name 0 :module :vision :priority 5)
                
                ;;;; [SC] updating the retrieved state for the visual object to t
                (set-vis-obj-retrieved paav-mod vis-obj-chnk-name t)

                ;;;; [SC] updating visual objects timestamp
                (set-vis-obj-entry-ts paav-mod vis-obj-chnk-name (mp-time-ms))
            )
            
            ;;;; [SC] failed to retrieve any matching visual object from VSTM
            (progn
                (setf (vstm-failure paav-mod) t)
                (schedule-event-relative 0 'vstm-retrieval-failure :module :vision :output 'low)
            )
        )
    )
)

;;;; [SC][2013.01.06] a dummy function to print VSTM retrieval failure
;;;; [TODO][TEST]
(defun vstm-retrieval-failure()
    "Dummy event function to signal a vstm-retrieval-failure failure in the trace"
    nil
)

;;;; [TODO][DELETE]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: some rules for an abstract visual-object in VSTM
; - If abstract chunk is a copy/reference of the real chunk then the corresponding real chunk should be inside one of the buffers or VSTM at the moment of creating abstract chunk
;    - changes in slot values of an abstract chunk should NOT be reflected in corresponding real chunk
; - Abstract chunk can also be standalone, not a copy/reference of a real chunk
;    - in this case the name of an abstract chunk should be unique, there should not be any real chunk with the same name
;        - this restriction is required so that modelers will not be able to create abstraction of real chunks that are inside only DM (not inside any of the buffers, therefore not directly accessible)
; - If abstract chunk is cleared from VSTM then it should NOT enter DM
;;;;;; END: some rules for an abstract visual-object in VSTM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; [TODO][DELETE]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Ways to request visual-memory buffer to create an abstract visual object inside VSTM
; - create a standalone abstract visual object that is NOT a copy of any existing real visual object chunk
;    - the preferred name for a chunk can be mentioned
;    OR
;    - random name can be created automatically
; - create a copy of a real visual object chunk that is in one of the buffers
;    - an alias name should be automatically created
;    OR
;    - the preferred name for a chunk can be mentioned
; - create a copy of a real visual object chunk that is the slot value of a chunk in one of the buffers
;    - an alias name should be automatically created
;    OR
;    - the preferred name for a chunk can be mentioned
;;;;;; END: Ways to request visual-memory buffer to create an abstract visual object inside VSTM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: need an ability to modify slot values of any abstract visual object inside VSTM
;;;;;; END: need an ability to modify slot values of any abstract visual object inside VSTM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: ability to retrieve visual object from VSTM by chunk-name
;;;;;; END: ability to retrieve visual object from VSTM by chunk-name
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; [SC][ENABLE-VSTM]
(defmethod add-abstract-object-callback ((paav-mod paav-vis-mod) chunk-specs)
    (setf (vstm-failure paav-mod) nil)

    (let* 
        (
            (main-specs (strip-request-parameters-from-chunk-spec chunk-specs))
            (slot-specs (chunk-spec-slot-spec main-specs))
            (abstract-chunk-name 
                (when (slot-in-chunk-spec-p chunk-specs :chunk-name)
                    (car (chunk-spec-slot-spec chunk-specs :chunk-name))
                )
            )
            (reference-chunk-name nil)
            (reference
                (when (slot-in-chunk-spec-p chunk-specs 'reference)
                    (car (chunk-spec-slot-spec chunk-specs 'reference))
                )
            )
        )

        ;;;; [TODO][TEST] verify that all operators inside main-specs are equality operators
        ;;;; [TODO][TEST] verify whether equality was used as an operator for chunk-name parameter
        ;;;; [TODO][TEST] need to make sure that proper slot values were provided:
        ;                    - only color chunk for fcolor
        ;                    - only integer values for position and size values
        ;                    - only region id and region category values that exist
        
        
        (if reference
            ;;;; [SC] the reference was provided
            (progn
                (setf reference (third reference))
                
                (if (get-buffer-name reference)
                    ;;;; [SC] reference is a buffer-placeholder
                    (progn
                        ;;;; [TODO] boolean parameter is T, so getting a original chunk from DM
                        ;;;; [SC] get-buffer-placeholder-value function is part of HRM module
                        (setf reference-chunk-name (get-buffer-placeholder-value reference t))

                        ;;;; [SC] if true then buffer placeholer was provided, but buffer was empty
                        (if (and reference (not reference-chunk-name))
                            (progn
                                (print-warning "Fail to add abstract object to VSTM. Were not able to extract chunk from buffer indicated by following placeholder: ~s" reference)
                                (return-from add-abstract-object-callback nil)
                            )
                        )
                    )

                    ;;;; [SC] reference is a name for a chunk, not buffer placeholder
                    (setf reference-chunk-name reference)
                )
                
                ;;;; [SC] removing specification of reference slot if it exists in slot specifications
                (setf slot-specs (delete-slot-spec slot-specs '(reference)))

                ;;;; [SC] the referred value is not chunk
                (if (not (chunk-p-fct reference-chunk-name))
                    (progn
                        (print-warning "Fail to add abstract object to VSTM. The referred value ~s is not a valid chunk." reference-chunk-name)
                        (return-from add-abstract-object-callback nil)
                    )
                )

                ;;;; [SC] the referred value is not subtype of R-CONCEPT
                (if (not (chunk-type-subtype-p-fct (chunk-chunk-type-fct reference-chunk-name) 'r-concept))
                    (progn
                        (print-warning 
                            "Fail to add abstract object to VSTM. The referred chunk ~s with chunk-type ~s is is not subtype of R-CONCEPT."
                            reference-chunk-name (chunk-chunk-type-fct reference-chunk-name)
                        )
                        (return-from add-abstract-object-callback nil)
                    )
                )
            )
        )

        ;;;; [SC] if true then reference chunk has visual-object chunk-type
        ;;;; [SC] creating abstract chunk slot specification by combining slot values of both reference chunk and chunk specification
        ;;;; [SC] chunk specification slot values override reference chunk slot values
        (if (and reference-chunk-name (equal (chunk-chunk-type-fct reference-chunk-name) 'visual-object))
            (let ((ref-slot-names (chunk-type-slot-names-fct (chunk-chunk-type-fct reference-chunk-name))))
                ;;;; [SC] creating chunk definition with slot values
                (dolist (ref-slot-name ref-slot-names)
                    (let ((ref-slot-val (chunk-slot-value-fct reference-chunk-name ref-slot-name)))
                        ;;;; [SC] making sure that ref-slot-name slot has non nil value
                        (if ref-slot-val
                            (cond
                                ;;;; [SC] this is screen-pos slot, and chunk specification does not have valid position specified
                                ((equal ref-slot-name 'screen-pos)
                                    (if
                                        (and
                                            (chunk-type-subtype-p-fct (chunk-chunk-type-fct ref-slot-val) 'feature-location)
                                            (or (not (slot-in-chunk-spec-p main-specs 'screen-x)) (not (slot-in-chunk-spec-p main-specs 'screen-y)))
                                        )

                                        (let ((xy-loc (xy-loc ref-slot-val)))
                                            (setf slot-specs (delete-slot-spec slot-specs '(screen-x screen-y)))

                                            (push (list '= 'screen-x (aref xy-loc 0)) slot-specs)
                                            (push (list '= 'screen-y (aref xy-loc 1)) slot-specs)
                                        )
                                    )
                                )

                                ;;;; [SC] chunk specification does not have value specification for this slot
                                ((not (slot-in-chunk-spec-p main-specs ref-slot-name))
                                    ;;;; [SC] use the value that is within reference chunk
                                    (push (list '= ref-slot-name ref-slot-val) slot-specs)
                                )
                            )
                        )
                    )
                )
            )
        )

        ;;;; [SC] deciding whether an explicit chunk name should be used
        (cond
            ;;;; [SC] parameter chunk-name has value and a chunk with the same name does not exist
            ((and abstract-chunk-name (not (chunk-p-fct (third abstract-chunk-name))))
                (setf abstract-chunk-name (third abstract-chunk-name))
            )

            ;;;; [SC] parameter chunk-name has value, but there is already a chunk with the same name
            ((and abstract-chunk-name (chunk-p-fct (third abstract-chunk-name)))
                (print-warning "Chunk with a name ~s already exists. Using default ACT-R naming convention to decide abstract object's name." (third abstract-chunk-name))
                (setf abstract-chunk-name nil)
            )
        )

        ;;;; [SC] by this point there should be a complete definition of an abstract visual object chunk
        (add-abstr-vis-object-to-vstm paav-mod slot-specs reference-chunk-name abstract-chunk-name)
    )

    ;;;; [TODO] set buffer flags to proper values
)

;;;; [SC][2013.12.23][ENABLE-VSTM] prints content of visual short-term memory
(defun print-vstm ()
    (verify-current-mp
        "get-matching-region is called with no current meta-process."
        (verify-current-model
            "get-matching-region is called with no current model."
            
            (let ((paav-mod (get-module :vision)))
                (if (enable-vstm paav-mod) ;; [SC][2013.12.20][ENABLE-VSTM]
                    (maphash 
                        #'(lambda (k v)
                            (format t "~a => ~a~%" k v)
                            (pprint-chunks-fct (list k))
                        )
                        (vstm-memory paav-mod)
                    )
                    (print-warning "Error in PRINT-VSTM function. Visual Short-Term Memory is not enabled.")
                )
            )
        )
    )
)

;;;;;; END: [HRM] Visual Short-Term Memory related functions and methods
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Eye tracking functions

(defun save-eye-protocols (save-path &optional (trial-id nil))
    (let ((paav-mod (get-module :vision)))
        (cond
            ((not paav-mod)
                (print-warning "Cannot find vision module!")
            )
            ((not (eye-tracking paav-mod))
                (print-warning "Eye tracking is not enabled!")
            )
            (t
                (with-open-file
                    (out save-path :direction :output :if-exists :supersede)
                    (with-standard-io-syntax
                        (if trial-id
                            (format out "EVENT~tTYPE~tX~tY~tTIMESTAMP~tTRIAL-ID~%")
                            (format out "EVENT~tTYPE~tX~tY~tTIMESTAMP~%")
                        )
                        (dolist (eye-protocol (reverse (eye-track-protocols paav-mod)))
                            (let ((curr-row ""))
                                (dolist (row-item eye-protocol)
                                    (if (string= curr-row "")
                                        (setf curr-row (concatenate 'string curr-row (to-string row-item)))
                                        (setf curr-row (concatenate 'string curr-row "~t" (to-string row-item)))
                                    )
                                )
                                    
                                (if trial-id 
                                    (setf curr-row (concatenate 'string curr-row "~t" (to-string trial-id)))
                                )
                                (format out (concatenate 'string curr-row "~%"))
                            )
                        )
                    )
                )
            )
        )
    )
)

(defun get-fx-ht-key (mode fx-id)
    (concatenate 'string "FX_" mode "_" (write-to-string fx-id))
)

(defmethod register-fx-start ((paav-mod paav-vis-mod))
    (let
        (
            (gaze-loc (gaze-loc paav-mod))
            (curr-time (mp-time-ms))
        )
        
        (setf (fx-counter paav-mod) (+ 1 (fx-counter paav-mod))) ; [SC] increment current fixation ID by one

        (push
            (list "FIXATION" "START" (aref gaze-loc 0) (aref gaze-loc 1) curr-time)
            (eye-track-protocols paav-mod)
        )
    )
)

(defmethod register-fx-end ((paav-mod paav-vis-mod))
    (let
        (
            (gaze-loc (gaze-loc paav-mod))
            (curr-time (mp-time-ms))
        )

        (push
            (list "FIXATION" "END" (aref gaze-loc 0) (aref gaze-loc 1) curr-time)
            (eye-track-protocols paav-mod)
        )
    )
)

(defun get-saccade-ht-key (mode sacc-id)
    (concatenate 'string "SACC_" mode "_" (write-to-string sacc-id))
)

(defmethod register-sacc-start ((paav-mod paav-vis-mod))
    (let
        (
            (gaze-loc (gaze-loc paav-mod))
            (curr-time (mp-time-ms))
        )
        
        (setf (sacc-counter paav-mod) (+ 1 (sacc-counter paav-mod))) ; [SC] increment current saccade ID by one

        (push
            (list "SACCADE" "START" (aref gaze-loc 0) (aref gaze-loc 1) curr-time)
            (eye-track-protocols paav-mod)
        )
    )
)

(defmethod register-sacc-end ((paav-mod paav-vis-mod))
    (let
        (
            (gaze-loc (gaze-loc paav-mod))
            (curr-time (mp-time-ms))
        )

        (push
            (list "SACCADE" "END" (aref gaze-loc 0) (aref gaze-loc 1) curr-time)
            (eye-track-protocols paav-mod)
        )
    )
)

;;;;;; END: Eye tracking functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Implementation of spreading activation from visual memory to declarative memory

;;;; [SC] in this the new implementation the visual spreading activation
;;;; 1. it assumes that activation is spread only from those elements that are in visual memory

;;;; [TODO] the visual memory should be removed of every invisible features before being used
;;;; [TODO] 2012.07.03: j count currently includes slots that have NIL as value; should those slots be excluded?

;;; Given chunk k with j slots the spreading activation for this chunk from iconic memory is calculated as: 
;;;    1. Calculating the fan for each unique slot value i in chunk k:
;;;        fan_i_k = slots_i * (1+slots_i_k)/(1+j)
;;;        slots_i - the number of slots in which i is the value across all chunks in visicon
;;;        slots_i_k - the number of slots in chunk k which have i as the value
;;;    2. Calculating the strength of association:
;;;        S_i_k = Wi * (S + ln(1+fan_i_k))
;;;            S: minimum associative strength; set with :visicon-mas parameter
;;;            Wi: weight of the feature of slot value i
;;;    3. Calculating total spreading activation from visicon for chunk k:
;;;        S_visicon = W * SumOf_i(S_i_k)
;;;            W: weight of association for chunks in visicon; set with :visicon-w

;;;; [SC][2013.12.23][ICONIC-NAME]
(defun count-fans-from-vm (dm-chunk-slot-val abstr-loc-slot-index iconic-memory-ht)
    (let ((fans 0))
        (if (chunk-p-fct dm-chunk-slot-val)
            
            ;;;; [SC] the DM chunk slot value is a chunk
            (maphash 
                #'(lambda (key value)
                    (declare (ignore key))
                    (let ((abstr-loc-slot-val (nth abstr-loc-slot-index value)))
                        (if (and (chunk-p-fct abstr-loc-slot-val) (eq-chunks-fct dm-chunk-slot-val abstr-loc-slot-val))
                            (setf fans (+ fans 1))
                        )
                    )
                )
                iconic-memory-ht
            )
            
            ;;;; [SC] the DM chunk slot value is not a chunk, but a lisp value
            (maphash 
                #'(lambda (key value)
                    (declare (ignore key))
                    (let ((abstr-loc-slot-val (nth abstr-loc-slot-index value)))
                        (if
                            (and
                                (not (chunk-p-fct abstr-loc-slot-val)) ; [SC] lisp value is expected at abstract location slot value; if value is a chunk then it is not considered
                                (equal abstr-loc-slot-val dm-chunk-slot-val) ; [SC] make sure that values in abstratc location and DM chunk slots are equal
                            )
                            (setf fans (+ fans 1))
                        )
                    )
                )
                iconic-memory-ht
            )
        )
        (return-from count-fans-from-vm fans)
    )
)

;;;; [SC][TODO] make sure that... make sure what? dude, you gotta elaborate!
(defmethod get-weights-and-fans-from-vm ((paav-mod paav-vis-mod) dm-chunk-slot-value)
    (let
        (
            (iconic-memory-ht (iconic-memory paav-mod))
            (abstr-loc-slot-index -1)
            (vw-feature-w nil)
        )
        (cond ; [SC] check the type of value in DM chunk slot
            ;;;; [SC] the slot value is a chunk
            ((chunk-p-fct dm-chunk-slot-value)
                (let ((value-chunk-type (chunk-chunk-type-fct dm-chunk-slot-value))) ; [SC] retrieve chunk type of DM chunk slot value
                    (case value-chunk-type    ; [SC] if chunk type is subtype of visual feature then count fans
                        ('color-feature
                            (setf abstr-loc-slot-index (get-feature-slot-index 'fcolor))
                            (setf vw-feature-w (vm-fcolor-w paav-mod))
                        )
                        ('shape-feature 
                            (setf abstr-loc-slot-index (get-feature-slot-index 'fshape))
                            (setf vw-feature-w (vm-fshape-w paav-mod))
                        )
                        ('shading-feature
                            (setf abstr-loc-slot-index (get-feature-slot-index 'fshading))
                            (setf vw-feature-w (vm-fshading-w paav-mod))
                        )
                        ('orientation-feature
                            (setf abstr-loc-slot-index (get-feature-slot-index 'forient))
                            (setf vw-feature-w (vm-forient-w paav-mod))
                        )
                        ('size-feature
                            (setf abstr-loc-slot-index (get-feature-slot-index 'fsize))
                            (setf vw-feature-w (vm-fsize-w paav-mod))
                        )
                    )
                )
            )
            ;;;; [SC] the slot value is not chunk, but also not equal to NIL; assumed to be a text so looking for a match among value slots of abstract-location chunks
            ((not (equal dm-chunk-slot-value 'NIL))
                (setf abstr-loc-slot-index (get-feature-slot-index 'value))
                (setf vw-feature-w (vm-ftext-w paav-mod))
            )
        )

        (if (/= abstr-loc-slot-index -1)
            (return-from get-weights-and-fans-from-vm 
                (list (count-fans-from-vm dm-chunk-slot-value abstr-loc-slot-index iconic-memory-ht) vw-feature-w)
            )
            (return-from get-weights-and-fans-from-vm (list 0 0))
        )
    )
)

;;;; [SC] calculate the amount of spreading activation from iconic memory to chunk in declarative memory
;;;; @dm-chunk - is a chunk in declarative memory
;;;; [SC][TODO][CORE][2014.01.15] make sure that the spreading activations are calculated correctly after introduced changes; compare with the PAAV without VSTM 
(defmethod calculate-vm-dm-sa ((paav-mod paav-vis-mod) dm-chunk-name)
    (let
        (
            (iconic-memory-ht (iconic-memory paav-mod)) ; [SC] getting iconic memory hash table
            (dm-chunk-slot-names (chunk-type-slot-names-fct (chunk-chunk-type-fct dm-chunk-name))) ; [SC] getting all slot names from DM chunk
            (unique-val-ht (make-hash-table :test #'equalp)) ; [SC] for each unique value in DM chunk this hashtable stores number of occurences in the DM chunk and fan from visual memory 
            (iconic-mem-mas (iconic-memory-mas paav-mod))
            (iconic-mem-w (iconic-memory-w paav-mod))
            (spread-activ 0)
        )

        ;;;; [SC] Checking if any of the slot values in dm-chunk is also slot value in any of the visual memory chunks
        (loop for dm-chunk-slot-name in dm-chunk-slot-names do
            (let ((dm-chunk-slot-value (chunk-slot-value-fct dm-chunk-name dm-chunk-slot-name)))
                (let ((existing-record (gethash dm-chunk-slot-value unique-val-ht)))
                    (if existing-record
                        
                        ;;;; [SC] the value record already exists (chunk has duplicated slot values)
                        ;;;; [SC] since value "i" already exists, just increment the slots_i_k
                        ;;;; [TEST]
                        (progn
                            (setf (nth 0 existing-record) (+ (nth 0 existing-record) 1))
                        )
                        
                        ;;;; [SC] the value record does not exists
                        ;;;; [SC] calculate the fan and store in hashtable as list record ([slot_i_k as 1] slot_i feature-weight) with value as a key
                        (let ((raw-fan-weight (get-weights-and-fans-from-vm paav-mod dm-chunk-slot-value)))
                            (setf (gethash dm-chunk-slot-value unique-val-ht) (push 1 raw-fan-weight))
                        )
                    )
                )
            )
        )
        
        ;;;; [SC] Calculating spreading activation based on dm-chunk slot values
        (let ((slot-count (length dm-chunk-slot-names))) ; [SC] getting a total number of slots "j" in DM chunk
            (maphash 
                #'(lambda (key value)
                    (setf spread-activ 
                        (+ spread-activ ; SumOf_i(S_i_k)
                            (* (nth 2 value) ; Wi * (S + ln(1 + fan_i_k))
                                (+ iconic-mem-mas ; [SC] S + ln(1 + fan_i_k)
                                    (log-coerced    ; [SC] ln(1 + fan_i_k)
                                        (+ 1 ; [SC] 1 + fan_i_k
                                            (*
                                                (nth 1 value) ; [SC] slots_i
                                                (/
                                                    (+ 1 (nth 0 value)) ; [SC] (1 + slots_i_k)
                                                    (+ 1 slot-count) ; [SC] (1 + j)
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
                unique-val-ht
            )
        )
        
        ;;;; [SC] Calculating spreading activation based on dm-chunk itself
        (let ((raw-fan-weight (get-weights-and-fans-from-vm paav-mod dm-chunk-name)))
            (setf spread-activ 
                (+ 
                    spread-activ 
                    (* 
                        (nth 1 raw-fan-weight)
                        (+ iconic-mem-mas (log-coerced (+ 1 (nth 0 raw-fan-weight))))
                    )
                )
            )
        )

        (return-from calculate-vm-dm-sa (* spread-activ iconic-mem-w))
    )
)

;;;; [SC] a spreading activaion offset function
;;;; [SC] to be set via (sgp :activation-offsets vm-dm-sa-offset)
(defun vm-dm-sa-offset (dm-chunk-name)
    (calculate-vm-dm-sa (get-module :vision) dm-chunk-name)
)

;;;;;; END: Implementation of spreading activation from visual memory to declarative memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Implementation of spreading activation from declarative memory to visual memory

;;;; [TODO]

;;;;;; END: Implementation of spreading activation from declarative memory to visual memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Implementation of visual regions

;;;; [NEW] [TEST]
(defun get-region-property (region-id)
    (verify-current-mp
        "get-region-property is called with no current meta-process."
        (verify-current-model
            "get-region-property is called with no current model."

            (let
                (
                    (device (current-device))
                    (paav-mod (get-module :vision))
                )

                (if device
                    (if paav-mod
                        (gethash region-id (vis-region-ht paav-mod))
                        (progn
                            (print-warning "get-region-property is called with no visual module.")
                        )
                    )
                    (progn
                        (print-warning "get-region-property is called with no current device.")
                    )
                )
            )
        )
    )
)

;;;; [SC] given single point returns region ID of the first visual region that contains it
;;;; [SC] returns nil of no region is found
;;;; [SC] [TEST]
(defun get-matching-region (x-loc y-loc)
    (verify-current-mp
        "get-matching-region is called with no current meta-process."
        (verify-current-model
            "get-matching-region is called with no current model."

            (let
                (
                    (device (current-device))
                    (paav-mod (get-module :vision))
                    (matching-region-id nil)
                    (matching-region-priority)
                )
                
                (if device
                    (if paav-mod
                        (progn
                            (maphash 
                                #'(lambda (region-id region-property)
                                    (let* 
                                        (
                                            (x-start (nth 0 region-property))
                                            (y-start (nth 1 region-property))
                                            (x-end (+ x-start (nth 2 region-property)))
                                            (y-end (+ y-start (nth 3 region-property)))
                                        )
                                        (if
                                            (and
                                                (>= x-loc x-start) (<= x-loc x-end)
                                                (>= y-loc y-start) (<= y-loc y-end)
                                            )
                                            (if
                                                (or
                                                    (not matching-region-id)
                                                    (< matching-region-priority (nth 4 region-property))
                                                )
                                                (progn
                                                    (setf matching-region-id region-id)
                                                    (setf matching-region-priority (nth 4 region-property))
                                                )
                                            )
                                        )
                                    )
                                )
                                (vis-region-ht paav-mod)
                            )
                            (return-from get-matching-region matching-region-id)
                        )
                        (progn
                            (print-warning "get-matching-region is called with no visual module.")
                        )
                    )
                    
                    (progn
                        (print-warning "get-matching-region is called with no current device.")
                    )
                )
            )
        )
    )
)

;;;; [SC] given an abstract-location and visual region's top-left and bottom-right coordinates 
;;;; [SC] returns T if top-left corner of the abstract-location is within the visual region
(defun within-vis-region (x-start y-start x-end y-end abstr-loc-name iconic-memory)
    (let ((abstr-loc (gethash abstr-loc-name iconic-memory)))
        (if abstr-loc
            (let
                (
                    (abstr-loc-x (get-abstr-loc-slot-val 'screen-x abstr-loc))
                    (abstr-loc-y (get-abstr-loc-slot-val 'screen-y abstr-loc))
                )
                
                (if
                    (and
                        (>= abstr-loc-x x-start) (<= abstr-loc-x x-end)
                        (>= abstr-loc-y y-start) (<= abstr-loc-y y-end)
                    )
                    (return-from within-vis-region t)
                    (return-from within-vis-region nil)
                )
            )
            (progn
                (return-from within-vis-region nil)
            )
        )
    )
)

;;;; [WORD] [NEW] [TODO] [TEST]
(defmethod get-query-matching-region-abstr-loc ((paav-mod paav-vis-mod) regions abstr-loc-name)
    (let
        (
            (iconic-memory (iconic-memory paav-mod))
            (vis-region-ht (vis-region-ht paav-mod))
        )

        (dolist (region regions)
            (if (eq '= (first region))
                (let ((vis-region (gethash (third region) vis-region-ht)))
                    (if vis-region
                        (let*
                            (
                                (x-start (nth 0 vis-region))
                                (y-start (nth 1 vis-region))
                                (x-end (+ x-start (nth 2 vis-region)))
                                (y-end (+ y-start (nth 3 vis-region)))
                            )

                            (if (within-vis-region x-start y-start x-end y-end abstr-loc-name iconic-memory)
                                (return-from get-query-matching-region-abstr-loc (third region))
                            )
                        )
                        (progn 
                            (print-warning "Invalid region ID ~a is supplied to :region parameter. Region parameter is ignored." (third region))
                        )
                    )
                )
            )
        )
        nil
    )
)

;;;; [WORD] [NEW] [TODO] [TEST]
(defmethod get-query-matching-region-cat-abstr-loc ((paav-mod paav-vis-mod) region-cats abstr-loc-name)
    (let
        (
            (iconic-memory (iconic-memory paav-mod))
            (vis-region-ht (vis-region-ht paav-mod))
        )

        (dolist (region-cat region-cats)
            (if (eq '= (first region-cat))
                (maphash 
                    #'(lambda (region-id vis-region)
                        (declare (ignore region-id))
                        (if (string-equal (nth 5 vis-region) (third region-cat)) ; [SC] the current region has a requested category
                            (let*
                                (
                                    (x-start (nth 0 vis-region))
                                    (y-start (nth 1 vis-region))
                                    (x-end (+ x-start (nth 2 vis-region)))
                                    (y-end (+ y-start (nth 3 vis-region)))
                                )

                                (if (within-vis-region x-start y-start x-end y-end abstr-loc-name iconic-memory)
                                    (return-from get-query-matching-region-cat-abstr-loc (third region-cat))
                                )
                            )
                        )
                    )
                    vis-region-ht
                )
            )
        )
        nil
    )
)

;;;; [SC] given list of abstract-location names and region request parameters (more than one is allowed)
;;;; [SC] returns the new list of abstract-locations that are within the requested region
;;;; [TODO] what if all region ID are invalid: currently returns just empty list
(defmethod get-matching-region-abstr-locs ((paav-mod paav-vis-mod) regions possible-chunks)
    (let
        (
            (iconic-memory (iconic-memory paav-mod))
            (matching-chunks nil)
            (vis-region-ht (vis-region-ht paav-mod))
        )

        (dolist (region regions)
            (let ((vis-region (gethash (third region) vis-region-ht)))
                (if vis-region
                    (let*
                        (
                            (x-start (nth 0 vis-region))
                            (y-start (nth 1 vis-region))
                            (x-end (+ x-start (nth 2 vis-region)))
                            (y-end (+ y-start (nth 3 vis-region)))
                        )
                        
                        (if (eq '= (first region))
                            (dolist (abstr-loc-name possible-chunks) ; [SC] consider only those chunks that are inside of the given region
                                (if (within-vis-region x-start y-start x-end y-end abstr-loc-name iconic-memory)
                                    (push abstr-loc-name matching-chunks)
                                )
                            )
                            (dolist (abstr-loc-name possible-chunks) ; [SC] consider all the chunks that are outside of given region
                                (if (not (within-vis-region x-start y-start x-end y-end abstr-loc-name iconic-memory))
                                    (push abstr-loc-name matching-chunks)
                                )
                            )
                        )
                    )
                    (progn 
                        (print-warning "Invalid region ID ~a is supplied to :region parameter. Region parameter is ignored." (third region))
                    )
                )
            )
        )
        (return-from get-matching-region-abstr-locs matching-chunks)
    )
)

;;;; [SC] given list of abstract-location names and region category request parameters (more than one is allowed)
;;;; [SC] returns the new list of abstract-locations that are within the requested region
;;;; [TODO] what if all region categories are invalid: currently returns just empty list
(defmethod get-matching-region-cat-abstr-locs ((paav-mod paav-vis-mod) region-cats possible-chunks)
    (let
        (
            (iconic-memory (iconic-memory paav-mod))
            (matching-chunks nil)
            (vis-region-ht (vis-region-ht paav-mod))
        )
        (dolist (region-cat region-cats)
            (maphash 
                #'(lambda (region-id vis-region)
                    (if (string-equal (nth 5 vis-region) (third region-cat)) ; [SC] the current region has a requested category
                        (let*
                            (
                                (x-start (nth 0 vis-region))
                                (y-start (nth 1 vis-region))
                                (x-end (+ x-start (nth 2 vis-region)))
                                (y-end (+ y-start (nth 3 vis-region)))
                            )
                            
                            (if (eq '= (first region-cat))
                                (dolist (abstr-loc-name possible-chunks) ; [SC] consider only those chunks that are inside of the given region
                                    (if (within-vis-region x-start y-start x-end y-end abstr-loc-name iconic-memory)
                                        (push abstr-loc-name matching-chunks)
                                    )
                                )
                                (dolist (abstr-loc-name possible-chunks) ; [SC] consider all the chunks that are outside of given region
                                    (if (not (within-vis-region x-start y-start x-end y-end abstr-loc-name iconic-memory))
                                        (push abstr-loc-name matching-chunks)
                                    )
                                )
                            )
                        )
                    )
                )
                vis-region-ht
            )
        )
        (return-from get-matching-region-cat-abstr-locs matching-chunks)
    )
)

;;;; [SC] prints information about available visual regions
(defun print-vis-region ()
    (verify-current-mp
        "print-vis-region is called with no current meta-process."
        (verify-current-model
            "print-vis-region is called with no current model."

            (let ((device (current-device)) (paav-mod (get-module :vision)))
                (if device
                    (if paav-mod
                        (maphash
                            #'(lambda (k v)
                                (format t "~a => ~a~%" k v)
                            )
                            (vis-region-ht paav-mod)
                        )

                        (progn
                            (print-warning "print-vis-region is called with no visual module.")
                        )
                    )
                    
                    (progn 
                        (print-warning "print-vis-region is called with no current device.")
                    )
                )
            )
        )
    )
)

;;;; [SC] removes the previously created visual region given its ID
(defun remove-vis-region (region-ID)
    (verify-current-mp  
        "remove-vis-region is called with no current meta-process."
        (verify-current-model
            "remove-vis-region is called with no current model."

            (let ((device (current-device)) (paav-mod (get-module :vision)))
                (if device
                    (if paav-mod
                        (if (not (remhash region-ID (vis-region-ht paav-mod)))
                            (progn
                                (print-warning "No region with given ID ~a was found." region-ID)
                            )
                        )

                        (progn
                            (print-warning "remove-vis-region is called with no visual module.")
                        )
                    )
                    
                    (progn 
                        (print-warning "remove-vis-region is called with no current device.")
                    )
                )
            )
        )
    )
)

;;;; [SC] creates a new visual region with given ID, top-left corner coordinate, width and height
(defun add-vis-region (region-ID x-loc y-loc width height &optional (priority 0) (category "DEFAULT"))

    (verify-current-mp  
        "add-vis-region is called with no current meta-process."
        (verify-current-model
            "add-vis-region is called with no current model."
        
            (let
                (
                    (device (current-device))
                    (paav-mod (get-module :vision))
                )

                (if device
                    (if paav-mod
                        (if 
                            (and
                                (integerp x-loc) (integerp y-loc) (integerp width) (integerp height)
                                (>= x-loc 0) (>= y-loc 0) (> width 0) (> height 0)
                            )
                            
                            (if
                                (and
                                    (>= (width device) (+ x-loc width))
                                    (>= (height device) (+ y-loc height))
                                )
                                
                                (let ((vis-region-ht (vis-region-ht paav-mod)))
                                    (setf (gethash region-ID vis-region-ht) (list x-loc y-loc width height priority category))
                                )
                                
                                (progn
                                    (print-warning "Visual region does not fit to the window.")
                                )
                            )
                            (progn 
                                (print-warning "All parameters for add-vis-region should be positive integer values.")
                            )
                        )
                        (progn
                            (print-warning "add-vis-region is called with no visual module.")
                        )
                    )
                    
                    (progn 
                        (print-warning "add-vis-region is called with no current device.")
                    )
                )
            )
        )
    )
)

;;;;;; END: Implementation of visual regions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Implementation of bottom-up activation and activation map in visual memory

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; ;;;;;; END: Implementation of bottom-up activation map based on contrast-based saliency (global dissimilaruty)

(defun create-fval-dissim-ht-key (feature-val-one feature-val-two)
    (list feature-val-one feature-val-two)
)

;;;; [TODO] check if provided feature type and values really exist
(defun get-feature-val-dissim (fval-dissim-ht feature-name feature-val-one feature-val-two)
    (if (and feature-val-one feature-val-two)
        (cond
            ;;;; [SC] if feature vlues have one of the feature types below then just assume that dissimilarity is 1
            ((or 
                (eq feature-name 'fshape) (eq feature-name 'fcolor)
                (eq feature-name 'fshading) (eq feature-name 'forient)
                (eq feature-name 'fsize))
                
                ;;;; [TODO] use chunk comparisons method
                (if (eq feature-val-one feature-val-two)
                    (return-from get-feature-val-dissim 0) ; [SC] if two values are the same then return 0 otherwise 1
                    (return-from get-feature-val-dissim 1)
                )
            )
            
            ;;;; [TODO]
            ;;;; [SC] if feature values have one of the feature types then assume that corresponding dissimilarity value is stored in fval-dissim-ht
            ;((or (eq feature-name 'fsize))
            ;    (let ((dissim-val (gethash ; [SC] retrieving dissimilarity-value for given pair of feature values
            ;                                (create-fval-dissim-ht-key feature-val-one feature-val-two) ; [SC] creating hashtable key
            ;                                fval-dissim-ht))
            ;            )
            ;        (if dissim-val
            ;            (return-from get-feature-val-dissim dissim-val)
            ;            (progn
            ;                (print-warning "No dissimilarity entry found for ~s and ~s" feature-val-one feature-val-two)
            ;            )
            ;        )
            ;    )
            ;)
        )
        (progn
            ;;;; [TODO] one of the features is NIL
            (return-from get-feature-val-dissim 0)
        )
    )
)

;;;; [SC] given two abstract-locations returns the dissimilarity value with respect to particular feature
(defun get-feature-val-dissim-loc (fval-dissim-ht feature-name abstr-loc-val-one abstr-loc-val-two)
    (let
        (
            (feature-val-one (get-abstr-loc-slot-val feature-name abstr-loc-val-one))
            (feature-val-two (get-abstr-loc-slot-val feature-name abstr-loc-val-two))
        )
    
        (get-feature-val-dissim fval-dissim-ht feature-name feature-val-one feature-val-two)
    )
)

;;;; [SC] the concept of bottom-up activation map borrowed from Guided Search 4.0 (Wolfe, 2007)
;;;; [SC] this function calculates the bottom-up activation of two abstract-locations 
;;;;            based on dissimilarity of the two with respect to feature values
(defun calculate-dissimilarity (fval-dissim-ht abstr-loc-val-one abstr-loc-val-two)
    ;;;; [SC] dist-factor is a square root of the linear (pixel) distance between centers of two abstract-locations
    (let
        (
            (dist-factor
                (get-distance-factor
                    (calculate-euclidean-distance 
                        (get-abstr-loc-center abstr-loc-val-one)
                        (get-abstr-loc-center abstr-loc-val-two)
                    )
                )
            )
        )
        
        (list 
            (/ (get-feature-val-dissim-loc fval-dissim-ht 'fcolor abstr-loc-val-one abstr-loc-val-two) dist-factor)
            (/ (get-feature-val-dissim-loc fval-dissim-ht 'fshape abstr-loc-val-one abstr-loc-val-two) dist-factor)
            (/ (get-feature-val-dissim-loc fval-dissim-ht 'fshading abstr-loc-val-one abstr-loc-val-two) dist-factor)
            (/ (get-feature-val-dissim-loc fval-dissim-ht 'forient abstr-loc-val-one abstr-loc-val-two) dist-factor)
            (/ (get-feature-val-dissim-loc fval-dissim-ht 'fsize abstr-loc-val-one abstr-loc-val-two) dist-factor)
        )
    )
)

;;;; [SC] the concept of bottom-up activation map borrowed from Guided Search 4.0 (Wolfe, 2007)
;;;; [SC] this function calculates the bottom-up activation for each abstract-location present in visual-memory
;;;; [TODO] more efficient code is required
(defmethod calculate-bottom-up-activation-map ((paav-mod paav-vis-mod))
    (let
        (
            (iconic-memory (iconic-memory paav-mod))
            (bottom-up-activ-ht (bottom-up-activ-ht paav-mod))
            (fval-dissim-ht (fval-dissim-ht paav-mod))
        )
        
        ;;;; [SC] at first clearing bottom-up activation table
        (clrhash bottom-up-activ-ht)
        
        (maphash 
            #'(lambda (abtsr-loc-name-one abstr-loc-val-one)
                ;;;; [SC] activ-vect is a list containing bottom-up activation with respect to each feature type
                ;;;; [SC] each activation value is calculated for each abstract-location 
                ;;;;             as a function of dissimilarity to all neighboring abstract-location and distance to them
                (let ((activ-vect nil))
                    (maphash
                        #'(lambda (abstr-loc-name-two abstr-loc-val-two)
                            (if (not (eq abtsr-loc-name-one abstr-loc-name-two)) ; [SC] making sure that the two abstract-locations are not the same
                                (progn
                                    ;;;; [SC] activation-components is a list of dissimilarity values with regard to color, shape, shading, orient and size
                                    (let
                                        (
                                            (activation-components (calculate-dissimilarity fval-dissim-ht abstr-loc-val-one abstr-loc-val-two))
                                            (counter 0)
                                        )

                                        (if activ-vect
                                            (progn
                                                (dolist (component activation-components)
                                                    (setf
                                                        (nth counter activ-vect)
                                                        (+ (nth counter activ-vect) (nth counter activation-components))
                                                    )
                                                    (setf counter (+ counter 1))
                                                )
                                            )
                                            (progn
                                                (setf activ-vect activation-components)
                                            )
                                        )
                                    )
                                )
                            )
                        )
                        iconic-memory
                    )
                    
                    ;;;; [SC] storing activation vector in bottom-up activation map
                    (setf (gethash abtsr-loc-name-one bottom-up-activ-ht) activ-vect)
                )
            )
            iconic-memory
        )
    )
)

;;;;;; ;;;;;; END: Implementation of bottom-up activation map based on contrast-based saliency (global dissimilaruty)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; ;;;;;; START: Implementation of top-down activation map based on similarity to the request parameters

;;;; [SC] a function to return similarity weight for given feature-name
;;;; [TODO] [TEST]
(defmethod get-feature-sim-weight ((paav-mod paav-vis-mod) feature-name)
    (case feature-name
        (fsize (fsize-sim-w paav-mod))
        (forient (forient-sim-w paav-mod))
        (fshape (fshape-sim-w paav-mod))
        (fshading (fshading-sim-w paav-mod))
        (fcolor (fcolor-sim-w paav-mod))
        (otherwise (default-sim-w paav-mod))
    )
)

;;;; [SC] utility function
(defun get-td-activ-record-elem-index (elem-name)
    (case elem-name
        (sim-records 0)
        (dist-factor 1)
    )
)

;;;; [SC] utility function
(defun get-td-sim-record-elem-index (elem-name)
    (case elem-name
        (feature-name 0)
        (sim-value 1)
    )
)

;;;; [SC] utility function: given top-down activation record and a feature name, returns similarity value for that feature
;;;; [SC] Returns: similarity value if feature is present or NIL otherwise
;;;; [TODO] need to check wehether valid feature-name is provided
(defun get-td-sim-value (top-down-activ-record feature-name)
    (let
        (
            (sim-records (nth (get-td-activ-record-elem-index 'sim-records) top-down-activ-record))
            (sim-value nil)
        )

        (dolist (sim-record sim-records)
            (if (eq (nth (get-td-sim-record-elem-index 'feature-name) sim-record) feature-name)
                (setf sim-value (nth (get-td-sim-record-elem-index 'sim-value) sim-record))
            )
        )
        sim-value
    )
)

;;;; [SC] converts all similarity values in top-down activation record to negative; used when dissimilarity parameter is provided in abstract-location request
(defun td-active-record-convert-to-negative (top-down-activ-record)
    (let ((sim-records (nth (get-td-activ-record-elem-index 'sim-records) top-down-activ-record)))
        (dolist (sim-record sim-records)
            (setf
                (nth (get-td-sim-record-elem-index 'sim-value) sim-record) 
                (- (nth (get-td-sim-record-elem-index 'sim-value) sim-record))
            )
        )
    )
    top-down-activ-record
)

;;;; [SC] returns sum of all top-down activation values
(defun td-active-record-get-similarity-sum (top-down-activ-record)
    (let
        (
            (sim-records (nth (get-td-activ-record-elem-index 'sim-records) top-down-activ-record))
            (similarity-sum 0)
        )

        (dolist (sim-record sim-records)
            (setf similarity-sum (+ similarity-sum (nth (get-td-sim-record-elem-index 'sim-value) sim-record)))
        )
        similarity-sum
    )
)

;;;; [SC] utility function: returns a test for a specified feature from the set provided in request parameters
(defun get-feature-test (feature-tests feature-name)
    (dolist (feature-test feature-tests)
        (if (eq (second feature-test) feature-name)
            (return-from get-feature-test feature-test)
        )
    )
    nil
)

;;;; [SC] checks if all features in current visual threshold are available within current feature test paramaters
;;;; [SC] if all features are available then returns a list of those feature names; otherwise returns a single name of the first unavailable feature
(defun is-comparable-current-relevancy-threshold (last-attended-relevancy feature-tests)
    (let
        (
            (sim-records (nth (get-td-activ-record-elem-index 'sim-records) last-attended-relevancy))
            (all-features '())
        )
        (dolist (sim-record sim-records)
            (let
                (
                    (target-feature (nth (get-td-sim-record-elem-index 'feature-name) sim-record))
                    (target-exists nil)
                )
                (dolist (feature-test feature-tests)
                    (if (eq (second feature-test) target-feature)
                        (progn
                            (setf target-exists t)
                            (push target-feature all-features)
                            (return)
                        )
                    )
                )
                (if (not target-exists)
                    (return-from is-comparable-current-relevancy-threshold target-feature)
                )
            )
        )
        all-features
    )
)

;;;; [SC] returns the sum of activation values for a given set of features from a given top-down activation record
(defun get-sum-of-threshold-features (top-down-activ-record feature-list)
    (let
        (
            (sim-records (nth (get-td-activ-record-elem-index 'sim-records) top-down-activ-record))
            (td-activ-sum 0)
        )
        (dolist (feature-name feature-list)
            (dolist (sim-record sim-records)
                (if (eq (nth (get-td-sim-record-elem-index 'feature-name) sim-record) feature-name)
                    (progn
                        (setf td-activ-sum (+ td-activ-sum (nth (get-td-sim-record-elem-index 'sim-value) sim-record)))
                        (return)
                    )
                )
            )
        )
        td-activ-sum
    )
)

;;;; [SC] the function calculates the similarity of given abstract-location to feature values supplied in abstract-location request
;;;; [SC] Returns top-down activation record: 
;;;; [SC]      (list (list '(feature-test1 similarity-value) '(feature-test2 similarity-value) ...) distance-factor-value)
;;;; [SC] Example of top-down activation record:
;;;; [SC]      (list (list '(fcolor 0.5) '(fshape 1)) 0.56)
;;;; [TODO] [PRIORITY] assumes that the consistency between feature type and feature value has been checked
(defmethod calc-abstr-loc-and-request-sim ((paav-mod paav-vis-mod) abstr-loc feature-tests)
    (let 
        (
            (sim-records nil)
            (dist-factor
                (get-distance-factor
                    (calculate-euclidean-distance 
                        (vector (get-abstr-loc-slot-val 'screen-x abstr-loc) (get-abstr-loc-slot-val 'screen-y abstr-loc))
                        (gaze-loc paav-mod)
                    )
                )
            )
        )

        (dolist (feature-test feature-tests)
            (let
                (
                    (operator (first feature-test))
                    (feature-type (second feature-test))
                    (feature-val (third feature-test))
                )
                
                (if feature-val ;;;; [SC] making sure that value is not NIL
                    (let
                        (
                            (abstr-loc-slot-val (get-abstr-loc-slot-val feature-type abstr-loc))
                            (sim-value nil)
                        )

                        (cond
                            ((eq '= operator)
                                (cond
                                    ((and abstr-loc-slot-val (eq abstr-loc-slot-val feature-val)) ; [SC] abstract-location has a matching value to the test
                                        ;;;; [TODO] maybe it is better to use dissimilarity between two features instead of 1
                                        (setf sim-value (* 1 (get-feature-sim-weight paav-mod feature-type)))
                                    )
                                    ((not abstr-loc-slot-val) ; [SC] the abstract-location slot has NIL
                                        (setf sim-value (* 0.5 (get-feature-sim-weight paav-mod feature-type)))
                                    )
                                    (t
                                        (setf sim-value 0)
                                    )
                                )
                            )
                            ((eq '- operator)
                                (cond
                                    ((and abstr-loc-slot-val (not (eq abstr-loc-slot-val feature-val))) ; [SC] abstract-location does not have a matching value to the test
                                        ;;;; [TODO] maybe it is better to use dissimilarity between two features instead of 1
                                        (setf sim-value (* 1 (get-feature-sim-weight paav-mod feature-type)))
                                    )
                                    ((not abstr-loc-slot-val) ; [SC] the abstract-location slot has NIL
                                        (setf sim-value (* 0.5 (get-feature-sim-weight paav-mod feature-type)))
                                    )
                                    (t
                                        (setf sim-value 0)
                                    )
                                )
                            )
                        )
    
                        (push (list feature-type sim-value) sim-records)
                    )
                )
            )
        )

        (list sim-records dist-factor)
    )
)

;;;; [SC] calculates similarity scores (for each feature value) for each abstract-location provided
;;;; [SC] returns a hashtable where key is abstract-location name and value is list of similarity scores
;;;; [TODO] [PRIORITY] assumes that operator types in feature types have been verified (only = or - should be allowed)
(defmethod calculate-top-down-activation-map ((paav-mod paav-vis-mod) matching-chunks feature-tests)
    ;;;; [DELETE]
    ;(if *print-flag* (format t "~%~%GETTING MOST SIMILAR WITH ~a~%" feature-tests))
    (let
        (
            (iconic-memory (iconic-memory paav-mod))
            (top-down-activ-ht (top-down-activ-ht paav-mod))
        )
        
        ;;;; [SC] at first clearing top-down activation table
        (clrhash top-down-activ-ht)

        (dolist (abstr-loc-name matching-chunks)
            (let ((abstr-loc (gethash abstr-loc-name iconic-memory)))
                
                ;;;; [SC] creating a similarity record in a hashtable
                (setf (gethash abstr-loc-name top-down-activ-ht)
                    (calc-abstr-loc-and-request-sim paav-mod abstr-loc feature-tests)
                )
            )
        )
    )
)

;;;; [SC] removes abstract-locations from top-down-activ-ht hashtable that do not match the relevancy criteria
;;;; [TODO] more precise solution would be considering relevancies for individual features
;;;; [TODO] also need assure that the query that resulted in encoding previous abstract-location should be as same as the query that for current abstract-location
;;;; [TODO] [TD-URGENT]
;;;; [TODO] [TD-URGENT] what to do with zero top down activation
;;;; [TEST]
(defmethod filter-by-top-down-relevancy ((paav-mod paav-vis-mod) relevancy-param feature-tests)
    (let
        (
            (operator (first relevancy-param))
            (relevancy-type (third relevancy-param))
            (top-down-activ-ht (top-down-activ-ht paav-mod))
            (last-attended-relevancy (last-attended-relevancy paav-mod))
            (abstr-loc-to-remove nil)
        )

        (if last-attended-relevancy
            (if (eq relevancy-type 'current)
                (progn
                    (let ((feature-list (is-comparable-current-relevancy-threshold last-attended-relevancy feature-tests)))
                        (if (listp feature-list) ; [SC] making sure that all feature types (exact feature valus are ignored) used to calculate current threshold are present within current feature tests
                            (let ((overall-threshold (td-active-record-get-similarity-sum last-attended-relevancy)))
                                (maphash
                                    #'(lambda (abstr-loc-name top-down-activ-record)
                                        ; [SC] calculating top-down overall activation of the current abstract-location; overall is not necessarily equal to total top-down activation
                                        (let ((overall-activation (get-sum-of-threshold-features top-down-activ-record feature-list)))
                                        
                                            (if
                                                (or 
                                                    (= 0 overall-activation) ; [SC] ignore all the locations that provide zero top-down activations
                                                    (and
                                                        ; [SC] only consider relevancy if the abstract-location's distance from gaze position is within the range of distace measured for previously encoded abstract location
                                                        (<= 
                                                            (nth (get-td-activ-record-elem-index 'dist-factor) top-down-activ-record)
                                                            (nth (get-td-activ-record-elem-index 'dist-factor) last-attended-relevancy)
                                                        )
                                                        (or 
                                                            (and 
                                                                (eq operator '>) ; [SC] higher relevancy
                                                                (<= overall-activation overall-threshold)
                                                            )
                                                            (and 
                                                                (eq operator '>=) ; [SC] equal or higher relevancy
                                                                (< overall-activation overall-threshold)
                                                            )
                                                            (and 
                                                                (eq operator '<) ; [SC] lower relevancy
                                                                (>= overall-activation overall-threshold)
                                                            )
                                                            (and 
                                                                (eq operator '<=) ; [SC] equal or lower relevancy
                                                                (> overall-activation overall-threshold)
                                                            )
                                                        )
                                                    )
                                                )
                                                (push abstr-loc-name abstr-loc-to-remove)
                                            )

                                        )
                                    )
                                    top-down-activ-ht
                                )
                            )
                            (progn
                                (print-warning "The requested parametere tests are not comparable with existing visual threshold. The ~s feature test is missing." feature-list)
                            )
                        )
                    )
                )
                (progn ; [SC] else it is a feature relevancy
                    (let ((sim-threshold (get-td-sim-value last-attended-relevancy relevancy-type)))
                        (if sim-threshold ; [SC] making sure that the relevant threshold for specified feature relevancy exists
                            (if (get-feature-test feature-tests relevancy-type) ; [SC] making sure that the relevant feature test exists among current request parameters
                                (maphash
                                    #'(lambda (abstr-loc-name top-down-activ-record)
                                        (if
                                            (or 
                                                (= 0 (get-td-sim-value top-down-activ-record relevancy-type)) ; [SC] ignore all the locations that provide zero top-down activations
                                                (and
                                                    ; [SC] only consider relevancy if the abstract-location's distance from gaze position is within the range of distace measured for previously encoded abstract location
                                                    (<= 
                                                        (nth (get-td-activ-record-elem-index 'dist-factor) top-down-activ-record)
                                                        (nth (get-td-activ-record-elem-index 'dist-factor) last-attended-relevancy)
                                                    )
                                                    (or 
                                                        (and 
                                                            (eq operator '>) ; [SC] higher relevancy
                                                            (<= (get-td-sim-value top-down-activ-record relevancy-type) sim-threshold)
                                                        )
                                                        (and 
                                                            (eq operator '>=) ; [SC] equal or higher relevancy
                                                            (< (get-td-sim-value top-down-activ-record relevancy-type) sim-threshold)
                                                        )
                                                        (and 
                                                            (eq operator '<) ; [SC] lower relevancy
                                                            (>= (get-td-sim-value top-down-activ-record relevancy-type) sim-threshold)
                                                        )
                                                        (and 
                                                            (eq operator '<=) ; [SC] equal or lower relevancy
                                                            (> (get-td-sim-value top-down-activ-record relevancy-type) sim-threshold)
                                                        )
                                                    )
                                                )
                                            )
                                            (push abstr-loc-name abstr-loc-to-remove)
                                        )
                                    )
                                    top-down-activ-ht
                                )
                                (progn 
                                    (print-warning "No test for ~s feature is provided to make comparison to the threshold." relevancy-type)
                                )
                            )
                            (progn
                                (print-warning "No visual threshold is available for ~s feature." relevancy-type)
                            )
                        )
                    )
                )
            )
            (progn
                (model-warning "No threshold is set; relevancy parameter is ignored.")
            )
        )
        (dolist (abstr-loc-name abstr-loc-to-remove)
            (remhash abstr-loc-name top-down-activ-ht)
        )
    )
)

;;;;;; ;;;;;; END: Implementation of top-down activation map based on similarity to the request parameters
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; [SC] returns distance factor: currently square root of the distance
;;;; [SC] distance factor is always >= 1
(defun get-distance-factor (distance)
    (+ 1 (sqrt distance))
)

;;;; [TODO] probably need to check whether the hashtable has any entries
;;;; [TODO] need some noise on combined activation noise?
;;;; [SC] returns a list of abstract-locations that have highest equal activation values
(defmethod get-most-activ-abstr-locs ((paav-mod paav-vis-mod))
    (let
        (
            (bottom-up-activ-ht (bottom-up-activ-ht paav-mod))
            (top-down-activ-ht (top-down-activ-ht paav-mod))
            (matching-chunks nil)
            (highest-activ nil)
        )

        (maphash
            #'(lambda (abstr-loc-name top-down-activ-record)
                (let
                    (
                        (current-activ nil)
                        (bottom-up-activ (apply '+ (gethash abstr-loc-name bottom-up-activ-ht))) ; [SC] summing bottom-up activations
                        (top-down-activ (td-active-record-get-similarity-sum top-down-activ-record)) ; [SC] summing top-down activations                    
                    )
                    
                    ;;;; [SC] weighting bottom-up and top-down activations
                    (setf bottom-up-activ (* bottom-up-activ (bottom-up-act-w paav-mod)))
                    (setf top-down-activ (* top-down-activ (top-down-act-w paav-mod)))
                    
                    ;;;; [SC] adding both activation values and some noise
                    (setf current-activ (+ bottom-up-activ top-down-activ))
                    
                    ;;;; [SC] adding some noise if unless vis-act-s is not set to 0
                    (if (not (= (vis-act-s paav-mod) 0))
                        (setf current-activ (+ current-activ (act-r-noise (vis-act-s paav-mod))))
                    )
                    
                    ;;;; [TODO] [SC] making sure that the activation will not be negative due to instanteneous noise component
                    (if (< current-activ 0)
                        (setf current-activ 0)
                    )

                    ;;;; [DELETE]
                    ;(if *print-flag* (format t "~a ~a ~%" abstr-loc-name current-activ))
                    
                    (if matching-chunks
                        (cond 
                            ((> current-activ highest-activ)
                                (setf matching-chunks nil)
                                (push abstr-loc-name matching-chunks)
                                (setf highest-activ current-activ)
                            )
                            ((= current-activ highest-activ)
                                (push abstr-loc-name matching-chunks)
                            )
                        )
                        
                        (progn
                            (push abstr-loc-name matching-chunks)
                            (setf highest-activ current-activ)
                        )
                    )
                )
            )
            top-down-activ-ht
        )
        matching-chunks
    )
)

;;;;;; END: Implementation of activation map in visual memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Implementation of extrafoveal vision and visual memory

;;;; [SC] visibility of the object in extra-foveal vision depends on: 
;;;;        1. eccentricity (distance in degrees of visual angle from the center of gaze)
;;;;        2. size of the object (also in degrees of visual angle)

;;;; [SC] following need to be considered
;;;;        how to calculate visibility of each individual feature in peripheral vision
;;;;        how to (do I really need to?) calculate an encoding time of each individual feature in peripheral vision
;;;;        how to implement influence of vision on decision making (spreading activation from visicon)
;;;;            do features have saliency values independent of parameters used to calculate visibility and encoding time
;;;;        how to implement influence of declarative memory on scanpath (spreading activation from DM to visicon)

;;;; [SC] [TODO] TEMP function only
;;;; [SC] returns acuity parameters in from of vector (a b v) (alpha bravo vega)
;;;; [TESTED]
(defmethod get-acuity-params ((paav-mod paav-vis-mod) feature-type)
    (case feature-type
        (color-feature (list (fcolor-acuity-a paav-mod) (fcolor-acuity-b paav-mod) 0))
        (shape-feature (list (fshape-acuity-a paav-mod) (fshape-acuity-b paav-mod) 0))
        (shading-feature (list (fshading-acuity-a paav-mod) (fshading-acuity-b paav-mod) 0))
        (orientation-feature (list (forient-acuity-a paav-mod) (forient-acuity-b paav-mod) 0))
        (size-feature (list (fsize-acuity-a paav-mod) (fsize-acuity-b paav-mod) 0))
    )
)

;;;; [SC] calculates the euclidean distance between two points
;;;; [TESTED]
(defun calculate-euclidean-distance-p (x1 y1 x2 y2)
    (expt (+ (expt (- x1 x2) 2) (expt (- y1 y2) 2)) 0.5)
)

(defmethod calculate-euclidean-distance ((loc-one vector) (loc-two vector))
    (calculate-euclidean-distance-p (aref loc-one 0) (aref loc-one 1) (aref loc-two 0) (aref loc-two 1))
)

(defmethod calculate-euclidean-distance ((loc-one list) (loc-two list))
    (calculate-euclidean-distance-p (nth 0 loc-one) (nth 1 loc-one) (nth 0 loc-two) (nth 1 loc-two))
)

;;;; [SC] borrowed from EMMA code 
(defun add-gaussian-noise (x stddev)
    "Adds pseudo-Gaussian noise to mean x with a given stddev."
    (let*
        (
            (v (* stddev stddev))
            (s (/ (sqrt (* 3.0 v)) pi))
        )

        (+ x (if (zerop s) 0 (act-r-noise s)))
    )
)

;;;; [SC] modified implementation of visual acuity function (Kieras, 2010)
;;;;        whether the object features are available (or even recognizable) in peripherial vision
;;;;        threshold = a * (e^2) - b * e
;;;;        P(available) = P(s + X > threshold)
;;;;        X ~ N(0, vs)
;;;;        
;;;;        e - eccentricity of an object (angular distance from current gaze position)
;;;;        s - angular size of an object (at least as I think)
;;;;        a, b, v - free parameters to be adjusted for each feature type
;;;;
;;;; [TESTED]
(defun calculate-threshold (e a b)
    (- (* a (expt e 2)) (* b e))
)

;;;; [SC] returns the noise component X
(defun get-noise (s v)
    (add-gaussian-noise 0 (* v s))
)

;;;; [SC] checks whether the feature is visible
;;;; [TESTED]
(defmethod is-visible ((paav-mod paav-vis-mod) feature-type-value s e)
    (let ((acuity-params (get-acuity-params paav-mod (chunk-chunk-type-fct feature-type-value))))
        (let
            (
                (threshold (calculate-threshold e (nth 0 acuity-params) (nth 1 acuity-params)))
                (X (get-noise s (nth 2 acuity-params)))
            )
            
            ;;;; [TODO] [TEMP][DELETE]
            ;(if *print-flag* (format t "Size: ~a; Threshold: ~a~%" s threshold))

            ;;;; [TODO] the noise component X is temporarily disabled
            (if (> s threshold) ; [TEMP]
                ;( > (+ s X) threshold) ; [TODO] decomment this line and remove TEMP line
                (return-from is-visible feature-type-value)
                (return-from is-visible nil)
            )
        )
    )
)

;;;; [SC] checks whether the value in value slot is visible
;;;; [NEW]
(defmethod is-visible-text ((paav-mod paav-vis-mod) e)
    (if (> (text-acuity-dist paav-mod) e)
        (return-from is-visible-text t)
        (return-from is-visible-text nil)
    )
)

(defun concat-two-symbols (symbol-a symbol-b)
    (intern (concatenate 'string (symbol-name symbol-a) (symbol-name symbol-b)))
)

;;;; [SC] this function receives an visual-location name (the value of visicon hashtable) and generates correspoding abstract-location name
;;;; [TESTED]
(defun get-abstract-location-name (visual-location-name extension)
    ;;;; [TODO] need to check whether the visual-location really exists in visicon
    (concat-two-symbols visual-location-name extension)
)

;;;; [SC] this function receives an abstract-location name and returns corresponding visual-location name (the value of visicon hashtable)
;;;; [TESTED]
(defun get-visual-location-name (abstract-location-name extension)
    ;;;; [TODO] check whether it is the valid abstract location name
    (let ((abstr-loc-name-str (symbol-name abstract-location-name)))
        (intern (subseq abstr-loc-name-str 0 (- (length abstr-loc-name-str) (length (symbol-name extension)))))
    )
)

;;;; [SC] utility function that creates a NEW registry entry
;;;; [TESTED]
(defun create-vm-registry-value (rv-time rv-x rv-y)
    ;;;; [SC] (list [update time] [x-loc] [y-loc] [entry time] [attended state])
    ;;;; [SC] for the new record the update time is same as the entry time
    (list rv-time rv-x rv-y rv-time *attended-new*)
)

;;;; [SC] utility function
;;;; [TESTED]
(defun get-vm-reg-value-index (item)
    (case item
        (rv-time 0)
        (rv-x 1)
        (rv-y 2)
        (rv-entry-time 3)
        (rv-attend-state 4)
    )
)

;;;; [SC] utility function
;;;; [TESTED]
(defun get-vm-reg-value-item (item registry-values)
    (nth (get-vm-reg-value-index item) registry-values)
)

;;;; [SC] utility function
;;;; [TESTED]
(defun set-vm-reg-value-item (item-val item registry-values)
    (setf (nth (get-vm-reg-value-index item) registry-values) item-val)
)

;;;; [SC] utility function
;;;; [TEST] [NEW]
(defun create-vm-registry-key (abstr-loc-name feature-name &optional chunk-kind)
    (if (eq feature-name 'value)
        (if chunk-kind
            (list abstr-loc-name feature-name chunk-kind)
            (progn
                (print-warning "~%Cannot create visual memory registy for VALUE slot in ~s. The value for chunk-kind is not supplied.~%" abstr-loc-name)
            )
        )
        (list abstr-loc-name feature-name)
    )
)

;;;; [SC] utility function
;;;; [TESTED]
(defun get-vm-reg-key-item (item registry-key)
    (case item
        (abstr-loc-name (nth 0 registry-key))
        (feature-name (nth 1 registry-key))
        (chunk-kind (nth 2 registry-key))
    )
)

;;;; [SC] creates the value list for attended state registry for an abstract-location
;;;; [WORD] [NEW]
(defun create-vm-loc-reg-value (rv-time)
    ;;;; [SC] (list [update time] [entry time] [attended state])
    (list rv-time rv-time *attended-new*)
)

;;;; [SC] utility function
;;;; [WORD] [NEW]
(defun get-vm-loc-reg-index (item)
    (case item
        (rv-update-time 0)
        (rv-entry-time 1)
        (rv-attend-state 2)
    )
)

;;;; [SC] utility function
;;;; [TESTED]
(defun get-vm-loc-reg-value (item registry-values)
    (nth (get-vm-loc-reg-index item) registry-values)
)

;;;; [SC] utility function
;;;; [TESTED]
(defun set-vm-loc-reg-value (item-val item registry-values)
    (setf (nth (get-vm-loc-reg-index item) registry-values) item-val)
)

;;;; [SC] utility function
;;;; [TODO] test
(defun get-loc-slot-name (slot-index)
    (nth slot-index *loc-slot-list*)
)

;;;; [SC] utility function
;;;; [TODO] test
(defun get-abstr-loc-slot-val (slot-name abstr-loc)
    (nth (get-feature-slot-index slot-name) abstr-loc)
)

;;;; [SC] utility function
;;;; [TODO] [TEST]
(defmethod get-abstr-loc-slot-value ((paav-mod paav-vis-mod) slot-name abstr-loc-name)
    (let ((abstr-loc (gethash abstr-loc-name (iconic-memory paav-mod))))    ; [SC] getting by name the abstract location slot value list from hashtable
        (if abstr-loc    ; [SC] checking if the abstract location slot value list exists
            (get-abstr-loc-slot-val slot-name abstr-loc)
            nil
        )
    )
)

;;;; [SC] utility function
;;;; [TODO] test; maybe change function name as well
(defun get-feature-slot-index (feature-name)
    (case feature-name
        (fsize 9)
        (forient 10)
        (fshape 12)
        (fshading 11)
        (fcolor 13)
        (value 3)
        (screen-y 7)
        (screen-x 8)
        (width 1)
        (height 2)
        (kind 5)
    )
)
;;;; [SC] a function to return acuity weight alpha given feature-name
;;;; [TODO] not used anywhere
(defmethod get-feature-acuity-weight-a ((paav-mod paav-vis-mod) feature-name)
    (case feature-name
        (fsize (fsize-acuity-a paav-mod))
        (forient (forient-acuity-a paav-mod))
        (fshape (fshape-acuity-a paav-mod))
        (fshading (fshading-acuity-a paav-mod))
        (fcolor (fcolor-acuity-a paav-mod))
        (otherwise (default-acuity-a paav-mod))
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; ;;;;;; START: block of methods to remove invisible abstract location features

;;;; [SC] check whether the feature has
;;;; [TESTED]
(defun is-decayed-feature (registry-value persist-time curr-gaze-x curr-gaze-y curr-actr-time)
    (let
        (
            (rv-time (get-vm-reg-value-item 'rv-time registry-value))
            (rv-x (get-vm-reg-value-item 'rv-x registry-value))
            (rv-y (get-vm-reg-value-item 'rv-y registry-value))
        )
        
        ;;;; [SC] checking whether gaze changed its position from time the value was added to hashtable
        ;;;;            if coordinates do not match then it means that feature is not visible amynore
        (if (not (and (equal rv-x curr-gaze-x) (equal rv-y curr-gaze-y)))
            ;;;; [SC] checking whether the registry entry is overdue the persistence time
            (if (> (- curr-actr-time rv-time) persist-time)
                (progn ; [TEMP]
                    ;;;; [DELETE]
                    ;(if *print-flag* (format t "Feature at (~a ~a) registered at ~a and decayed at ~a after ~a at (~a ~a)~%" rv-x rv-y rv-time curr-actr-time persist-time curr-gaze-x curr-gaze-y)) ; [TEMP]
                    (return-from is-decayed-feature t)
                )
            )
        )
        (return-from is-decayed-feature nil)
    )
)

;;;; [SC] for given abstract location and its feature that is not visible anymore it sets the feature slot value to nil
;;;; [TESTED]
(defun remove-invisible-feature (abstr-loc-name feature-name iconic-memory)
    
    ;;;; [DELETE]
    ;(if *print-flag* (format t "Deleting ~a from ~a~%" feature-name abstr-loc-name)) ; [TEMP]
    
    (let ((abstr-loc (gethash abstr-loc-name iconic-memory)))    ; [SC] getting by name the abstract location slot value list from hashtable 
        (if abstr-loc    ; [SC] checking if the abstract location slot value list exists
            (setf (nth (get-feature-slot-index feature-name) abstr-loc) nil)    ; [SC] setting the corresponding feature slot value to nil
        )
    )
)

;;;; [SC] removes the entries from registry which has expired the persistence time
;;;; [SC] @vm-feature-reg - registry hashtable; @vm-feature-keys-rem - list of registry keys that should be removed
;;;; [TESTED]
(defun remove-expired-registry-entries (vm-feature-reg vm-feature-keys-rem)
    (dolist (registry-key vm-feature-keys-rem)
        (remhash registry-key vm-feature-reg)
    )
)

;;;;;; ;;;;;; END: block of methods to remove invisible abstract location features
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; ;;;;;; START: block of methods to remove invisible abstract location from hashtable

;;;; [Ryan Hope][2013.04.09] a source code to purge the content of the iconic memory
(defmethod purge-abstract-locations ((paav-mod paav-vis-mod))
    (let
        (
            (iconic-memory (iconic-memory paav-mod))
            (vm-loc-reg (vm-loc-reg paav-mod))
        )
        (maphash 
            #'(lambda (abstr-loc-name abstr-loc-values)
                (declare (ignore abstr-loc-values))
                (remhash abstr-loc-name iconic-memory)
                (remhash abstr-loc-name vm-loc-reg)
            )
            iconic-memory
        )
    )
)

;;;; [SC] this function returns true the abstract-location was not updated from visicon for period of time that is above persistence-time
;;;; [WORD] [NEW]
(defmethod is-decayed-abstr-loc ((paav-mod paav-vis-mod) abstr-loc-name curr-actr-time)
    (let*
        (
            (vm-loc-reg (vm-loc-reg paav-mod))                    ; [SC] attended state registry for abstract location
            (persistence-time (persistence-time paav-mod))    ; [SC] persistence time for an abstract-loaction that is not in visicon anymore
            (last-update-time ; [SC] the time when the abstract-location was last updated from visicon
                (get-vm-loc-reg-value 'rv-update-time (gethash abstr-loc-name vm-loc-reg))
            )
        )
        (if (> (- curr-actr-time last-update-time) persistence-time)
            (return-from is-decayed-abstr-loc t)
            (return-from is-decayed-abstr-loc nil)
        )
    )
)

;;;; [SC] removes the abstract location entries from visual memory hashtable and registry location's attended states
;;;; [WORD] [NEW]
(defmethod remove-invisible-abstract-locations ((paav-mod paav-vis-mod))
    (let
        (
            (iconic-memory (iconic-memory paav-mod))    ; [SC] iconic-memory hash table representing visual memory
            (vm-loc-reg (vm-loc-reg paav-mod))    ; [SC] attended state registry for abstract location
            (abstr-locs-rem nil)                        ; [SC] the list that will contain the abstract locations that should be removed
            (curr-actr-time (mp-time-ms))
        )    
        
        ;;;; [SC] filling the list with keys of decayed abstract locations
        (maphash 
            #'(lambda (abstr-loc-name abstr-loc-values)
                (declare (ignore abstr-loc-values))
                (if (is-decayed-abstr-loc paav-mod abstr-loc-name curr-actr-time)    ; [SC] checks if abstract location has decayed
                    (push abstr-loc-name abstr-locs-rem)
                )
            )
            iconic-memory
        )
        
        ;;;; [SC] removing all abstract locations recorded in remove list from visual memory hashtable
        (dolist (abstr-loc-name abstr-locs-rem)
            (remhash abstr-loc-name iconic-memory)    ; [SC] removing from visual memory
            
            (remhash abstr-loc-name vm-loc-reg) ; [SC] removing from attended state registry
        )
    )
)

;;;;;; ;;;;;; END: block of methods to remove invisible abstract location from hashtable
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; ;;;;;; START: Implementation of visual memory buffer and query processing

(defun tstamp-elapsed-abstr-loc (attend-start-time)
    (- (mp-time-ms) attend-start-time)
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; ;;;;;; ;;;;;; START: Group of methods to set attended state for abstract location and its features to T

;;;; [SC] this is the method to set given feature attended state T for a given abstract-location
;;;; [TODO] [TEST]
(defun set-abstr-loc-feature-attend-t (key vm-feature-reg)
    (let ((reg-entry (gethash key vm-feature-reg)))
        ;;;; [SC] make sure that registry entry for given feature exists and its attended state is NEW
        (if reg-entry         
            (set-vm-reg-value-item t 'rv-attend-state reg-entry)
            
            (progn
                (print-warning "Error setting attended state to T for abstract-location feature ~s with registry values ~s" key reg-entry)
            )
        )
    )
)

;;;; [SC] this is the method to set all features available in VM for a given abstract-location to attended state T
;;;; [TODO] [TEST]
(defmethod set-abstr-loc-features-attended-t ((paav-mod paav-vis-mod) abstr-loc-name vm-feature-reg)
    (set-abstr-loc-feature-attend-t (create-vm-registry-key abstr-loc-name 'fcolor) vm-feature-reg)
    (set-abstr-loc-feature-attend-t (create-vm-registry-key abstr-loc-name 'fshape) vm-feature-reg)
    (set-abstr-loc-feature-attend-t (create-vm-registry-key abstr-loc-name 'fshading) vm-feature-reg)
    (set-abstr-loc-feature-attend-t (create-vm-registry-key abstr-loc-name 'fsize) vm-feature-reg)
    (set-abstr-loc-feature-attend-t (create-vm-registry-key abstr-loc-name 'forient) vm-feature-reg)

    ;;;; [SC] [NEW] checking whether the attended state should be changed for value slot as well
    (let ((chunk-kind (get-abstr-loc-slot-value paav-mod 'kind abstr-loc-name)))
        (if (eq chunk-kind 'text) ;[SC] if value of a VALUE slot is kind of text then it should be changed
            (set-abstr-loc-feature-attend-t (create-vm-registry-key abstr-loc-name 'value chunk-kind) vm-feature-reg)
        )
    )
)

;;;; [SC] this the main methods that set the attended state for abstract-location to T 
;;;; [SC] and then calls set-abstr-loc-features-attended-t to set corresponding feature states to T
;;;; [TODO] [TEST]
(defmethod set-abstr-loc-attended-t ((paav-mod paav-vis-mod) vis-loc-visicon-key)
    (let
        (
            (abstr-loc-name
                (get-abstract-location-name ; [SC] retrieving abstract-location name given visual-location name and extension
                    (gethash vis-loc-visicon-key (visicon paav-mod)) ; [SC] retrieving visual-location name given its value list
                    (abstr-loc-ext paav-mod)
                )
            )
        )
        (let ((registry-values (gethash abstr-loc-name (vm-loc-reg paav-mod))))
            (if registry-values ; [SC] make sure that registry entry exists for given abstract location
                (progn 
                    (set-vm-loc-reg-value t 'rv-attend-state registry-values)
                    (set-abstr-loc-features-attended-t paav-mod abstr-loc-name (vm-feature-reg paav-mod))
                )
                (progn
                    (print-warning "Error setting attended state to T for abstract-location ~s with registry values ~s" abstr-loc-name registry-values)
                )
            )
        )
    )
)
;;;;;; ;;;;;; ;;;;;; END: Group of methods to set attended state for abstract location and its features to T
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;; [SC] this function sets the attended state of the feature to NIL if its current state is NEW
;;;; [TODO] [TEST]
(defun set-abstr-loc-feature-attend-nil (key vm-feature-reg)
    (let ((reg-entry (gethash key vm-feature-reg)))
        ;;;; [SC] make sure that registry entry for given feature exists and its attended state is NEW
        (if (and reg-entry (eq (get-vm-reg-value-item 'rv-attend-state reg-entry) *attended-new*))
            (set-vm-reg-value-item nil 'rv-attend-state reg-entry)
        )
    )
)

;;;; [SC] sets attended state of all NEW features of given abstract-location to NIL
;;;; [TODO] [TEST]
(defmethod set-abstr-loc-features-attended-nil ((paav-mod paav-vis-mod) abstr-loc-name vm-feature-reg)
    (set-abstr-loc-feature-attend-nil (create-vm-registry-key abstr-loc-name 'fcolor) vm-feature-reg)
    (set-abstr-loc-feature-attend-nil (create-vm-registry-key abstr-loc-name 'fshape) vm-feature-reg)
    (set-abstr-loc-feature-attend-nil (create-vm-registry-key abstr-loc-name 'fshading) vm-feature-reg)
    (set-abstr-loc-feature-attend-nil (create-vm-registry-key abstr-loc-name 'fsize) vm-feature-reg)
    (set-abstr-loc-feature-attend-nil (create-vm-registry-key abstr-loc-name 'forient) vm-feature-reg)

    ;;;; [SC] [NEW] checking whether the attended state should be changed for value slot as well
    (let ((chunk-kind (get-abstr-loc-slot-value paav-mod 'kind abstr-loc-name)))
        (if (eq chunk-kind 'text) ;[SC] if value of a VALUE slot is kind of text then it should be changed
            (set-abstr-loc-feature-attend-nil (create-vm-registry-key abstr-loc-name 'value chunk-kind) vm-feature-reg)
        )
    )
)

;;;; [SC] checks if attended state of an abstract location should be changed from NEW to NIL
;;;; [SC] if state should be changed then it also changes the state of correspoding features from NEW to NIL
;;;; [TODO] [WORD] [NEW]
(defmethod check-new-abstr-loc ((paav-mod paav-vis-mod) abstr-loc-name loc-reg-values)
    (let
        (
            (attend-state (get-vm-loc-reg-value 'rv-attend-state loc-reg-values))
            (attend-time (get-vm-loc-reg-value 'rv-entry-time loc-reg-values))
        )

        (if
            (and
                (eq attend-state *attended-new*) ; [SC] check if attended state for abstract-location is NEW but the time span has elapsed
                (> (tstamp-elapsed-abstr-loc attend-time) (finst-span-abstr paav-mod))
            )

            (progn
                ;;;; [SC] setting the attended state for abstract-location to NIL
                (set-vm-loc-reg-value nil 'rv-attend-state loc-reg-values)

                ;;;; [SC] setting the corresponding features with attended state NEW to NIL
                (set-abstr-loc-features-attended-nil paav-mod abstr-loc-name (vm-feature-reg paav-mod))
            )
        )
    )
)

;;;; [SC] rules:
;;;;        1. if attended states for all features are set to NIL then abstract-location should also be set to NIL
;;;;        2. if attended states for all features is T then abstract-location should be set to T
;;;;        3. if at least one feature has attended state NEW then abstract-location should also be set to NEW with its timestamp also updated
(defmethod update-new-abstr-loc ((paav-mod paav-vis-mod))
    (maphash 
        #'(lambda (key value)
            (check-new-abstr-loc paav-mod key value)
        )
        (vm-loc-reg paav-mod)
    )
)

;;;; [SC] removes all abstract-locations from abst-loc-name-list that do not match the attended-feature state criteria for given feature
;;;; [SC] returns a new list that contains only matching abstract-locations names
(defmethod get-matching-attended-abstr-locs-feature ((paav-mod paav-vis-mod) abst-loc-name-list attended feature-name &optional chunk-kind) ;[NEW]
    (let
        (
            (vm-feature-reg (vm-feature-reg paav-mod))
            (attend-operator (first attended))
            (attend-state (third attended))
            (matching-abstr-locs nil)
            (abstr-loc-encode (abstr-loc-encode paav-mod))
        )
    
        (dolist (abstr-loc-name abst-loc-name-list)
            (let ((feature-reg-entry (gethash (create-vm-registry-key abstr-loc-name feature-name chunk-kind) vm-feature-reg))) ; [NEW]
                (if feature-reg-entry                    
                    (cond
                        ((eq attend-operator '=)
                            (cond
                                ((eq abstr-loc-encode abstr-loc-name)
                                    ;;;; [SC] do nothing since this abstract-location is still being encoded
                                )
                                ((eq (get-vm-reg-value-item 'rv-attend-state feature-reg-entry) attend-state)
                                    (push abstr-loc-name matching-abstr-locs)
                                )
                                ((and
                                    (eq attend-state *attended-nil*)
                                    (eq (get-vm-reg-value-item 'rv-attend-state feature-reg-entry) *attended-new*))

                                    (push abstr-loc-name matching-abstr-locs)
                                )
                            )
                        )
                        ((eq attend-operator '-)
                            ;;;; [TODO] [PRIORITY]
                        )
                    )
                    ;;;; [TODO] [PRIORITY] what if the feature is not visible?
                )
            )
        )
        matching-abstr-locs
    )
)

;;;; [SC] returns the list of abstract location names that match the given attended state criteria
(defmethod get-matching-attended-abstr-locs (attended (paav-mod paav-vis-mod))
    (let
        (
            (attend-operator (first attended))
            (attend-state (third attended))
            (matching-abstr-locs nil)
            (abstr-loc-encode (abstr-loc-encode paav-mod))
        )
        
        (maphash 
            #'(lambda (abstr-loc-name reg-entry)
                (cond
                    ((eq attend-operator '=)
                        (cond
                            ((eq abstr-loc-encode abstr-loc-name)
                                ;;;; [SC] do nothing since this abstract-location is still being encoded
                            )
                            ((eq (get-vm-loc-reg-value 'rv-attend-state reg-entry) attend-state)
                                (push abstr-loc-name matching-abstr-locs)
                            )
                            ((and
                                (eq attend-state *attended-nil*)
                                (eq (get-vm-loc-reg-value 'rv-attend-state reg-entry) *attended-new*))

                                (push abstr-loc-name matching-abstr-locs)
                            )
                        )
                    )
                    ((eq attend-operator '-)
                        ;;;; [TODO] [PRIORITY]
                    )
                )
            )
            (vm-loc-reg paav-mod)
        )
        matching-abstr-locs
    )
)

;;;; [SC] returns the list of all abstract location names that are currently in visual memory
;;;; [SC] this function is alternative to get-matching-attended-abstr-locs and is called if no attended state is given in request
(defmethod get-all-abstr-locs ((paav-mod paav-vis-mod))
    (let ((matching-abstr-locs nil))
        (maphash 
            #'(lambda (abstr-loc-name reg-entry)
                (declare (ignore reg-entry))
                (push abstr-loc-name matching-abstr-locs)
            )
            (vm-loc-reg paav-mod)
        )
        matching-abstr-locs
    )
)

;;;; [SC] a utility function to create hashtable from single abstract-location entry in visual memory
;;;; [SC] keys are names of the slots and values are slot values
;;;; [SC] this function is not really necessary and hashtable is created to reuse Dan's code
(defun create-abstr-loc-temp-ht (abstr-loc-name iconic-memory)
    (let
        (
            (abstr-loc-ht (make-hash-table :test #'equalp))
            (abstr-loc-values (gethash abstr-loc-name iconic-memory))
            (slot-index 0)
        )

        (dolist (abst-loc-val abstr-loc-values)
            (setf (gethash (get-loc-slot-name slot-index) abstr-loc-ht) abst-loc-val)
            (setf slot-index (+ slot-index 1))
        )
        (return-from create-abstr-loc-temp-ht abstr-loc-ht)
    )
)

;;;; [SC][2013.12.19] this functions is necessary because PAAV avoids creating any chunk abstract-location chunks until it is absolutely necessary
;;;; [SC] thus this function creates a hashtable that represents a dummy abstract-location chunk to compare it with the provided chunk specification (chunk-spec)
;;;; [TODO][2013.12.19][MANUAL] need to explore further how static chunk-type works to avoid unexpected conflicts
(defun match-abstr-loc-spec
    (iconic-memory abstr-loc-name chunk-spec
        &key
        (=test #'chunk-slot-equal) (-test #'chunk-slot-not-equal)
        (>test #'safe>) (>=test #'safe>=)
        (<test #'safe<) (<=test #'safe<=)
        (variable-char #\=)
    )

    (cond
        ((chunk-type-subtype-p-fct (chunk-spec-chunk-type chunk-spec) 'abstract-location)
            (handler-case 
                (test-chunk-slots
                    nil ; [SC][r1395] indicating that it is not a static chunk-type
                    (create-abstr-loc-temp-ht abstr-loc-name iconic-memory)
                    (act-r-chunk-spec-slots chunk-spec)
                    =test
                    -test
                    >test
                    >=test
                    <test
                    <=test
                    variable-char
                )
                (error (condition)
                    (print-warning "Error ~S encountered in matching abstract-location ~s." condition abstr-loc-name)
                )
            )
        )
        (t nil)
    )
)

;;;; [SC][2013.12.20] this function tries to find abstract-locations in iconic memory that match the slot specifications of a buffer request
(defun get-abstr-locs-matching-slots
    (iconic-memory abstr-loc-list chunk-spec
        &key 
        (=test #'chunk-slot-equal) (-test #'chunk-slot-not-equal) ;; [TODO][SC] these parameters do not received any value
        (>test #'safe>) (>=test #'safe>=) ;; [TODO][SC] these parameters do not received any value
        (<test #'safe<) (<=test #'safe<=) ;; [TODO][SC] these parameters do not received any value
        (variable-char #\=)
    )

    (verify-current-mp  
        "get-abstr-locs-matching-slots called with no current meta-process."
        (verify-current-model
            "get-abstr-locs-matching-slots called with no current model."

            (let ((found nil))
                (cond 
                    ((not (act-r-chunk-spec-p chunk-spec))
                        (print-warning "~s in variable CHUNK-SPEC is not a valid chunk specification in call to get-abstr-locs-matching-slots" chunk-spec)
                    )
                    ((listp abstr-loc-list)
                        (dolist (abstr-loc-name abstr-loc-list found)
                            (when 
                                (match-abstr-loc-spec iconic-memory abstr-loc-name chunk-spec 
                                    :=test =test :-test -test
                                    :>test >test :>=test >=test 
                                    :<test <test :<=test <=test
                                    :variable-char variable-char
                                )
                                (push abstr-loc-name found)
                            )
                        )
                    )
                    (t (print-warning "~S isa not a valid value for the :chunks keyword parameter to get-abstr-locs-matching-slots" abstr-loc-list))
                )
            )
        )
    )
)

;;;; [SC] this function tries to find abstract-locations in visual memory that match all specifications of a buffer request
;;;; [TODO] need to implement neares, lowest/highest, current constraints
(defmethod find-current-abstr-locs-with-spec ((paav-mod paav-vis-mod) spec)
    "Assume that it's a valid visual-location chunk-spec with at most 1 attended slot specification and one nearest spec"
    (let*
        (
            (main-spec (strip-request-parameters-from-chunk-spec spec))
            (attended
                (when (slot-in-chunk-spec-p spec :attended)
                    (car (chunk-spec-slot-spec spec :attended))
                )
            )
            (attended-fcolor
                (when (slot-in-chunk-spec-p spec :attended-fcolor)
                    (car (chunk-spec-slot-spec spec :attended-fcolor))
                )
            )
            (attended-fshape
                (when (slot-in-chunk-spec-p spec :attended-fshape)
                    (car (chunk-spec-slot-spec spec :attended-fshape))
                )
            )
            (attended-fshading
                (when (slot-in-chunk-spec-p spec :attended-fshading)
                    (car (chunk-spec-slot-spec spec :attended-fshading))
                )
            )
            (attended-forient
                (when (slot-in-chunk-spec-p spec :attended-forient)
                    (car (chunk-spec-slot-spec spec :attended-forient))
                )
            )
            (attended-fsize
                (when (slot-in-chunk-spec-p spec :attended-fsize)
                    (car (chunk-spec-slot-spec spec :attended-fsize))
                )
            )
            (relevancy ; [SC] assumed that relevancy has single specification
                (when (slot-in-chunk-spec-p spec :relevancy)
                    (car (chunk-spec-slot-spec spec :relevancy))
                )
            )
            (slots (chunk-spec-slot-spec main-spec))
            ; [TODO] this current marker is for visual location 
            ; (current (current-marker paav-mod))
            ; [TODO] this current type marker is for visual location
            ; (current-type (when current (chunk-chunk-type-fct current)))
            (nearest
                (when (slot-in-chunk-spec-p spec :nearest)
                    (car (chunk-spec-slot-spec spec :nearest))
                )
            )
            (min-max-tests nil)
            (iconic-memory (iconic-memory paav-mod))
            (feature-tests nil)
            (gaze-loc (gaze-loc paav-mod))
            (region
                (when (slot-in-chunk-spec-p spec :region)
                    (chunk-spec-slot-spec spec :region)
                )
            )
            (region-categories
                (when (slot-in-chunk-spec-p spec :region-category)
                    (chunk-spec-slot-spec spec :region-category)
                )
            )
        )

        ;;;; [TODO] this code uses the current visual location; need to provide equivalent for abstract-location 
        ;; Remap all current values to the current chunk
        #|(if current
            (dolist (x slots)
                (when (eq (third x) 'current)
                    (if (find (second x) (chunk-type-slot-names-fct current-type))
                        (if (and (eq (second x) 'value) (chunk-real-visual-value current)) 
                            (setf (third x) (chunk-real-visual-value current)) 
                            (setf (third x) (chunk-slot-value-fct current (second x)))
                        )
                        (progn
                            (print-warning "Current visual-location does not have a slot named ~S so it is ignored in the request."
                                (second x))
                            (setf slots (remove x slots))
                        )
                    )
                )
            )
            (dolist (x slots)
                (when (eq (third x) 'current)
                    (print-warning "There is no currently attended location.  So, request specifying ~S as current is being ignored."
                        (second x))
                    (setf slots (remove x slots))
                )
            )
        )|#
        
        ;;;; [SC] PAAV modified
        (dolist (x slots)
            
            ;; Remove all tests for highest and lowest for later
            (when (or (eq (third x) 'lowest) (eq (third x) 'highest))
                (push-last x min-max-tests)
                (setf slots (remove x slots))
            )

            ;;;; [SC] [PAAV]
            ;;;; [SC] removing all feature value tests
            ;;;; [SC] those tests will be done at very end of this method
            ;;;; [SC] rather than doing exact matching tests the relative similarity test will be done
            (when
                (or
                    (eq (second x) 'fcolor)
                    (eq (second x) 'fshape)
                    (eq (second x) 'fshading)
                    (eq (second x) 'forient)
                    (eq (second x) 'fsize)
                    (eq (second x) 'value) ;[SC][NEW]
                )

                (push-last x feature-tests)
                (setf slots (remove x slots))
            )
        )
    
        ;; update the finsts and new markers if attended is needed
        (when
            (or
                attended attended-fcolor attended-fshape
                attended-fshading attended-forient attended-fsize
            )
            
            ;;;; [SC] set all abstract location with attended state NEW to NIL if the timespan has expired
            (update-new-abstr-loc paav-mod)
            
            ;;;; [TODO] finsts will not be implemented?
            ; (check-finsts paav-mod)
        )
  
        ;; find the chunks that match
        (let
            (
                (possible-chunks 
                    (if attended
                        (get-matching-attended-abstr-locs attended paav-mod)
                        (get-all-abstr-locs paav-mod)
                    )
                )
                (changed nil)
            )

            ;;;; [SC] removing all abstract locations that do not match the criteria of region
            (if region
                (setf possible-chunks (get-matching-region-abstr-locs paav-mod region possible-chunks))
            )

            ;;;; [SC]
            (if region-categories
                (setf possible-chunks (get-matching-region-cat-abstr-locs paav-mod region-categories possible-chunks))
            )
            
            ;;;; [SC] removing all abstract locations that do not match the criteria of attended-feature state
            (if attended-fcolor
                (setf possible-chunks (get-matching-attended-abstr-locs-feature paav-mod possible-chunks attended-fcolor 'fcolor))
            )
            (if attended-fshape
                (setf possible-chunks (get-matching-attended-abstr-locs-feature paav-mod possible-chunks attended-fshape 'fshape))
            )
            (if attended-fshading
                (setf possible-chunks (get-matching-attended-abstr-locs-feature paav-mod possible-chunks attended-fshading 'fshading))
            )
            (if attended-forient
                (setf possible-chunks (get-matching-attended-abstr-locs-feature paav-mod possible-chunks attended-forient 'forient))
            )
            (if attended-fsize
                (setf possible-chunks (get-matching-attended-abstr-locs-feature paav-mod possible-chunks attended-fsize 'fsize))
            )
            
            ;;;; [NEW] [SC] [TODO] how exactly to handle the attended state?????
            ;(if attended-value
            ;    (setf possible-chunks (get-matching-attended-abstr-locs-feature paav-mod possible-chunks attended-fsize 'fsize)))
            
            ;;;; [SC] do not know yet what this code exactly does
            ;; Hack to reassign value slots as needed before testing
            #|(dolist (check possible-chunks)
                (when (chunk-real-visual-value check)
                    (push (cons check (chunk-slot-value-fct check 'value)) changed)
                    (fast-set-chunk-slot-value-fct check 'value (chunk-real-visual-value check))
                )
            )|#
            
            ;;;; [SC] the similarity calculation is way down there at the end
            (let
                (
                    (matching-chunks
                        (get-abstr-locs-matching-slots iconic-memory possible-chunks
                            (slot-specs-to-chunk-spec (chunk-spec-chunk-type main-spec) slots)
                            :variable-char #\&
                        )
                    )
                )

                ;; apply all of the lowest/highest constraints
                ;; in the order provided
                #|(dolist (x min-max-tests)
                    (let ((value nil)
                            (truth (first x))
                            (slot (second x))
                            (test (third x)))
                     
                        ;; find the min/max value
                        (dolist (y matching-chunks)
                            (let ((cur-val (fast-chunk-slot-value-fct y slot)))
                                (unless (numberp cur-val)
                                    (setf value :fail)
                                    (print-warning "Cannot apply ~S constraint because not all chunks have a numerical value." x)
                                    (return)
                                )
                                (when (or (null value) 
                                            (and (eq test 'lowest) (< cur-val value))
                                            (and (eq test 'highest) (> cur-val value)))
                                    (setf value cur-val)
                                )
                            )
                        )
                     
                        (setf matching-chunks 
                            (remove-if-not 
                                (lambda (z)
                                    (if (eq truth '=)
                                        (= value z)
                                        (not (= value z))
                                    )
                                )
                                matching-chunks :key (lambda (z) (fast-chunk-slot-value-fct z slot))
                            )
                        )
                    )
                )|#
                
                ;; if there's a nearest constraint then
                ;; apply that filter now
                (when (and nearest matching-chunks)
                             
                    (if 
                        (or
                            (eq (third nearest) 'current)
                            (eq (third nearest) 'current-x)
                            (eq (third nearest) 'current-y)
                            (and
                                (chunk-p-fct (third nearest))
                                (chunk-type-subtype-p-fct (chunk-chunk-type-fct (third nearest)) 'visual-location)
                            )
                        )
                  
                        (let
                            (
                                (value nil)
                                ;(truth (first nearest))
                                (test (third nearest))
                                (matches nil)
                                (current-loc
                                    (aif (current-marker paav-mod)
                                        it 
                                        (progn 
                                            (model-warning "No location has yet been attended so current is assumed to be at current gaze location. ~s" gaze-loc)
                                            (car (define-chunks-fct (list (list 'isa 'visual-location 'screen-x (aref gaze-loc 0) 'screen-y (aref gaze-loc 1)))))
                                        )
                                    )
                                )
                            )
                     
                            ;; find the min value
                            ;;;; [PAAV] modified hadling of nearest parameter
                            (dolist (y matching-chunks)
                                (let 
                                    (
                                        (cur-val 
                                            (cond 
                                                ((eq test 'current)
                                                    ;;;; [DELETE]
                                                    ;(if *print-flag* (format t "~a ~a" (vector (get-abstr-loc-slot-val 'screen-x (gethash y iconic-memory))
                                                    ;                                (get-abstr-loc-slot-val 'screen-y (gethash y iconic-memory)))
                                                    ;                    (xy-loc current-loc)))

                                                    (dist
                                                        (vector
                                                            (get-abstr-loc-slot-val 'screen-x (gethash y iconic-memory))
                                                            (get-abstr-loc-slot-val 'screen-y (gethash y iconic-memory))
                                                        )
                                                        (xy-loc current-loc)
                                                    )
                                                )
                                                ((eq test 'current-x)
                                                    (abs
                                                        (-
                                                            (get-abstr-loc-slot-val 'screen-x (gethash y iconic-memory))
                                                            (fast-chunk-slot-value-fct current-loc 'screen-x)
                                                        )
                                                    )
                                                )
                                                ((eq test 'current-y)
                                                    (abs
                                                        (-
                                                            (get-abstr-loc-slot-val 'screen-y (gethash y iconic-memory))
                                                            (fast-chunk-slot-value-fct current-loc 'screen-y)
                                                        )
                                                    )
                                                )
                                                (t
                                                    (dist
                                                        (vector
                                                            (get-abstr-loc-slot-val 'screen-x (gethash y iconic-memory))
                                                            (get-abstr-loc-slot-val 'screen-y (gethash y iconic-memory))
                                                        )
                                                        (xy-loc test)
                                                    )
                                                )
                                            )
                                        )
                                    )
                                    (if (or (null value) (< cur-val value))
                                        (progn
                                            (setf value cur-val)
                                            (setf matches (list y))
                                        )
                                        (when (= cur-val value)
                                            (push y matches)
                                        )
                                    )
                                )
                            )
                     
                            (setf matching-chunks matches)
                        )
                     
                        (progn
                            (print-warning "Nearest test in a visual-location request must be current or a chunk that is a subtype of visual-location.")
                            (print-warning "Ignoring nearest request for ~S." (third nearest))
                        )
                    )
                )
                
                ;; undo the value slots that were changed for matching purposes
                ;;;; [TODO] have no idea what this code does
                ;(dolist (restore changed)
                ;    (fast-set-chunk-slot-value-fct (car restore) 'value (cdr restore))
                ;)
                
                ;;;; [SC] calculating bottom-up activation map for all abstract-locations as a function of global contrast 
                ;;;; [SC] contrats is global since it is calculated using all abstract-locations available in visual memory
                ;;;; [TEST]
                (calculate-bottom-up-activation-map paav-mod)

                ;;;; [TEST]
                ;;;; [SC] calculating top-down activation map for chosen abstract-locations as a function of similarity to parameter tests
                (calculate-top-down-activation-map paav-mod matching-chunks feature-tests)
                
                ;;;; [DELETE]
                #|(if *print-flag*
                    (progn 
                        (format t "VISUAL MEMORY:~%")
                        (maphash #'(lambda (k v) (format t "~a => ~a~%" k v)) iconic-memory)
                    )
                )|#
                ;;;; [DELETE]
                #|(if *print-flag*
                    (progn 
                        (format t "BOTTOM-UP ACTIVATIONS:~%")
                        (maphash #'(lambda (k v) (format t "~a => ~a~%" k v)) (bottom-up-activ-ht paav-mod))
                    )
                )|#
                ;;;; [DELETE]
                #|(if *print-flag*
                    (progn 
                        (format t "TOP-DOWN ACTIVATIONS:~%")
                        (maphash #'(lambda (k v) (format t "~a => ~a~%" k v)) (top-down-activ-ht paav-mod))
                    )
                )|#

                (if relevancy
                    ;;;; [SC] removes abstract-locations from top-down-activ-ht that has lower top-down activation value than the relevancy value
                    ;;;; [SC] assumes that only one specification of relevancy is allowed
                    (filter-by-top-down-relevancy paav-mod relevancy feature-tests)
                )

                ;;;; [DELETE]
                #|(if *print-flag*
                    (progn 
                        (format t "TOP-DOWN ACTIVATIONS AFTER RELEVANCY TEST:~%")
                        (maphash #'(lambda (k v) (format t "~a => ~a~%" k v)) (top-down-activ-ht paav-mod))
                    )
                )|#
                
                ;;;; [SC] combining top-down and bottom-up activation maps
                (setf matching-chunks (get-most-activ-abstr-locs paav-mod))

                matching-chunks
            )
        )
    )
)

;;;; [SC] given list of abstract-location names it returns the one that has oldest update time of attended state in location registry hashtable
(defun get-oldest-abstr-loc (abstr-loc-list vm-loc-reg)
    (let
        (
            (old-time nil)
            (matches nil)
        )
          
        (dolist (abstr-loc-name abstr-loc-list)
            (let ((cur-time (get-vm-loc-reg-value 'rv-entry-time (gethash abstr-loc-name vm-loc-reg))))
                (if 
                    (and
                        cur-time
                        (or (null old-time) (> cur-time old-time))
                    )
                    (progn
                        (setf old-time cur-time)
                        (setf matches (list abstr-loc-name))
                    )
                    (when (= cur-time old-time)
                        (push abstr-loc-name matches)
                    )
                )
            )
        )
        matches
    )
)

;;;; [TODO] need a smart way to track the several abstract-location chunks created from the same abstract location
;;;; [TODO] using just ID is primitive
(defun get-abstr-loc-chunk-name (abstr-loc-name abstr-loc-id-ht)
    (let ((chunk-id (gethash abstr-loc-name abstr-loc-id-ht)))
        (if chunk-id
            (intern (concatenate 'string (symbol-name abstr-loc-name) "-" (write-to-string chunk-id)))
            (progn 
                (print-warning "Cannot find the chunk ID tracker record for abstract-location ~s." abstr-loc-name)
                nil
            )
        )
    )
)

;;;; [SC] updates the chunk-id in abstr-loc-id hashtable for given abstract-location
(defun update-abstr-loc-chunk-ID (abstr-loc-name abstr-loc-id-ht)
    (let ((chunk-id (gethash abstr-loc-name abstr-loc-id-ht)))
        (if chunk-id
            (setf (gethash abstr-loc-name abstr-loc-id-ht) (+ 1 chunk-id))
            (print-warning "Cannot find the chunk ID tracker record for abstract-location ~s." abstr-loc-name)
        )
    )
)

(defmethod define-slot-specification ((paav-mod paav-vis-mod) abstr-loc-name)
    (let
        (
            (abstr-loc-vals (gethash abstr-loc-name (iconic-memory paav-mod)))
            (slot-spec nil)
            (slot-counter 0)
        )

        (if abstr-loc-vals
            ;;;; [SC] adding slot values and slot names to chunk specification
            (dolist (slot-val abstr-loc-vals)
                
                (if slot-val ;;;; [SC] add the slot to specification only if its value is not NIL
                    (progn
                        (push slot-val slot-spec)
                        (push (get-loc-slot-name slot-counter) slot-spec)
                    )
                )

                (setf slot-counter (+ 1 slot-counter))
            )
            (print-warning "Cannot find abstract-location ~s in visual memory." abstr-loc-name)
        )

        (return-from define-slot-specification slot-spec)
    )
)

;;;; [SC] this function creates a abstract-location chunk from given abstract-location
(defmethod construct-abstr-loc-chunk ((paav-mod paav-vis-mod) abstr-loc-name slot-spec)
    (let
        (
            (abstr-loc-id-ht (abstr-loc-id paav-mod))
            (chunk-spec (copy-alist slot-spec))
            (new-chunk nil)
        )
            
        ;;;; [SC] adding chunk type and chunk name to chunk specification
        (push 'abstract-location chunk-spec)
        (push 'isa chunk-spec)
        ;;;; [SC] creating chunk name according to the ID stored in ID hash table
        (push (get-abstr-loc-chunk-name abstr-loc-name abstr-loc-id-ht) chunk-spec)
            
        ;;;; [SC] creating chunk from chunk specification
        (setf new-chunk (define-chunks-fct (list chunk-spec)))

        ;;;; [SC] since new chunk is successfully created updating the ID for the next possible chunk
        (update-abstr-loc-chunk-ID abstr-loc-name abstr-loc-id-ht)

        (return-from construct-abstr-loc-chunk (first new-chunk))
    )
)

;;;; [SC] this function constructs the chunk-specification that is further supplied to visual-location request
(defun construct-vis-loc-spec (slot-spec)
    (push 'visual-location slot-spec)
    (push 'isa slot-spec)

    (define-chunk-spec-fct slot-spec)
)

;;;; [SC] the visual memory content should be updated every time when saccade initiates or end
;;;; [SC] this function is assumed to be a one possibe point of saccade initiation
;;;; [SC] this function is called when the request is sent to abstract-location buffer
(defmethod find-abstract-location ((paav-mod paav-vis-mod) chunk-spec)
    ;;;; [SC] set all abstract location with attended state NEW to NIL if the timespan has expired
    (update-new-abstr-loc paav-mod)
    
    ;;;; [TODO] finsts will not be implemented?
    ; (check-finsts paav-mod)

    (let
        (
            (abstr-loc-name 
                (awhen 
                    (find-current-abstr-locs-with-spec paav-mod chunk-spec) ;;;; [SC] returns the list of abstract-locations that match all specifications
                    (random-item (get-oldest-abstr-loc it (vm-loc-reg paav-mod)))
                )
            )
        )
            
        (if abstr-loc-name
            (progn
                (let ((slot-spec (define-slot-specification paav-mod abstr-loc-name)))
                    (let 
                        (
                            (abstr-loc-chunk (construct-abstr-loc-chunk paav-mod abstr-loc-name slot-spec))
                            (vis-loc-spec (construct-vis-loc-spec slot-spec))
                            (top-down-activ-record (gethash abstr-loc-name (top-down-activ-ht paav-mod)))
                        )

                        (if abstr-loc-chunk
                            (progn

                                (setf (abstr-loc-failure paav-mod) nil)
                                
                                ;;;; [SC] a code to store the top-down activation value and distance factor for chosen abstract-location
                                ;;;; [SC] commented on 2012.01.03; this is an old code
                                ;(setf (last-located-relevancy paav-mod)
                                ;        (list (apply '+ (nth 0 top-down-activ-record))
                                ;                (nth 1 top-down-activ-record))
                                ;)

                                ;;;; [SC] [NEW] [WORD] obtaining region-id and region category for chosen abstract location chunk
                                ;;;; [SC] those values will be later put in corresponding region and region-cat slots of visual-object chunk upon move-attention request
                                (let 
                                    (
                                        (regions 
                                            (when (slot-in-chunk-spec-p chunk-spec :region)
                                                (chunk-spec-slot-spec chunk-spec :region)
                                            )
                                        )
                                        (region-cats 
                                            (when (slot-in-chunk-spec-p chunk-spec :region-category)
                                                (chunk-spec-slot-spec chunk-spec :region-category)
                                            )
                                        )
                                    )

                                    (setf (last-located-region-info paav-mod)
                                        (list 
                                            (get-query-matching-region-abstr-loc paav-mod regions abstr-loc-name)
                                            (get-query-matching-region-cat-abstr-loc paav-mod region-cats abstr-loc-name)
                                        )
                                    )
                                )

                                ;;;; [DELETE]
                                ;(if *print-flag* 
                                ;    (format t "FIND ABSTR-LOC: ~a ~%" (last-located-region-info paav-mod))
                                ;)

                                (setf (last-located-relevancy paav-mod) (copy-list top-down-activ-record))

                                (schedule-set-buffer-chunk 'abstract-location abstr-loc-chunk 0 :module :vision :priority 10)
                                
                                (lock-device (current-device-interface)) ; [TODO] do I need to lock the device for abstract-location shift?
                                (schedule-event-relative 0 'unlock-device 
                                    :module :vision
                                    :destination :device
                                    :priority 9
                                    :output nil
                                    :maintenance t
                                )
                                
                                (if vis-loc-spec
                                    ;;;; [TODO] need to change the chunk specification before calling this method
                                    (schedule-event-relative 0 'find-location
                                        :module :vision 
                                        :destination :vision 
                                        :details "Find-location" 
                                        :output 'medium
                                        :params (list vis-loc-spec)
                                    )
                                    
                                    (progn ; [TODO] what to do here if the visual location specification was not produced?
                                        (print-warning "Cannot produce visual location specification: ~a~%" slot-spec)
                                    )
                                )
                            )
                            (progn ; [TODO] what to do here if the visual location specification was not produced?
                                (print-warning "Cannot create chunk with abstract-location name ~a and slot specification ~a~%" abstr-loc-name slot-spec)
                            )
                        )
                    )
                )
            )
            ;;;; [TODO] this should be changed to abstract location failure
            (progn
                (setf (abstr-loc-failure paav-mod) t)
                (schedule-event-relative 0 'find-abtsr-loc-failure :module :vision :output 'low)
            )
        )

        ;;;; [TODO] the auto-attending is disabled
        ;(when (and loc (auto-attend paav-mod))
        ;    (schedule-event-relative 0 'visual-auto-attend :destination :vision :output t
      ;                         :module :vision :details (concatenate 'string "automatically attending " (symbol-name loc)))
        ;)
        
        abstr-loc-name ; [SC] this the return
    )
)

;;;; [TODO] [TEST]
(defun find-abtsr-loc-failure()
    "Dummy event function to signal a find-abstr-location failure in the trace"
    nil
)

;;;;;; ;;;;;; END: Implementation of visual memory buffer and query processing
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; ;;;;;; START: Implementation of visual memory encoding time



;;;;;; ;;;;;; END: Implementation of visual memory encoding time
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;; [TESTED]
(defmethod delete-decayed-features-from-iconic-memory ((paav-mod paav-vis-mod))
    (let
        (
            (curr-gaze-x (aref (gaze-loc paav-mod) 0))    ; [SC] x coordinate of a current gaze location
            (curr-gaze-y (aref (gaze-loc paav-mod) 1))    ; [SC] y coordinate of a current gaze location
            (iconic-memory (iconic-memory paav-mod))                ; [SC] iconic-memory hash table representing iconic memory
            (persist-time (persistence-time paav-mod))    ; [SC] the time after which the feature value should be erased from iconic-memory
            (vm-feature-reg (vm-feature-reg paav-mod))    ; [SC] registry of time when the abstract location feature entered or was updated in iconic-memory
            (vm-feature-keys-rem nil)                           ; [SC] list of registry entries that should be deleted
        )

        (maphash 
            #'(lambda (key value) 
                (if (is-decayed-feature value persist-time curr-gaze-x curr-gaze-y (mp-time-ms))
                    (progn
                        (remove-invisible-feature
                            (get-vm-reg-key-item 'abstr-loc-name key)
                            (get-vm-reg-key-item 'feature-name key) 
                            iconic-memory
                        )
                        (push key vm-feature-keys-rem)
                    )
                )
            )
            vm-feature-reg
        )
        
        ;;;; [SC] calling a method to remove abstract locations that have all features set to nil
        ;;;; [SC] it removes the abtract location from visual memory and its registry entry in attended state hashtable
        ;;;;                in other words the abstract locations that are not visible anymore
        (remove-invisible-abstract-locations paav-mod)

        ;;;; [SC] need to remove registry entries that are recorded in vm-feature-keys-rem
        ;;;;                clearing the registry from records of features that are not visible anymore
        (remove-expired-registry-entries vm-feature-reg vm-feature-keys-rem)
    )
)

;;;; [SC] adds or updates the visible feature entry in the registry table
;;;; [SC] the updated values are update time and gaze x,y position at updated time 
;;;; [TESTED]
(defun add-feature-to-registry (vm-feature-reg key new-value)
    
    ;;;; [DELETE]
    ;(if *print-flag* (format t "Adding ~a from ~a to feature registry~%" new-value key))

    (let ((old-value (gethash key vm-feature-reg)))
        (if old-value ; [SC] check if feature entry already exists in registry
            
            (progn ;;;; [SC] if it already exist then change the update time and x,y coordinates of gaze
                (set-vm-reg-value-item (get-vm-reg-value-item 'rv-time new-value) 'rv-time old-value)
                (set-vm-reg-value-item (get-vm-reg-value-item 'rv-x new-value) 'rv-x old-value)
                (set-vm-reg-value-item (get-vm-reg-value-item 'rv-y new-value) 'rv-y old-value)
                nil
            )
            
            (progn ;;;; [SC] feature entry does not exist so add new entry 
                (setf (gethash key vm-feature-reg) new-value)
                t
            )
        )
    )
)

;;;; [SC] This function 
;;;;        1. calculates which visual location features in visicon are visible from current gaze position
;;;;        2. generates corresponding abstract location records and stores in iconic-memory hashtable 
;;;;                (keys are abstract location names with list of slot values as values)
;;;;        3. the distance between visual-location and current gaze position is calculated based on:
;;;;                coordinates of the center of visual-location (NOT screen-x and screen-y) and (x, y) of gaze-loc variable of visual module
;;;; [TODO] this function should be called at saccade initiation and saccade end to simulate continuous stream of visual unput        
;;;; [TODO] note of consideration: i think it is still possible to use string keys for hashtable instead of symbols
;;;; [TODO] what if one of the feature values were not provided
;;;; [TODO] need to consider incremental update
;;;;                1. if some items in visual memory are not visible anymore then they should be deleted after some fixed time
;;;;                2. which items in are new
;;;; [NEW] [TEST]
(defmethod get-visible-visicon-chunks ((paav-mod paav-vis-mod))
    (let
        (
            (vis-loc-chunks (visicon-chunks paav-mod))        ; [SC] retrieveing visual-location chunks from visicon - those are values in visicon hashtable
            (start-loc-x (aref (gaze-loc paav-mod) 0))        ; [SC] x coordinate of a current gaze location
            (start-loc-y (aref (gaze-loc paav-mod) 1))        ; [SC] y coordinate of a current gaze location
            (iconic-memory (iconic-memory paav-mod))                ; [SC] iconic-memory hashtable representing visual memory
            (abstr-loc-ext (abstr-loc-ext paav-mod))        ; [SC] an extension that will be used to generate abstract location name from visual location name
            (vm-feature-reg (vm-feature-reg paav-mod))        ; [SC] registry of time when the abstract location entered or was updated in iconic-memory
            (vm-loc-reg (vm-loc-reg paav-mod))                ; [SC] abstract location attended state registry
            (abstr-loc-id-ht (abstr-loc-id paav-mod))        ; [SC] abstract location ID hashtable; tracks the ID number of next abstract location chunk to be created
            (curr-actr-time (mp-time-ms))
        )

        (loop for vis-loc-chunk in vis-loc-chunks do
            (let
                (
                    (width (chunk-slot-value-fct vis-loc-chunk 'width))
                    (height (chunk-slot-value-fct vis-loc-chunk 'height))
                    (x-loc (chunk-slot-value-fct vis-loc-chunk 'screen-x))
                    (y-loc (chunk-slot-value-fct vis-loc-chunk 'screen-y))
                    ;(distance (chunk-slot-value-fct vis-loc-chunk 'distance)) ; [TODO] to delete if not used
                    (kind (chunk-slot-value-fct vis-loc-chunk 'kind))
                    (s (chunk-slot-value-fct vis-loc-chunk 'size))        ; [SC] this is the s parameter
                    (fcolor (chunk-slot-value-fct vis-loc-chunk 'fcolor))
                    (fshape (chunk-slot-value-fct vis-loc-chunk 'fshape))
                    (fshading (chunk-slot-value-fct vis-loc-chunk 'fshading))
                    (forient (chunk-slot-value-fct vis-loc-chunk 'forient))
                    (fsize (chunk-slot-value-fct vis-loc-chunk 'fsize))
                )
                
                (let*
                    (
                        (vis-loc-center (get-vis-loc-center x-loc y-loc width height))
                        (x-loc-c (nth 0 vis-loc-center))
                        (y-loc-c (nth 1 vis-loc-center))
                        (gaze-distance (calculate-euclidean-distance-p x-loc-c y-loc-c start-loc-x start-loc-y)) ; [SC] calculating distance of a center of visual-location to current gaze position; distance is in pixels
                    )
                    
                    (let ((e (pm-pixels-to-angle gaze-distance)))    ; [SC] calculalting eccentricity value (e) which is angular gaze-distance
                        
                        ;;;; [DELETE]
                        ;(if *print-flag* (format t "~%~%~a ~a => ~a ~a => ~a ~a => ~a ~a~%" x-loc y-loc x-loc-c y-loc-c start-loc-x start-loc-y e s)) ;;;; [TEMP] to delete
                        ;(if *print-flag* (format t "Calculating visibility for ~a~%" vis-loc-chunk))

                        ;;;; [SC] (size width height value color kind distance screen-y screen-x fsize forient fshading fshape fcolor)
                        ;;;; [SC] creating list of values for slots in new abstract-location chunk
                        ;;;; [TODO] what if none of the features are visible? still create abstract location chunk with no features?
                        (let
                            (
                                (fcolor-vis (is-visible paav-mod fcolor s e))
                                (fshape-vis (is-visible paav-mod fshape s e))
                                (fshading-vis (is-visible paav-mod fshading s e))
                                (forient-vis (is-visible paav-mod forient s e))
                                (fsize-vis (is-visible paav-mod fsize s e))
                                (value-vis nil) ;[SC] [NEW]
                                (abstr-loc-name (get-abstract-location-name vis-loc-chunk abstr-loc-ext))

                                ;;;; [SC] boolean flags indicating whether any of this features are new and were not in visual memory
                                (fcolor-new nil) (fshape-new nil) (fshading-new nil) (forient-new nil) (fsize-new nil)    
                                (value-new nil) ;[SC] [NEW]
                            )

                            ;;;; [SC] [NEW] processing VALUE slot according to the type specified in KIND slot
                            (cond
                                ;;;; [SC] if the visual-location chunk is kind of text then identify whether value in VALUE slot is visible
                                ((and (eq kind 'text) (is-visible-text paav-mod e))
                                    ;;;; [SC] extracting value of a value slot
                                    ;;;; [SC] using chunk-real-visual-value because chunk-slot-value-fct returns fake value
                                    ;;;; [TODO] what if there is no text value provided
                                    ;;;; [TODO] why do I need these two call: chunk-real-visual-value and chunk-slot-value-fct
                                    (if (chunk-real-visual-value vis-loc-chunk)
                                        (setf value-vis (chunk-real-visual-value vis-loc-chunk))
                                        (setf value-vis (chunk-slot-value-fct vis-loc-chunk 'value))
                                    )
                                )
                                ;;;; [SC] for some other condition do it below
                                ;()e
                            )
                                    
                            ;;;; [SC] if a feature is visible then add registry record for the feature
                            (if fcolor-vis
                                (setf fcolor-new 
                                    (add-feature-to-registry 
                                        vm-feature-reg 
                                        (create-vm-registry-key abstr-loc-name 'fcolor)
                                        (create-vm-registry-value curr-actr-time start-loc-x start-loc-y)
                                    )
                                )
                            )
                            (if fshape-vis
                                (setf fshape-new 
                                    (add-feature-to-registry
                                        vm-feature-reg
                                        (create-vm-registry-key abstr-loc-name 'fshape) 
                                        (create-vm-registry-value curr-actr-time start-loc-x start-loc-y)
                                    )
                                )
                            )
                            (if fshading-vis
                                (setf fshading-new
                                    (add-feature-to-registry
                                        vm-feature-reg
                                        (create-vm-registry-key abstr-loc-name 'fshading) 
                                        (create-vm-registry-value curr-actr-time start-loc-x start-loc-y)
                                    )
                                )
                            )
                            (if forient-vis
                                (setf forient-new 
                                    (add-feature-to-registry
                                        vm-feature-reg
                                        (create-vm-registry-key abstr-loc-name 'forient) 
                                        (create-vm-registry-value curr-actr-time start-loc-x start-loc-y)
                                    )
                                )
                            )
                            (if fsize-vis
                                (setf fsize-new 
                                    (add-feature-to-registry 
                                        vm-feature-reg
                                        (create-vm-registry-key abstr-loc-name 'fsize)
                                        (create-vm-registry-value curr-actr-time start-loc-x start-loc-y)
                                    )
                                )
                            )

                            ;;;; [SC] [NEW]
                            (if value-vis
                                (setf value-new 
                                    (add-feature-to-registry
                                        vm-feature-reg
                                        (create-vm-registry-key abstr-loc-name 'value kind)
                                        (create-vm-registry-value curr-actr-time start-loc-x start-loc-y)
                                    )
                                )
                            )
                                    
                            ;;;; [SC] updating the visual memory with abstract location
                            ;;;; [TODO] what if the entry already exists => some more elegant code maybe, DUDE!!!!
                            (let ((abstr-loc (gethash abstr-loc-name iconic-memory)))
                                        
                                (if abstr-loc
                                    ;;;; [SC] if abstract location already exists then update it with visible features in visual memory
                                    ;;;; [SC] does not reset to NIL the features that are not visible anymore!!!
                                    (progn 
                                        (if fcolor-vis 
                                            (setf (nth (get-feature-slot-index 'fcolor) abstr-loc) fcolor-vis)
                                        )
                                        (if fshape-vis 
                                            (setf (nth (get-feature-slot-index 'fshape) abstr-loc) fshape-vis)
                                        )
                                        (if fshading-vis 
                                            (setf (nth (get-feature-slot-index 'fshading) abstr-loc) fshading-vis)
                                        )
                                        (if forient-vis 
                                            (setf (nth (get-feature-slot-index 'forient) abstr-loc) forient-vis)
                                        )
                                        (if fsize-vis 
                                            (setf (nth (get-feature-slot-index 'fsize) abstr-loc) fsize-vis)
                                        )
                                        ;;;; [SC] [NEW]
                                        (if value-vis
                                            (setf (nth (get-feature-slot-index 'value) abstr-loc) value-vis)
                                        )
                                        
                                        ;;;; [SC] updating the update time entry of the abstract-location registry
                                        ;;;; [SC] if abstract-loaction has a new feature then update locations attended state to NEW as well as its entry time
                                        ;;;; [WORD][NEW]
                                        (let ((registry-values (gethash abstr-loc-name vm-loc-reg)))
                                            (if registry-values
                                                (progn
                                                    (if (or fcolor-new fshape-new fshading-new forient-new fsize-new value-new) ;[SC][NEW]
                                                        (progn
                                                            (set-vm-loc-reg-value *attended-new* 'rv-attend-state registry-values)
                                                            (set-vm-loc-reg-value curr-actr-time 'rv-entry-time registry-values)
                                                        )
                                                    )
                                                    (set-vm-loc-reg-value curr-actr-time 'rv-update-time registry-values)
                                                )
                                                (progn
                                                    (print-warning
                                                        "Error changing registry entry for abstract-location ~s with registry values ~s in get-visible-visicon-chunks"
                                                        abstr-loc-name registry-values
                                                    )
                                                )
                                            )
                                        )
                                    )

                                    ;;;; [SC] abstract location does not exist in visual memory
                                    (progn 
                                        ;;;; [SC] creating record of abstract location in the visual memory hashtable
                                        (setf 
                                            (gethash abstr-loc-name iconic-memory)
                                            (list
                                                nil width height value-vis nil kind nil y-loc x-loc ;[SC][NEW]
                                                fsize-vis forient-vis fshading-vis fshape-vis fcolor-vis
                                            )
                                        )
                                                
                                        ;;;; [SC] creating record of abstract location in the attended state registry
                                        (setf (gethash abstr-loc-name vm-loc-reg) (create-vm-loc-reg-value curr-actr-time))
                                    )
                                )
                            )
                                    
                            ; [SC] creating abstract-location chunk ID tracker for this abstract location if tracker does not exist already
                            (let ((abstr-loc-id-entry (gethash abstr-loc-name abstr-loc-id-ht)))
                                (if (not abstr-loc-id-entry) ; [SC] make sure that there is no existing record for current abstract-location
                                    (setf (gethash abstr-loc-name abstr-loc-id-ht) 0) ; [SC] set the starting ID to 0
                                )
                            )
                        )
                    )
                )
            )
        )
    )
)

;;;;;; END: Implementation of extrafoveal vision and visual memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Gaze location related codes

;;;; [SC][2014.01.06] a utility function to print current gaze location
(defun print-gaze-loc ()
    (verify-current-mp
        "print-vis-region is called with no current meta-process."
        (verify-current-model
            "print-vis-region is called with no current model."
            (let ((gaze-loc (gaze-loc (get-module :vision))))
                (format t "CURRENT GAZE LOCATION IS AT (~s, ~s)" (aref gaze-loc 0) (aref gaze-loc 1))
            )
        )
    )
)

;;;; [SC] a method to set a current gaze location given list with x and y corrdinates
;;;; [TESTED]
(defmethod set-gaze-loc ((paav-mod paav-vis-mod) (newloc list))
    (set-gaze-loc paav-mod (coerce newloc 'vector))
)

;;;; [SC] a method to set a current gaze location given vector with x and y corrdinates
;;;; [TESTED]
(defmethod set-gaze-loc ((paav-mod paav-vis-mod) (newloc vector))
    (let
        (
            (window-width (width (current-device)))
            (window-height (height (current-device)))
            (x-loc (aref newloc 0))
            (y-loc (aref newloc 1))
        )

        (if
            (and 
                paav-mod window-width window-height
                (integerp x-loc) (integerp y-loc)
                (<= 0 x-loc) (<= 0 y-loc)
                (>= window-width x-loc) (>= window-height y-loc)
            )
            
            (setf (gaze-loc paav-mod) newloc)
            (print-warning "Cannot set gaze-location at given position: ~a" newloc)
        )
    )
  
    ;;;; [SC] EMMA borrowed codes
    ;;;; [SC] updates the visualization device with new location so it can be rendered correctly
    ;;;; [SC] this code is commented because probably I will not need it
    ;;;; [TODO] remove this code if not necessary; uncomment if EMMA is implemented
    #|(device-update-gaze-loc (device (current-device-interface)) newloc)
    (when (trace-eye-p eye-mod)
        (push (cons (mp-time) newloc) (eye-trace eye-mod)))|#
)

;;;; [SC] EMMA borrowed concept: 
;;;;                OLD: landing point of a saccade follows Gaussian distribution around the center point of visual-location with SD of (0.1 * saccade length in pixels)
;;;;           landing point x and y now follow Gaussian distribution around the center point of visual-location with SD of (0.5 * object width or height in pixels)
;;;; [TODO] [PRIORITY] TEST
(defmethod get-vis-loc-variable ((paav-mod paav-vis-mod) vis-loc)
    (let
        (
            (vis-loc-center
                (get-vis-loc-center 
                    (chunk-slot-value-fct vis-loc 'screen-x)
                    (chunk-slot-value-fct vis-loc 'screen-y)
                    (chunk-slot-value-fct vis-loc 'width)
                    (chunk-slot-value-fct vis-loc 'height)
                )
            )
            (window-width (width (current-device)))
            (window-height (height (current-device)))
            (gaze-noise-weight (gaze-noise-weight paav-mod)) ; [SC] the noise-weight has been changed from 0.1 to 0.5
        )
        
        (let
            (
                (vis-loc-x (round (nth 0 vis-loc-center)))
                (vis-loc-y (round (nth 1 vis-loc-center)))
            )
            
            (if (not (= gaze-noise-weight 0)) ; [SC] adding gaussian noises to x and y coordinates of a gaze's landing position
                (let 
                    (
                        (stddev-x (* gaze-noise-weight (chunk-slot-value-fct vis-loc 'width)))
                        (stddev-y (* gaze-noise-weight (chunk-slot-value-fct vis-loc 'height)))
                    )

                    (setf vis-loc-x (round (add-gaussian-noise vis-loc-x stddev-x))) ; [SC] adding noise from Gaussian distribution
                    (setf vis-loc-y (round (add-gaussian-noise vis-loc-y stddev-y))) ; [SC] adding noise from Gaussian distribution
                    
                    ; [SC] making sure the x coordinate does not go beyond window boundaries
                    (cond 
                        ((< vis-loc-x 0)
                            (setf vis-loc-x 0)
                        )
                        ((> vis-loc-x window-width)
                            (setf vis-loc-x window-width)
                        )
                    )
                    ; [SC] making sure the y coordinate does not go beyond window boundaries
                    (cond 
                        ((< vis-loc-y 0)
                            (setf vis-loc-y 0)
                        )
                        ((> vis-loc-y window-height)
                            (setf vis-loc-y window-height)
                        )
                    )
                )
            )
            
            (return-from get-vis-loc-variable (vector vis-loc-x vis-loc-y))
        )
    )
)

;;;;;; END: Gaze location related codes
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Variable encoding time



;;;;;; END: Variable encoding time
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: FUNCTIONS OVERRIDDEN FROM DEFAULT VISION MODULE

;;;; [SC] this function is changed to copy values from feature slot types to corresponding slots of visual object
;;;; [NEW] [WORD] [TEST]
(defun fill-default-vis-obj-slots (vis-obj vis-loc)
    (if 
        (and
            (chunk-p-fct vis-obj)
            (chunk-p-fct vis-loc)
            (chunk-type-subtype-p-fct (chunk-chunk-type-fct vis-obj) 'visual-object)
            (chunk-type-subtype-p-fct (chunk-chunk-type-fct vis-loc) 'visual-location)
        )
        ;;;; [SC] [NEW] [WORD]
        (let*
            (
                (region-info (last-attended-region-info (get-module :vision)))
                (region-id (nth 0 region-info))
                (region-cat (nth 1 region-info))
            )

            ;;;; [DELETE]
            ;(if *print-flag* (format t "VIS-OBJ: ~a ~a ~a~%" region-info region-id region-cat))

            ;;;; [SC] if region-id was not provided during abstract-loaction request then finding the first region containing the object
            (if (not region-id)
                (setf
                    region-id 
                    (get-matching-region 
                        (chunk-slot-value-fct vis-loc 'screen-x)
                        (chunk-slot-value-fct vis-loc 'screen-y)
                    )
                )
            )
            
            ;;;; [SC] if region-cat was not provided during abstract-loaction request then take the category of the first region indicated by region-id
            (if (not region-cat)
                (setf region-cat (nth 5 (get-region-property region-id)))
            )

            ;;;; [DELETE]
            ;(if *print-flag* (format t "~a ~a ~%" region-id region-cat)) ; [DELETE]

            (mod-chunk-fct vis-obj 
                `(height ,(chunk-slot-value-fct vis-loc 'height)
                    width ,(chunk-slot-value-fct vis-loc 'width)
                    color ,(chunk-slot-value-fct vis-loc 'color)
                    value ,(if (chunk-real-visual-value vis-loc)
                                (chunk-real-visual-value vis-loc)
                                (chunk-slot-value-fct vis-loc 'value))
                    ;;;; [SC] PAAV only values
                    fcolor ,(chunk-slot-value-fct vis-loc 'fcolor)
                    fshape ,(chunk-slot-value-fct vis-loc 'fshape)
                    fshading ,(chunk-slot-value-fct vis-loc 'fshading)
                    forient ,(chunk-slot-value-fct vis-loc 'forient)
                    fsize ,(chunk-slot-value-fct vis-loc 'fsize)
                    region , region-id
                    region-cat , region-cat
                    ;;;; [SC][HRM] related code
                    instance-id ,(chunk-slot-value-fct vis-loc 'instance-id)
                )
            )
        )
        (progn
            (print-warning "Invalid chunk passed to fill-default-vis-obj-slots ~S not updated using ~s." vis-obj vis-loc)
        )
    )
)

;;;; [SC] PAAV modified version of generic method
(defgeneric encoding-complete-paav (paav-mod loc-dmo scale last-loc-relevant relevancy-flag &key requested)
    (:documentation "When SACCADE-COMPLETE completes, focus on a place with this.")
)

;;;; [SC] last-loc-relevant is PAAV only parameter which indicates the top-down activation value of the abstract-location being encoded
(defmethod encoding-complete-paav ((paav-mod paav-vis-mod) loc scale last-loc-relevant relevancy-flag &key (requested t))
  
    (setf (moving-attention paav-mod) nil)
    (change-state paav-mod :exec 'free :proc 'free)
    (setf (current-marker paav-mod) loc)

    ;;;; [SC] [PAAV] no abstract location is being encoded anymore
    (setf (abstr-loc-encode paav-mod) nil)
  
    (let ((return-obj (get-obj-at-location paav-mod loc scale)))

        ;;;; [SC] don't need this anymore; clearing it and releasing for a next move attention request
        (setf (last-attended-region-info paav-mod) nil)

        ;;;; [DELETE]
        ;(format t "~%ENCODING-COMPLETE-PAAV: ~a" return-obj)
    
        (if return-obj
            (progn
                (set-attended paav-mod (chunk-visicon-entry return-obj))
                (attend-to-object paav-mod return-obj :requested requested)
                
                ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                ;;;;;; END: PAAV only codes or codes modified from default implementation
                
                ;;;; [DELETE]
                ;(if *print-flag* (format t "LAST ENCODED TOP-DOWN ACTIVATION: ~a~%" (last-attended-relevancy paav-mod)))
                ;(if *print-flag* (format t "CURRENT ENCODED TOP-DOWN ACTIVATION: ~a~%" last-loc-relevant))

                ;;;; [SC] if relevancy flag is set to T then store the top-down activation record of the encoded abstract-location
                (if (eq relevancy-flag 't)
                    ;;;; [SC] store top-down activation similarity as relevancy threshold only if at least one feature test was provided in the corresponding abstract-location request
                    (if (nth (get-td-activ-record-elem-index 'sim-records) last-loc-relevant)
                        (setf (last-attended-relevancy paav-mod) last-loc-relevant)
                        (progn
                            (print-warning "Cannot store relevancy. No feature parameters were provided in the abstract-location request.")
                        )
                    )
                )
                
                ;;;; [SC] [PAAV] set the attended state for corresponding abstract-location to T
                ;;;; [SC] it is important to call this method after updating the visual memory so that T state will not be changed immediately to NEW
                (set-abstr-loc-attended-t paav-mod (chunk-visicon-entry return-obj))

                ;;;; [DELETE]
                ;(if *print-flag* (format t "HERE1: ~a ~a" return-obj (chunk-visicon-entry return-obj)))
                
                ;;;;;; END: PAAV only codes or codes modified from default implementation
                ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                
                return-obj
            )
      
            (progn
                (clear-attended paav-mod)
                (setf (last-obj paav-mod) nil)
                (setf (attend-failure paav-mod) t)
      
                (schedule-event-relative 0 'no-visual-object-found :maintenance t :module :vision :output 'medium :details "No visual-object found")
      
                nil
            )
        )
    )
)

;;;; [SC] EMMA borrowed concept; calculates the saccade execution time given base execution time and saccade length
;;;; [SC] returned time is in seconds
;;;; [TODO] maybe add some noise from Gaussian distribution with SD of 1/3 of calculated execution time?
;;;; [TEST]
(defmethod calc-sacc-exec-time ((paav-mod paav-vis-mod) x-loc y-loc)
    (let
        (
            (sacc-base-exe (sacc-base-exe paav-mod))
            (sacc-rate (sacc-rate paav-mod))
            (gaze-loc (gaze-loc paav-mod))
        )
        
        (let
            (
                (angle-dist ; [SC] angular distance between between given coordinates and current gaze location
                    (pm-pixels-to-angle 
                        ; [SC] calculating pixel distance between given coordinates and current gaze location
                        (calculate-euclidean-distance-p x-loc y-loc (aref gaze-loc 0) (aref gaze-loc 0))
                    )
                )
            )

            (+ sacc-base-exe (* angle-dist sacc-rate))
        )
    )
)

;;;; [SC] [PAAV]
;;;; [TEST][SC][2013.04.12] scheduler stack overflow?
(defmethod saccade-complete ((paav-mod paav-vis-mod) loc scale new-gaze-loc last-loc-relevant relevancy-flag)
    
    ;;;; [SC] [PAAV] updating the eye location with new visual-location coordinates
    (set-gaze-loc paav-mod new-gaze-loc)
                
    ;;;; [SC] [PAAV] saccade end update of visual memory
    ;;;; [TODO]
    ;;;; [TEST][2013.0412][SC] maybe content conflict over here between iconic memory and visicon
    (get-visible-visicon-chunks paav-mod)

    (if (eye-tracking paav-mod)
        (progn
            ;;;; [TEST][2013.0412][SC] add test code here 5000 seconds
            ;;;; [SC] list of fixation start end recordings
            (register-sacc-end paav-mod)
            (register-fx-start paav-mod)
        )
    )

    ;;;; [SC][TEST][2013.04.12] event may not be scheduled correctly; time randomization may not work in high act-r time values
    ;;;; [SC][TEST][2013.04.12] last-loc-relevant may be stacking too high
    (schedule-event-relative
        (randomize-time (move-attn-latency-new paav-mod)) ; [SC] uses PAAV latency factor which is 0.05 by default
        'encoding-complete-paav
        :destination :vision
        :module :vision
        :params (list loc scale last-loc-relevant relevancy-flag)
        :details (concatenate 'string "ENCODING-COMPLETE " (symbol-name loc) " " (symbol-name scale))
        :output 'medium
    )
)

;;;; [SC] set abstr-loc-ext parameter with name of the abstract-location currently being encoded
;;;; [SC] this method is called by move-attention
(defmethod set-abstr-loc-attending ((paav-mod paav-vis-mod) loc scale)
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;;;;; START: [HRM]
    
    (let ((vis-loc-true-name (chunk-copied-from-fct loc))) ; [SC] retrieving visual-location's true name
        ;;;; [SC] if true then vis-loc-true-name still exists in visicon
        (if (find vis-loc-true-name (visicon-chunks paav-mod))
            (setf
                (abstr-loc-encode paav-mod)
                (get-abstract-location-name ; [SC] retrieving abstract-location name given visual-location name and extension
                    vis-loc-true-name 
                    (abstr-loc-ext paav-mod)
                )
            )
            (progn
                ;;;; [TODO]
            )
        )
    )

    ;;;;;; END: [HRM]
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
)

;;;; [SC] this method gets called when request [+visual> isa move-attention] is given
(defmethod move-attention ((paav-mod paav-vis-mod) &key location scale relevancy-flag)
    (let ((new-gaze-loc (get-vis-loc-variable paav-mod location))) ; [SC] [PAAV] calculating location for new gaze
        
        (if
            (and
                (eq (exec-s paav-mod) 'BUSY)  ; [SC] EMMA and default vision
                (not (tracked-obj-last-feat paav-mod))
            )
            
            (model-warning "Attention shift requested at ~S while one was already in progress." (mp-time))
            
            (progn

                (when (tracked-obj-last-feat paav-mod) (remove-tracking paav-mod)) ; [SC] EMMA and default vision
            
                (setf (moving-attention paav-mod) t)
                (clear-attended paav-mod) ; [SC] EMMA and default vision
                (setf (last-scale paav-mod) scale) ; [SC] EMMA and default vision
            
                (setf (attend-failure paav-mod) nil) ; [SC] EMMA and default vision
                
                ;;;; [SC] [PAAV] saccade start update of visual memory
                ;;;; [TODO]
                (get-visible-visicon-chunks paav-mod)
                
                (if (eye-tracking paav-mod)
                    (progn
                        (register-fx-end paav-mod)
                        (register-sacc-start paav-mod)
                    )
                )

                ;;;; [SC] [WORD] [NEW] this region info later on will be copy pasted to region and region-cat slots of visual-objetc chunk
                (setf (last-attended-region-info paav-mod) (copy-list (last-located-region-info paav-mod)))

                ;;;; [DELETE]
                ;(if *print-flag* 
                ;    (format t "MOVE-ATTENTION: located region - ~a; attended region ~a ~%" (last-located-region-info paav-mod) (last-attended-region-info paav-mod))
                ;)

                ;;;; [SC] [PAAV] No need to test for existence of an item in visicon the saccade should be executed anyway
                ;;;; [SC] correspondingly gaze position should be updated in any circumstances
                (schedule-event-relative 
                    (randomize-time 
                        ;;;; [SC] calculating saccade execution time
                        (calc-sacc-exec-time paav-mod (aref new-gaze-loc 0) (aref new-gaze-loc 1))
                    )
                    'saccade-complete
                    :destination :vision
                    :module :vision
                    :params (list location scale new-gaze-loc (copy-list (last-located-relevancy paav-mod)) relevancy-flag)
                    :details
                    (concatenate 
                        'string "SACCADE-COMPLETE AT GAZE LOCATION #(" 
                        (write-to-string (aref new-gaze-loc 0)) ", "
                        (write-to-string (aref new-gaze-loc 1))
                        ") AND TARGET LOCATION " (symbol-name location)
                    )
                    :output 'low
                )
                
                ;;;; [SC] [PAAV]
                (set-abstr-loc-attending paav-mod location scale)
                
                (setf (current-marker paav-mod) location) ; [SC] 
                ;; not being used right now (set-clof paav-mod (dmo-to-xy location))
                (change-state paav-mod :exec 'BUSY :proc 'BUSY)
            )
        )
    )
)

;;;; [TODO] what if not visual-locatin chunk was found at the requested coordinates?
(defmethod find-location ((paav-mod paav-vis-mod) chunk-spec)
    (update-new paav-mod)
    (check-finsts paav-mod)
  
    (let
        (
            (loc
                (awhen (find-current-locs-with-spec paav-mod chunk-spec)
                    (construct-location paav-mod (random-item (objs-max-val it 'chunk-visual-tstamp)) chunk-spec)
                )
            )
        )

        (if loc
            (progn
                (setf (loc-failure paav-mod) nil)

                (schedule-set-buffer-chunk 'visual-location loc 0 :module :vision :priority 10)
                (lock-device (current-device-interface))
                (schedule-event-relative 0 'unlock-device 
                    :module :vision
                    :destination :device
                    :priority 9
                    :output nil
                    :maintenance t
                )
            )
            (progn
                (setf (loc-failure paav-mod) t)
                (schedule-event-relative 0 'find-loc-failure :module :vision :output 'low)
            )
        )
        (when (and loc (auto-attend paav-mod))
            (schedule-event-relative 0 'visual-auto-attend
                :destination :vision
                :output t
                :module :vision 
                :details (concatenate 'string "automatically attending " (symbol-name loc))
            )
        )
        loc ; [SC] this the return
    )
)

;;;; [TODO] probably need to change the visual and visual-location buffer codes as well
;;;; [SC] it looks like this function is used to handle queries which are related to a buffer state
;;;;        [SC] the function does NOT handle buffer requests
;;;; [SC] added code to handle query for new abstract-location buffer
(defun query-vision-module (vis-mod buffer slot value)
    (case buffer
        (visual
            (cond 
                ((and (eq slot 'state) (eq value 'error))
                    (attend-failure vis-mod)
                )
                ((eq slot 'scene-change)
                    (let
                        (
                            (change-detect
                                (and
                                    (numberp (car (scene-change vis-mod)))
                                    (>= (car (scene-change vis-mod)) (change-threshold vis-mod))
                                    (<= (mp-time-ms) (+ (cdr (scene-change vis-mod)) (new-span vis-mod)))
                                )
                            )
                        )

                        (or (and change-detect value)
                            (null (or change-detect value))
                        )
                    )
                )
                ((eq slot 'scene-change-value)
                    (and
                        (numberp value)
                        (numberp (car (scene-change vis-mod)))
                        (>= (car (scene-change vis-mod)) value)
                    )
                )
                (t 
                    (generic-state-query vis-mod buffer slot value)
                )
            )
        )

        (visual-location
            (case slot
                (state
                    (case value
                        (busy nil) ;; visual-location requests are always free
                        (free t)
                        (error (loc-failure vis-mod))
                        (t
                            (print-warning "Invalid query made of the ~S buffer with slot ~S and value ~S" buffer slot value)
                        )
                    )
                )
                
                (attended
                    (let ((vis-loc-chunk (buffer-read 'visual-location)))
                        (when
                            (and 
                                vis-loc-chunk
                                (chunk-type-subtype-p-fct (chunk-chunk-type-fct vis-loc-chunk) 'visual-location)
                            )
                            (let*
                                (
                                    (old-loc (chunk-visicon-entry vis-loc-chunk))
                                    (loc (if (chunk-p-fct old-loc) old-loc vis-loc-chunk))
                                )
            
                                (update-new vis-mod)
                                (check-finsts vis-mod)
              
                                (test-attended (list '= :attended value) loc)
                            )
                        )
                    )
                )
            )
        )
        
        ;;;; [SC] PAAV only code
        ;;;; [SC] TODO need to finish the code
        (abstract-location
            (case slot
                (state
                    (case value
                        (busy nil) ;; abstract-location requests are always free
                        (free t)
                        (error (abstr-loc-failure vis-mod)) ; [TODO] change this line of code
                        (t
                            (print-warning "Invalid query made of the ~S buffer with slot ~S and value ~S" buffer slot value)
                        )
                    )
                )
                (attended
                    ;;;; [TODO]
                    #|(let ((vis-loc-chunk (buffer-read 'abstract-location)))
                        (when (and vis-loc-chunk (chunk-type-subtype-p-fct (chunk-chunk-type-fct vis-loc-chunk) 'abstract-location))
                            (let* ((old-loc  (chunk-visicon-entry vis-loc-chunk))
                                        (loc (if (chunk-p-fct old-loc) old-loc vis-loc-chunk)))
            
                                (update-new vis-mod)
                                (check-finsts vis-mod)
              
                                (test-attended (list '= :attended value) loc)
                            )
                        )
                    )|#
                )
            )
        )

        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;;;;; START: [HRM] related code

        ;;;; [TODO]
        (visual-memory
            (if (enable-vstm vis-mod) ;; [SC][2013.12.20][ENABLE-VSTM] making sure that VSTM functionality is enabled
                (case slot
                    (state
                        (case value
                            (busy nil) ;; always free
                            (free t)
                            (error 
                                (vstm-failure vis-mod)
                            )
                            (t 
                                (print-warning "Invalid query made of the ~S buffer with slot ~S and value ~S" buffer slot value)
                            )
                        )
                    )
                )

                nil ;; [SC] always return NIL if VSTM is disabled
            )
        )

        ;;;;;; END: [HRM] related code
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        ;;;; [SC] [END] PAAV only code
    )
)

;;;; [SC] this method is modified from its default implementation verify-single-explicit-value in "framework/misc-util.lisp"
(defun param-has-value (slot-specs module cmd slot)
    (if (zerop (length slot-specs))
        (print-warning "~a command to ~s module requires a value for the ~a slot." cmd module slot)
        t
    )
)

;;;; [SC] this method is modified from its default implementation verify-single-explicit-value in "framework/misc-util.lisp"
(defun param-has-single-spec (slot-specs module cmd slot)
    (if (> (length slot-specs) 1)
        (print-warning "~a slot may only be specified once in a ~a command to the ~s module." slot cmd module)
        t
    )
)

;;;; [SC] this method is modified from its default implementation verify-single-explicit-value in "framework/misc-util.lisp"
(defun params-have-valid-modif (slot-specs module cmd modif-list)
    (dolist (slot-spec slot-specs)
        (let ((invalid t))

            (dolist (modif modif-list)
                (if (eql modif (first slot-spec))
                    (setf invalid nil)
                )
            )

            (if invalid
                (progn
                    (print-warning 
                        "~a slot specification does not have a valid modifier in a ~a command to the ~s module." 
                        slot-spec cmd module
                    )
                    (return-from params-have-valid-modif nil)
                )
            )
        )
    )
    t
)

;;;; [SC] this method is modified from its default implementation verify-single-explicit-value in "framework/misc-util.lisp"
(defun params-are-explicit (slot-specs module cmd)
    (dolist (slot-spec slot-specs)
        (if (chunk-spec-variable-p (third slot-spec))
            (progn
                (print-warning 
                    "~a slot must be explict - not a variable in a ~a command to the ~s module." 
                    slot-spec cmd module
                )
                (return-from params-are-explicit nil)
            )
        )
    )
    t
)

;;;; [SC] checks if the parameters were provided valid values (used if possible values are retricted by a particular set indicated by value-list)
(defun params-have-valid-values (slot-specs module cmd value-list)
    (dolist (slot-spec slot-specs)
        (let ((invalid t))
            (dolist (value value-list)
                (if (eql value (third slot-spec))
                    (setf invalid nil)
                )
            )

            (if invalid
                (progn
                    (print-warning 
                        "~a slot specification does not have a valid value in a ~a command to the ~s module. Possible values are restricted to the following list ~a."
                        slot-spec cmd module value-list
                    )
                    (return-from params-have-valid-values nil)
                )
            )
        )
    )
    t
)

;;;; [TODO] probably need to change the visual and visual-location buffer codes as well
;;;; [SC] it looks like this function is used to handle queries which are related to a buffer state
;;;;        [SC] the function does NOT handle buffer requests
;;;; [SC] added code to handle query for new abstract-location buffer
(defmethod pm-module-request ((paav-mod vision-module) buffer-name chunk-spec)
    (case buffer-name
        (visual
            (when (visual-lock paav-mod)
                (setf (visual-lock paav-mod) nil)
                (schedule-event-relative 0 'unlock-device 
                    :module :vision
                    :destination :device
                    :priority :min
                    :output nil
                    :maintenance t
                )
            )

            (case (chunk-spec-chunk-type chunk-spec)
                (clear ;; replaces the implicit clear from -visual
                    (schedule-event-relative 0 'clear :module :vision :destination :vision :output 'low)
                )
                (clear-scene-change
                    (schedule-event-relative 0 'clear-scene-change :module :vision :destination :vision :output 'low)
                )
                (start-tracking
                    (schedule-event-relative 0 'start-tracking :destination :vision :module :vision :output 'medium)
                )
                (assign-finst
                    (let 
                        (
                            (object 
                                (if (slot-in-chunk-spec-p chunk-spec 'object)
                                    (verify-single-explicit-value 
                                        (chunk-spec-slot-spec chunk-spec 'object)
                                        :vision 'assign-finst 'object
                                    )
                                    nil
                                )
                            )
                            (location 
                                (if (slot-in-chunk-spec-p chunk-spec 'location)
                                    (verify-single-explicit-value 
                                        (chunk-spec-slot-spec chunk-spec 'location) 
                                        :vision 'assign-finst 'location
                                    )
                                    nil
                                )
                            )
                        )
          
                        (if (or object location)
                            (schedule-event-relative 0 'assign-finst 
                                :params (list paav-mod :object object :location location)
                                :module :vision
                                :output 'medium
                            )
                            (print-warning "An object or location is required for an assign-finst request")
                        )
                    )
                )
                (visual-object
                    (print-warning "Move attention requests are now done with an isa move-attention")
                )
                (move-attention
                    (let 
                        (
                            (sp 
                                (if (slot-in-chunk-spec-p chunk-spec 'screen-pos)
                                    (verify-single-explicit-value
                                        (chunk-spec-slot-spec chunk-spec 'screen-pos)
                                        :vision 'visual-object 'screen-pos
                                    )
                                    nil
                                )
                            )
                            (scale 
                                (if (slot-in-chunk-spec-p chunk-spec 'scale)
                                    (verify-single-explicit-value
                                        (chunk-spec-slot-spec chunk-spec 'scale) 
                                        :vision 'visual-object 'scale
                                    )
                                    nil
                                )
                            )
                            ;;;; [SC] PAAV related parameter
                            ;;;; [SC] a boolean parameter that indicates whether to store the current top-down activation as a threshold
                            (relevancy
                                (if (slot-in-chunk-spec-p chunk-spec :relevancy)
                                    (let ((slot-specs (chunk-spec-slot-spec chunk-spec :relevancy)))
                                        (multiple-value-bind (val valid)
                                            (if
                                                (and
                                                    (param-has-single-spec slot-specs :vision 'move-attention :relevancy) ; [SC] has single relevancy parameter specified
                                                    (param-has-value slot-specs :vision 'move-attention :relevancy) ; [SC] parameter have value specified
                                                    (params-have-valid-modif slot-specs :vision 'move-attention '(=)) ; [SC] parameter has equal only modification
                                                    (params-are-explicit slot-specs :vision 'move-attention) ; [SC] parameter has explicit value
                                                    (params-have-valid-values slot-specs :vision 'move-attention '(t nil)) ; [SC] parameter has either t or nil as a value
                                                )
                                                (values (third (car slot-specs)) t)
                                                nil
                                            )
                                            (declare (ignore val))
                                            valid
                                        )
                                    )
                                    :none
                                )
                            )
                        )

                        ; (when scale
                        ;     (print-warning "Scale values are not yet handled by the new vision module - ignoring it."))

                        (when sp
                            (if (not (null relevancy)) ; [SC] PAAV related condition for checking valid request parameter
                                (if (chunk-p-fct sp)
                                    (if (chunk-type-subtype-p-fct (chunk-chunk-type-fct sp) 'visual-location)
                                        (progn
                                            (schedule-event-relative 0 'move-attention 
                                                :params (list paav-mod :scale scale :location sp :relevancy-flag (if (eq relevancy :none) 'nil relevancy))
                                                :details  (concatenate 'string "Move-attention " (symbol-name sp) " " (symbol-name scale))
                                                :module :vision
                                            )
                                        )
                                        (print-warning "screen-pos value ~s in a move-attention request was not a visual-location chunk" sp)
                                    )
                                    (print-warning "screen-pos value ~s in a move-attention request was not a chunk" sp)
                                )
                                (print-warning "Invalid value in a request to the abstract-location buffer")
                            )
                        )
                    )
                )
                (t
                    (print-warning "Invalid command ~a sent to the visual buffer" 
                        (chunk-spec-chunk-type chunk-spec))
                )
            )
        )
    
        (visual-location
            (cond 
                ((chunk-type-subtype-p-fct (chunk-spec-chunk-type chunk-spec) 'visual-location)
                    (let 
                        (
                            (nearest
                                (if (slot-in-chunk-spec-p chunk-spec :nearest)
                                    (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :nearest)
                                            :vision 'visual-location :nearest
                                    )
                                    :none
                                )
                            )
                            (attended 
                                (if (slot-in-chunk-spec-p chunk-spec :attended) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :attended)
                                            :vision 'visual-location :attended
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                        )
                    
                        (if (or (null nearest) (null attended))
                            (print-warning "Invalid value in a request to the visual-location buffer")
                
                            (schedule-event-relative 0 'find-location
                                :module :vision 
                                :destination :vision 
                                :details "Find-location" 
                                :output 'medium
                                :params (list chunk-spec)
                            )
                        )
                    )
                )
                ((chunk-type-subtype-p-fct (chunk-spec-chunk-type chunk-spec) 'set-visloc-default)
                    (let 
                        (
                            (nearest
                                (if (slot-in-chunk-spec-p chunk-spec :nearest)
                                    (verify-single-explicit-value
                                        (chunk-spec-slot-spec chunk-spec :nearest)
                                        :vision 'set-visloc-default :nearest
                                    )
                                    :none
                                )
                            )
                            (attended 
                                (if (slot-in-chunk-spec-p chunk-spec :attended) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :attended)
                                            :vision 'set-visloc-default :attended
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                            (type 
                                (if (slot-in-chunk-spec-p chunk-spec 'type) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec 'type)
                                            :vision 'set-visloc-default 'type
                                        )
                                        (declare (ignore valid))
                                        val
                                    )
                                    :none
                                )
                            )
                        ) ; [SC] end of the variable initialization part
              
                        (if (or (null nearest) (null attended))
                            (print-warning "Invalid value in a request to the visual-location buffer")
                            (if (and type (not (eq type :none)) (not (chunk-type-p-fct type)))
                                (print-warning "Invalid type specified in set-visloc-default request.")
                                (schedule-event-relative 0 'set-visloc-default-request
                                    :module :vision 
                                    :destination :vision 
                                    :details "Set-visloc-default" 
                                    :output 'medium
                                    :priority 9 ; just below the buffer clearing by the production
                                    :params (list chunk-spec)
                                )
                            )
                        )
                    )
                )
                (t 
                    (print-warning "Invalid command ~a sent to the visual-location buffer" (chunk-spec-chunk-type chunk-spec))
                )
            )
        ) 
        
        ;;;; [SC] [START] PAAV only code
        (abstract-location
            (cond 
                ((chunk-type-subtype-p-fct (chunk-spec-chunk-type chunk-spec) 'abstract-location)
                    
                    ;;;; [SC] at first removing all decayed abstract locations from visual memory
                    ;;;; [TODO] this call might need to move to some other place
                    (delete-decayed-features-from-iconic-memory paav-mod)
                    
                    (let 
                        (
                            (nearest
                                (if (slot-in-chunk-spec-p chunk-spec :nearest) ; [SC] checking whether the chunk specification passed to visual module includes slot called :nearest
                                    ;;;; [SC] this function makes sure that :nearest has only one specification and that specification uses = modifier
                                    ;;;;        the last three parameters for this function are for printing purpose only
                                    (verify-single-explicit-value
                                        (chunk-spec-slot-spec chunk-spec :nearest) 
                                        :vision 'abstract-location :nearest
                                    )
                                    :none
                                )
                            )
                            (attended 
                                (if (slot-in-chunk-spec-p chunk-spec :attended) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :attended) 
                                            :vision 'abstract-location :attended
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                            (attended-fcolor 
                                (if (slot-in-chunk-spec-p chunk-spec :attended-fcolor) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :attended-fcolor)
                                            :vision 'abstract-location :attended-fcolor
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                            (attended-fshape
                                (if (slot-in-chunk-spec-p chunk-spec :attended-fshape) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :attended-fshape) 
                                            :vision 'abstract-location :attended-fshape
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                            (attended-fshading
                                (if (slot-in-chunk-spec-p chunk-spec :attended-fshading) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :attended-fshading) 
                                            :vision 'abstract-location :attended-fshading
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                            (attended-forient
                                (if (slot-in-chunk-spec-p chunk-spec :attended-forient) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :attended-forient) 
                                            :vision 'abstract-location :attended-forient
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                            (attended-fsize
                                (if (slot-in-chunk-spec-p chunk-spec :attended-fsize) 
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :attended-fsize) 
                                            :vision 'abstract-location :attended-fsize
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                            (region
                                (if (slot-in-chunk-spec-p chunk-spec :region)
                                    (let ((slot-specs (chunk-spec-slot-spec chunk-spec :region)))
                                        (multiple-value-bind (val valid)
                                            (if
                                                (and
                                                    (param-has-value slot-specs :vision 'abstract-location :region)
                                                    (params-have-valid-modif slot-specs :vision 'abstract-location '(= -))
                                                    (params-are-explicit slot-specs :vision 'abstract-location)
                                                )

                                                (values (third (car slot-specs)) t)
                                                nil
                                            )
                                            (declare (ignore val))
                                            valid
                                        )
                                    )
                                    :none
                                )
                            )

                            ;;;; [TODO] [URGENT]
                            (region-category
                                (if (slot-in-chunk-spec-p chunk-spec :region-category)
                                    (let ((slot-specs (chunk-spec-slot-spec chunk-spec :region-category)))
                                        (multiple-value-bind (val valid)
                                            (if
                                                (and
                                                    (param-has-value slot-specs :vision 'abstract-location :region-category)
                                                    (params-have-valid-modif slot-specs :vision 'abstract-location '(= -))
                                                    (params-are-explicit slot-specs :vision 'abstract-location)
                                                )
                                                (values (third (car slot-specs)) t)
                                                nil
                                            )
                                            (declare (ignore val))
                                            valid
                                        )
                                    )
                                    :none
                                )
                            )

                            (relevancy
                                (if (slot-in-chunk-spec-p chunk-spec :relevancy)
                                    (let ((slot-specs (chunk-spec-slot-spec chunk-spec :relevancy)))
                                        (multiple-value-bind (val valid)
                                            (if
                                                (and
                                                    (param-has-single-spec slot-specs :vision 'abstract-location :relevancy)
                                                    (param-has-value slot-specs :vision 'abstract-location :relevancy)
                                                    (params-have-valid-modif slot-specs :vision 'abstract-location '(< <= >= >))
                                                    (params-are-explicit slot-specs :vision 'abstract-location)
                                                    (params-have-valid-values slot-specs :vision 'abstract-location 
                                                        '(fcolor fshape fsize forient fshading current)
                                                    )
                                                )
                                                (values (third (car slot-specs)) t)
                                                nil
                                            )
                                            (declare (ignore val))
                                            valid
                                        )
                                    )
                                    :none
                                )
                            )
                        )
                    
                        (if 
                            (or
                                (null nearest) 
                                (null attended) (null attended-fcolor) (null attended-fshape) 
                                (null attended-fshading) (null attended-forient) (null attended-fsize)
                                (null region) (null region-category) (null relevancy)
                            )
                            (print-warning "Invalid value in a request to the abstract-location buffer")
                            
                            ;;;; [SC] scheduling the call for find-location-location method
                            (schedule-event-relative 0 'find-abstract-location
                                :module :vision 
                                :destination :vision 
                                :details "Find-abstract-location" 
                                :output 'medium
                                :params (list chunk-spec)
                            )
                        )
                    )
                )
                (t 
                    (print-warning "Invalid command ~a sent to the visual-location buffer" (chunk-spec-chunk-type chunk-spec))
                )
            )
        )

        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;;;;; START: [HRM] related code
    
        (visual-memory
            (cond
                ;;;; [SC][2013.12.20][ENABLE-VSTM] do not process the request if VSTM is not enabled
                ((not (enable-vstm paav-mod))
                    (print-warning "Cannot process a request to the visual-memory buffer. VSTM is not enables.")
                )
                
                ;;;; [SC] buffer was requested to create a new abstract visual object chunk and add it into VSTM
                ((chunk-type-subtype-p-fct (chunk-spec-chunk-type chunk-spec) 'add-abstract-object)
                    (let 
                        (
                            ;;;; [TODO] make sure there is an appropriate validity check for opertators (only =) and values (either t or nil)
                            (chunk-name
                                (if (slot-in-chunk-spec-p chunk-spec :chunk-name)
                                    (verify-single-explicit-value
                                        (chunk-spec-slot-spec chunk-spec :chunk-name)
                                        :vision 'visual-memory :chunk-name
                                    )
                                    :none
                                )
                            )
                        )

                        (if (null chunk-name)
                            (print-warning "Invalid CHUNK-NAME value in a request to the visual-memory buffer")
                            (schedule-event-relative 0 'add-abstract-object-callback
                                :params (list chunk-spec)
                                :module :vision
                                :destination :vision
                                :details "CREATING AN ABSTRACT VISUAL-OBJECT CHUNK INSIDE VSTM"
                                :output 'medium
                            )
                        )
                    )
                )

                ;;;; [SC] buffer was requested to add to VSTM a chunk already existing in one of the buffers
                ((chunk-type-subtype-p-fct (chunk-spec-chunk-type chunk-spec) 'refer-abstract-object)

                )

                ;;;; [SC] buffer received a request to retrieve a chunk from VSTM
                ((chunk-type-subtype-p-fct (chunk-spec-chunk-type chunk-spec) 'feature-object)
                    ;;;; [SC] the decayed visual objects will be called during individual function calls
                    (let 
                        (
                            ;;;; [TODO] make sure there is an appropriate validity check for opertators (only =) and values (either t or nil)
                            (recently-retrieved
                                (if (slot-in-chunk-spec-p chunk-spec :recently-retrieved)
                                    (multiple-value-bind (val valid)
                                        (verify-single-explicit-value 
                                            (chunk-spec-slot-spec chunk-spec :recently-retrieved)
                                            :vision 'visual-memory :recently-retrieved
                                        )
                                        (declare (ignore val))
                                        valid
                                    )
                                    :none
                                )
                            )
                        )

                        (if (null recently-retrieved)
                            (print-warning "Invalid RECENTLY-RETRIEVED value in a request to the visual-memory buffer")
                            (schedule-event-relative 0 'vstm-retrieval-callback
                                :params (list chunk-spec)
                                :module :vision
                                :destination :vision
                                :details "RETRIEVING A CHUNK FROM VSTM"
                                :output 'medium
                            )
                        )
                    )
                )
            )
        )

        ;;;;;; END: [HRM] related code
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        ;;;; [SC] [END] PAAV only code
    )
)

;;;;;; START: FUNCTIONS OVERRIDDEN FROM DEFAULT VISION MODULE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: top level methods and functions

;;;; [SC] sets the current gaze location at center of the device (window)
;;;; [TESTED]
(defun set-gaze-loc-center ()
    (let
        (
            (paav-mod (get-module :vision))
            (window-width (width (current-device)))
            (window-height (height (current-device)))
        )

        (set-gaze-loc paav-mod (list (/ window-width 2) (/ window-height 2)))
    )
)

;;;; [SC] sets the current gaze location at given x and y position
;;;; [TESTED]
(defun set-gaze-loc-custom (x-loc y-loc)
    (set-gaze-loc (get-module :vision) (list x-loc y-loc))
)

;;;; [TODO] [TEMP]
(defun ready-the-eye ()
    (let ((paav-mod (get-module :vision)))
        (delete-decayed-features-from-iconic-memory paav-mod)
        (get-visible-visicon-chunks paav-mod)
        (register-fx-start paav-mod)
    )
)

;;;; [SC] resets all abstract-locations with attended state T to NIL
;;;; [SC] one should be careful with reseting to NEW because it is not obvious how to reset times in that case
(defun remove-abstract-finsts ()
    (let ((paav-mod (get-module :vision)))
        (if paav-mod
            (progn
                (maphash
                    #'(lambda (feature-key feature-reg)
                        (declare (ignore feature-key))
                        ;;;; [SC] if the attended state is T then set NIL, otherwise ignore
                        (if (eq *attended-t* (get-vm-reg-value-item 'rv-attend-state feature-reg))
                            (set-vm-reg-value-item *attended-nil* 'rv-attend-state feature-reg)
                        )
                    )
                    (vm-feature-reg paav-mod)
                )

                (maphash
                    #'(lambda (abstr-loc-key abstr-loc-reg)
                        (declare (ignore abstr-loc-key))
                        ;;;;; [SC] if the attended state is T then set NIL, otherwise ignore
                        (if (eq *attended-t* (get-vm-loc-reg-value 'rv-attend-state abstr-loc-reg))
                            (set-vm-loc-reg-value *attended-nil* 'rv-attend-state abstr-loc-reg)
                        )
                    )
                    (vm-loc-reg paav-mod)
                )
            )
            (print-warning "Cannot find visual module in remove-abstract-finsts function call.")
        )
    )
)

;;;;;; END: top level methods and functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: MODULE INIT CODE

;;;; [SC] creates an instance of paav-vis-mod class
(defun create-paav-module (model-name)
    (declare (ignore model-name))
    (make-instance 'paav-vis-mod)
)

;;;;; [TODO] need to make sure that those methods exist in visual module
(defmethod reset-paav-module ((paav-mod paav-vis-mod))
    (reset-pm-module paav-mod)
  
    ;; This stuff was moved from an after method on reset-pm-module...
  
    (clrhash (visicon paav-mod))
    ;(clrhash (feat-table vis-mod))
  
    (setf (current-cursor paav-mod) nil)
  
    (remove-tracking paav-mod)
    (setf (last-scale paav-mod) nil)
    (set-cfs-mth paav-mod :RM-ORIG)
    (setf (synthd-objs paav-mod) (clrhash (synthd-objs paav-mod)))
    (setf (finst-lst paav-mod) nil)
  
    (setf (scene-change paav-mod) nil)
  
    (setf (last-obj paav-mod) nil)
  
    ;;(setf (attn-trace paav-mod) nil)
  
    ;; Not needed at this point (set-clof paav-mod #(0 0))
    
    (setf (loc-failure paav-mod) nil)
    (setf (attend-failure paav-mod) nil)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;;;;; START: PAAV only codes or codes modified from default implementation

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;;;;; START: [HRM] related code

    (setf (vstm-persist-time paav-mod) 10000)
    (setf (vstm-capacity paav-mod) 4)
    (setf (vstm-failure paav-mod) nil)
    (clrhash (vstm-memory paav-mod))

    ;;;;;; END: [HRM] related code
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (setf (gaze-loc paav-mod) #(0 0))
    
    ;;;; [SC] PAAV only
    (setf (last-attended-relevancy paav-mod) nil)
    (setf (last-located-relevancy paav-mod) nil)
    
    ;;;; [SC] PAAV only
    (setf (abstr-loc-failure paav-mod) nil)
    
    ;;;; [SC] PAAV only
    (setf (eye-tracking paav-mod) nil)
    (setf (eye-track-protocols paav-mod) nil)
    (setf (gaze-noise-weight paav-mod) 0.5)
    ;(clrhash (eye-track-protocols paav-mod))
    (setf (sacc-counter paav-mod) 0)
    (setf (fx-counter paav-mod) 0)
    
    ;;;; [SC] PAAV only
    (clrhash (iconic-memory paav-mod))
    (clrhash (vm-feature-reg paav-mod))
    (clrhash (vm-loc-reg paav-mod))
    (clrhash (abstr-loc-id  paav-mod))
    
    ;;;; [SC] PAAV only
    (clrhash (fval-dissim-ht paav-mod))
    (clrhash (bottom-up-activ-ht paav-mod))
    (clrhash (top-down-activ-ht paav-mod))

    ;;;; [SC] [PAAV]
    (clrhash (vis-region-ht paav-mod))
    
    ;;;; [SC] [PAAV] defining type for chunks that represent slot names
    (chunk-type slot-name-tp)
    (define-chunks
        (fcolor isa slot-name-tp)
        (fshape isa slot-name-tp)
        (fshading isa slot-name-tp)
        (fsize isa slot-name-tp)
        (forient isa slot-name-tp)
    )

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;;;;; START: [HRM] related code
    
    ;;;; [SC] creating R-CONCEPT chunk
    (if (not (chunk-type-p r-concept))
        (chunk-type r-concept) ; [SC] base chunk-type on which reasoner is allowed to reason
    )
    
    ;;;; [SC] creating R-INSTANCE chunk
    (if (chunk-type-p r-instance)
        (progn
            (if (not (chunk-type-subtype-p r-instance r-concept))
                (print-warning "Chunk-type R-INSTANCE is not subtype of R-CONCEPT.")
            )

            (if (not (member 'instance-id (chunk-type-slot-names r-instance)))
                (print-warning "Chunk-type R-INSTANCE does not have slot named INSTANCE-ID.")
            )
        )
        (chunk-type (r-instance (:include r-concept)) instance-id)
    )

    ;;;;;; END: [HRM] related code
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ;;;; [SC] PAAV only chunk types
    ;;;; [TODO] seems to be that saliency slot will not be used
    
    ;;;; [SC] the feature-name slot is necessary for ACT-R to differentiate between different feature values during merging (reference count)
    (chunk-type (visual-feature (:include r-instance)) saliency slot-name feature-name) ; [SC][HRM]
    (chunk-type (color-feature (:include visual-feature)) (slot-name fcolor))
    (chunk-type (shape-feature (:include visual-feature)) (slot-name fshape))
    (chunk-type (shading-feature (:include visual-feature)) (slot-name fshading))
    (chunk-type (orientation-feature (:include visual-feature)) (slot-name forient))
    (chunk-type (size-feature (:include visual-feature)) (slot-name fsize))
    
    ;;;; [SC] creating default feature values
    (define-chunks 
        ;;;; [SC] color feature values 
        (vf-black isa color-feature feature-name "vf-black")
        (vf-red isa color-feature feature-name "vf-red")
        (vf-green isa color-feature feature-name "vf-green")
        (vf-blue isa color-feature feature-name "vf-blue")
        (vf-gray isa color-feature feature-name "vf-gray")
        (vf-yellow isa color-feature feature-name "vf-yellow")
        (vf-purple isa color-feature feature-name "vf-purple")
        (vf-orange isa color-feature feature-name "vf-orange")
        
        ;;;; [SC] shape feature values
        (vf-rectangle isa shape-feature feature-name "vf-rectangle")
        (vf-oval isa shape-feature feature-name "vf-oval")
        (vf-squiggle isa shape-feature feature-name "vf-squiggle")
        (vf-square isa shape-feature feature-name "vf-square")
        (vf-triangle isa shape-feature feature-name "vf-triangle")
        (vf-diamond isa shape-feature feature-name "vf-diamond")
        (vf-star isa shape-feature feature-name "vf-star")
        (vf-clower isa shape-feature feature-name "vf-clower")
        (vf-x isa shape-feature feature-name "vf-x")
        
        ;;;; [SC] shading feature values
        (vf-solid isa shading-feature feature-name "vf-solid")
        (vf-open isa shading-feature feature-name "vf-open")
        (vf-stripped isa shading-feature feature-name "vf-stripped")
        (vf-textured isa shading-feature feature-name "vf-textured")

        ;;;; [SC] orientation feature values
        (vf-north isa orientation-feature feature-name "vf-north")
        (vf-south isa orientation-feature feature-name "vf-south")
        (vf-east isa orientation-feature feature-name "vf-east")
        (vf-west isa orientation-feature feature-name "vf-west")

        (vf-small isa size-feature feature-name "vf-small")
        (vf-medium isa size-feature feature-name "vf-medium")
        (vf-large isa size-feature feature-name "vf-large")
        (vf-extra-large isa size-feature feature-name "vf-extra-large")
    )
    
    ;;;; [SC] PAV only chunk types
    (chunk-type (feature-location (:include r-instance)) fcolor fshape fshading forient fsize screen-x screen-y distance kind color value height width size) ; [SC][HRM]
    (chunk-type (feature-object (:include r-instance)) fcolor fshape fshading forient fsize) ; [SC][HRM]

    ;;;; [SC] Redefining visual location chunk types as the subtypes of PAV chunks
    ;;;; [TODO] need to modify setting for default slot values
    (chunk-type (visual-location (:include feature-location)) (fcolor vf-black) (fshape vf-rectangle) (fshading vf-solid) (forient vf-north) (fsize vf-small))
    (chunk-type (set-visloc-default (:include feature-location)) type)
    
    ;;;; [SC] PAAV only chunk types
    ;;;; [SC] its purpose is similar to visual-location but is used instead in visual memory 
    (chunk-type (abstract-location (:include feature-location)))
    
    ;;;; [SC] Redefining visual object chunk types as the subtypes of PAAV chunks
    (chunk-type (visual-object (:include feature-object)) screen-pos value status color height width region region-cat)

    ;;;; [SC][HRM][2013.03.07]
    ;;;; [SC] reference-chunk slot contains the name of the real chunk if abstract chunk is its copy/reference
    ;;;; [SC] if abstract chunk is standalone then value of reference-chunk slot is nil
    (chunk-type (abstract-visual-object (:include feature-object)) reference-chunk screen-x screen-y value status color height width region region-cat)

    ;;;; [SC][HRM][2013.03.05] a command to visual-memory buffer to create a new abstract visual object and add it to VSTM
    ;;;; [SC] reference slot has as a value of a placeholder for a buffer containing the real chunk or the real chunk name
    (chunk-type (add-abstract-object (:include feature-object)) reference screen-x screen-y value status color height width region region-cat)
    
    ;;;; [SC][HRM] a command to visual-memory buffer to add a chunk already existing inside a buffer to VSTM as an abstract object
    ;;;; [TODO][DELETE] currently not used anywhere
    (chunk-type refer-abstract-object reference #|[SC] this is either direct referency of chunk from which copy should be maid or a placeholder for a buffer from which the chunk should be taken|#)
    
    ;;;; [TODO] this abstract-object is never being used
    (chunk-type (abstract-object (:include feature-object)) value line-pos bin-pos)

    ;;;;;; END: PAAV only codes or codes modified from default implementation
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
    
    (chunk-type (abstract-letter (:include abstract-object)))
    (chunk-type (abstract-number (:include abstract-object)))
    (chunk-type (text (:include visual-object)))
    (chunk-type (empty-space (:include visual-object)))
  
    (chunk-type (line (:include visual-object)) end1-x end1-y end2-x end2-y)
    (chunk-type (oval (:include visual-object)))
    (chunk-type (cursor (:include visual-object)))
  
    (chunk-type (phrase! (:include visual-object)) objects words colors)
  
    (chunk-type (char-primitive (:include visual-location)) left right)
  
    (chunk-type vision-command)
  
    (unless (chunk-type-p pm-constant) (chunk-type pm-constant))
    
    ;;;; [TODO] redefine the color chunk type
    (chunk-type color)
  
    (chunk-type (move-attention (:include vision-command)) screen-pos scale)
  
    (chunk-type (start-tracking (:include vision-command)))
  
    (chunk-type (assign-finst (:include vision-command)) object location)
  
    (chunk-type (clear-scene-change (:include vision-command)))

    (unless (chunk-type-p clear) (chunk-type clear))
  
    (define-chunks 
        (lowest isa pm-constant)
        (highest isa pm-constant)
        (current isa pm-constant)
        (external isa pm-constant)
        (internal isa pm-constant)
        (find-location isa vision-command)
        (move-attention isa vision-command)
        (assign-finst isa vision-command)
        (start-tracking isa vision-command)
        
        ;;;; [TODO] redefine color chunks
        (black isa color)
        (red isa color)
        (blue isa color)
        (green isa color)
        (white isa color)
        (magenta isa color)
        (yellow isa color)
        (cyan isa color)
        (dark-green isa color)
        (dark-red isa color)
        (dark-cyan isa color)
        (dark-blue isa color)
        (dark-magenta isa color)
        (dark-yellow isa color)
        (light-gray isa color)
        (dark-gray isa color)
        
        (text isa chunk)
        (box isa chunk)
        (line isa chunk)
        (oval isa chunk)
    
        (new isa chunk)
        (clear isa chunk)
    )

    (setf
        (default-spec paav-mod)
        (define-chunk-spec isa visual-location screen-x lowest :attended new)
    )
)

;;;; [SC] probably this function is called when one of the module parameters is either set or read
;;;; [SC] this function is NOT called to set frequency values for individual chunks
;;;; [SC] the function accepts two parameters instance of class of vis-mod and list named param
;;;; [SC] param is probably cons cell with parameter name and parameter value
;;;; [TODO] emma version of params function
(defun params-paav-module (vis-mod param)    
    
    ;;;; [TODO] PAAV version of function body
    (aif (params-vision-module vis-mod param)
        it
        (if (consp param)    ;[SC] consp returns true if param refers to cons cell
            
            ;;;; [SC] this case (switch) is setter
            (case (car param)        ;[SC] case is similar to C switch statement; car returns the content of the first pointer in cons cell
                (:persistence-time ;[SC] switch case check: checks if the content of the first pointer is :persistence-time
                    (setf (persistence-time vis-mod) (cdr param))) ;[SC] body of the case statement; sets the def-persistence-time parameter of visual class with a content of the second pointer of param

                (:abstract-finst-span
                    (setf (finst-span-abstr vis-mod) (cdr param)))
                (:abstract-num-finsts
                    (setf (num-finst-abstr vis-mod) (cdr param)))

                (:iconic-memory-mas
                    (setf (iconic-memory-mas vis-mod) (cdr param)))
                (:iconic-memory-w
                    (setf (iconic-memory-w vis-mod) (cdr param)))
                (:vm-fcolor-w
                    (setf (vm-fcolor-w vis-mod) (cdr param)))
                (:vm-fshape-w
                    (setf (vm-fshape-w vis-mod) (cdr param)))
                (:vm-fshading-w
                    (setf (vm-fshading-w vis-mod) (cdr param)))
                (:vm-fsize-w
                    (setf (vm-fsize-w vis-mod) (cdr param)))
                (:vm-forient-w
                    (setf (vm-forient-w vis-mod) (cdr param)))
                (:vm-ftext-w
                    (setf (vm-ftext-w vis-mod) (cdr param)))

                (:text-acuity-dist
                    (setf (text-acuity-dist vis-mod) (cdr param)))
                
                (:fcolor-acuity-a 
                    (setf (fcolor-acuity-a vis-mod) (cdr param)))
                (:fshape-acuity-a 
                    (setf (fshape-acuity-a vis-mod) (cdr param)))
                (:fshading-acuity-a 
                    (setf (fshading-acuity-a vis-mod) (cdr param)))
                (:fsize-acuity-a 
                    (setf (fsize-acuity-a vis-mod) (cdr param)))
                (:forient-acuity-a 
                    (setf (forient-acuity-a vis-mod) (cdr param)))

                (:fcolor-acuity-b 
                    (setf (fcolor-acuity-b vis-mod) (cdr param)))
                (:fshape-acuity-b 
                    (setf (fshape-acuity-b vis-mod) (cdr param)))
                (:fshading-acuity-b
                    (setf (fshading-acuity-b vis-mod) (cdr param)))
                (:fsize-acuity-b
                    (setf (fsize-acuity-b vis-mod) (cdr param)))
                (:forient-acuity-b 
                    (setf (forient-acuity-b vis-mod) (cdr param)))

                (:fcolor-sim-w 
                    (setf (fcolor-sim-w vis-mod) (cdr param)))
                (:fshape-sim-w 
                    (setf (fshape-sim-w vis-mod) (cdr param)))
                (:fshading-sim-w 
                    (setf (fshading-sim-w vis-mod) (cdr param)))
                (:fsize-sim-w 
                    (setf (fsize-sim-w vis-mod) (cdr param)))
                (:forient-sim-w 
                    (setf (forient-sim-w vis-mod) (cdr param)))

                (:top-down-act-w
                    (setf (top-down-act-w vis-mod) (cdr param)))
                (:bottom-up-act-w
                    (setf (bottom-up-act-w vis-mod) (cdr param)))
                (:vis-act-s
                    (setf (vis-act-s vis-mod) (cdr param)))

                (:move-attn-latency-new
                    (setf (move-attn-latency-new vis-mod) (cdr param)))

                (:eye-tracking
                    (setf (eye-tracking vis-mod) (cdr param)))
                
                (:gaze-noise-weight
                    (setf (gaze-noise-weight vis-mod) (cdr param)))


                ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                ;;;;;; START: [HRM]
                
                (:vstm-persist-time
                    (setf (vstm-persist-time vis-mod) (cdr param)))

                (:vstm-capacity
                    (setf (vstm-capacity vis-mod) (cdr param)))

                (:vstm-trace
                    (setf (vstm-trace vis-mod) (cdr param)))

                ;;;; [SC][2013.12.20][ENABLE-VSTM]
                (:enable-vstm
                    (setf (enable-vstm vis-mod) (cdr param)))

                ;;;;;; END: [HRM]
                ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
            )
            
            ;;;; [SC] this case (switch) is probably getter
            (case param
                (:persistence-time
                    (persistence-time vis-mod))

                (:abstract-finst-span
                    (finst-span-abstr vis-mod))
                (:abstract-num-finsts
                    (num-finst-abstr vis-mod))

                (:iconic-memory-mas
                    (iconic-memory-mas vis-mod))
                (:iconic-memory-w
                    (iconic-memory-w vis-mod))
                (:vm-fcolor-w
                    (vm-fcolor-w vis-mod))
                (:vm-fshape-w
                    (vm-fshape-w vis-mod))
                (:vm-fshading-w
                    (vm-fshading-w vis-mod))
                (:vm-fsize-w
                    (vm-fsize-w vis-mod))
                (:vm-forient-w
                    (vm-forient-w vis-mod))
                (:vm-ftext-w
                    (vm-ftext-w vis-mod))

                (:text-acuity-dist
                    (text-acuity-dist vis-mod))

                (:fcolor-acuity-a
                    (fcolor-acuity-a vis-mod))
                (:fshape-acuity-a
                    (fshape-acuity-a vis-mod))
                (:fshading-acuity-a
                    (fshading-acuity-a vis-mod))
                (:fsize-acuity-a
                    (fsize-acuity-a vis-mod))
                (:forient-acuity-a
                    (forient-acuity-a vis-mod))
                
                (:fcolor-acuity-b
                    (fcolor-acuity-b vis-mod))
                (:fshape-acuity-b
                    (fshape-acuity-b vis-mod))
                (:fshading-acuity-b
                    (fshading-acuity-b vis-mod))
                (:fsize-acuity-b
                    (fsize-acuity-b vis-mod))
                (:forient-acuity-b
                    (forient-acuity-b vis-mod))

                (:fcolor-sim-w
                    (fcolor-sim-w vis-mod))
                (:fshape-sim-w
                    (fshape-sim-w vis-mod))
                (:fshading-sim-w
                    (fshading-sim-w vis-mod))
                (:fsize-sim-w
                    (fsize-sim-w vis-mod))
                (:forient-sim-w
                    (forient-sim-w vis-mod))

                (:top-down-act-w
                    (top-down-act-w vis-mod))
                (:bottom-up-act-w
                    (bottom-up-act-w vis-mod))
                (:vis-act-s
                    (vis-act-s vis-mod))

                (:move-attn-latency-new
                    (move-attn-latency-new vis-mod))

                (:eye-tracking
                    (eye-tracking vis-mod))
                
                (:gaze-noise-weight
                    (gaze-noise-weight vis-mod))


                ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                ;;;;;; START: [HRM]
                
                (:vstm-persist-time
                    (vstm-persist-time vis-mod))

                (:vstm-capacity
                    (vstm-capacity vis-mod))

                (:vstm-trace
                    (vstm-trace vis-mod))

                ;;;; [SC][2013.12.20][ENABLE-VSTM]
                (:enable-vstm
                    (enable-vstm vis-mod))

                ;;;;;; END: [HRM]
                ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
            )
        )
    )
)

;;; define the module itself  -- name :vision

(undefine-module :vision)


(define-module-fct :vision 
    (list
        ;;;; [SC][HRM][TODO][CORE] creating a buffer called visual-memory
        (list 'visual-memory
            nil
            '(:recently-retrieved :chunk-name)
            '()
            #'(lambda ()
                (print-module-status (get-module :vision)) ; [TODO]
            )
        )

        (list 'visual-location nil '(:attended :nearest) '(attended)
            #'(lambda ()
                (command-output "  attended new          : ~S"
                    (query-buffer 'visual-location '((attended . new)))
                )
                (command-output "  attended nil          : ~S"
                    (query-buffer 'visual-location '((attended . nil)))
                )
                (command-output "  attended t            : ~S"
                    (query-buffer 'visual-location '((attended . t)))
                )
            )
        )
        
        ;;;; [SC] PAAV modified visual buffer
        (list 'visual nil '(:relevancy) '(scene-change-value scene-change modality preparation execution processor last-command)
            #'(lambda ()
                (let ((v (get-module :vision)))
                    (print-module-status v)
                    (command-output "  scene-change          : ~S"
                        (query-buffer 'visual '((scene-change . t)))
                    )
                    (command-output "  scene-change-value    : ~S"
                        (car (scene-change v))
                    )
                )
            )
        )
    
        ;;;; [SC] PAAV only code for abstract-location buffer
        ;;;; [SC] creating abstract-lcoation buffer
        (list 'abstract-location nil  ;;;; [SC] a list of parameters that can be supplied to request
            '(
                :nearest
                ;;;; [SC] set of parameters for controlling attended state
                :attended :attended-fcolor :attended-fshape
                :attended-fshading :attended-forient :attended-fsize
                :relevancy :region :region-category
            )

            ;;;; [SC] list of buffer state query parameters
            '(attended)

            #'(lambda ()
                (command-output "  attended new          : ~S"
                    (query-buffer 'abstract-location '((attended . new)))
                )
                (command-output "  attended nil          : ~S"
                    (query-buffer 'abstract-location '((attended . nil)))
                )
                (command-output "  attended t            : ~S"
                    (query-buffer 'abstract-location '((attended . t)))
                )
            )
        )
    )

    (list
        ;;;; [SC] this set of parameters are from default module and also were included in emma
        (define-parameter :optimize-visual    ;[SC] emma & default visual 
            :valid-test #'tornil 
            :default-value T
            :warning "T or NIL"
            :documentation "")
        (define-parameter :visual-attention-latency    ;[SC] emma & default visual 
            :valid-test #'nonneg 
            :default-value 0.085
            :warning "a non-negative number"
            :documentation "Time for a shift of visual attention")
        (define-parameter :visual-finst-span    ;[SC] emma & default visual 
            :valid-test #'nonneg 
            :default-value 3.0
            :warning "a non-negative number"
            :documentation "Lifespan of a visual finst")
        (define-parameter :visual-movement-tolerance    ;[SC] emma & default visual
            :valid-test #'nonneg 
            :default-value 0.5
            :warning "a non-negative number"
            :documentation "How far something can move while still being seen as the same object.")
        (define-parameter :visual-num-finsts    ;[SC] emma & default visual
            :valid-test #'posnum 
            :default-value 4
            :warning "a positive number"
            :documentation "Number of visual finsts.")
        (define-parameter :visual-onset-span    ;[SC] emma & default visual 
            :valid-test #'nonneg 
            :default-value 0.5
            :warning "a non-negative number"
            :documentation "Lifespan of new visual objects being marked as NEW")
        (define-parameter :test-feats    ;[SC] emma & default visual 
            :valid-test #'tornil 
            :default-value T
            :warning "T or NIL"
            :documentation "Whether proc-display should use the features to compare items instead of just the chunk names")

        ;;;; [SC] this set of parameters are from default module but were not included in emma
        (define-parameter :scene-change-threshold    ;[SC] default visual 
            :valid-test (lambda (x) (and (numberp x) (<= 0.0 x 1.0)))
            :default-value 0.25
            :warning "a number in the range [0.0,1.0]"
            :documentation "Proportion of visicon which must change to signal a scene change")
        (define-parameter :auto-attend        ;[SC] default visual 
            :valid-test #'tornil 
            :default-value nil
            :warning "T or NIL"
            :documentation "Whether visual-location requests automatically generate an attention shift")
        (define-parameter :delete-visicon-chunks    ;[SC] default visual 
            :valid-test #'tornil 
            :default-value T
            :warning "T or NIL"
            :documentation "Whether proc-display should delete and unintern the name of old chunks that were in the visicon")
        (define-parameter :viewing-distance        ;[SC] default visual
            :owner nil)

        ;;;; [SC] parameters for PAAV only
        ;;;; [TODO] defining feature acuity parameters

        (define-parameter :text-acuity-dist
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 1.0
            :documentation "Acuity for a text")

        (define-parameter :fcolor-acuity-a
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.104
            :documentation "Acuity for color feature")
        (define-parameter :fcolor-acuity-b
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.85
            :documentation "Acuity for color feature")

        (define-parameter :fshape-acuity-a
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.142
            :documentation "Acuity for shape feature")
        (define-parameter :fshape-acuity-b
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.96
            :documentation "Acuity for shape feature")

        (define-parameter :fshading-acuity-a
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.147
            :documentation "Acuity for shading feature")
        (define-parameter :fshading-acuity-b
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.96
            :documentation "Acuity for shading feature")

        (define-parameter :fsize-acuity-a
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.14
            :documentation "Acuity for size feature")
        (define-parameter :fsize-acuity-b
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.96
            :documentation "Acuity for size feature")

        (define-parameter :forient-acuity-a
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.1
            :documentation "Acuity for orientation feature")
        (define-parameter :forient-acuity-b
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 0.601
            :documentation "Acuity for orientation feature")

        ;;;; [SC] parameters for PAAV only
        ;;;; [SC] parameters for feature similarity weight
        (define-parameter :fcolor-sim-w
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 1
            :documentation "Weight of similarity between two same color feature values.")
        (define-parameter :fshape-sim-w
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 1
            :documentation "Weight of similarity between two same shape feature values.")
        (define-parameter :fshading-sim-w
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 1
            :documentation "Weight of similarity between two same shading feature values.")
        (define-parameter :fsize-sim-w
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 1
            :documentation "Weight of similarity between two same size feature values.")
        (define-parameter :forient-sim-w
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 1
            :documentation "Weight of similarity between two same orientation feature values.")

        ;;;; [SC] [PAAV] top-down and bottom-up activation weight and noise parameters
        (define-parameter :top-down-act-w
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 0.45
            :documentation "Weight of a top-down activation map.")
        (define-parameter :bottom-up-act-w
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 1.1
            :documentation "Weight of a bottom-up activation map.")
        (define-parameter :vis-act-s
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 0.0
            :documentation "An instanteneous noise to be added to the total activation of the abstract location.")

        ;;;; [SC] parameters for PAAV only
        (define-parameter :persistence-time
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 4000
            :documentation "The duration in milliseconds after which the item should erased from visual memory if it is not visible anymore")

        ;;;; [SC] PAAV only parameters - for visual memory buffers and query parameters
        (define-parameter :abstract-finst-span    ;[SC] span of finst for abstract location in visual memmory
            :valid-test #'nonneg
            :warning "a non-negative number" 
            :default-value 3000
            :documentation "Lifespan of a abstract finst in milliseconds.")
        (define-parameter :abstract-num-finsts    ;[SC] total number of finsts that can be used to mark abstract locations in visual memory
            :valid-test #'posnum
            :warning "a positive number" 
            :default-value 4
            :documentation "Number of abstract finsts.")
        
        ;;;; [SC] PAAV only parameters - spreading activation from visuam memory to declarative memory
        (define-parameter :iconic-memory-mas
            :valid-test #'nonneg
            :warning "a non-negative number"
            :default-value 0 
            :documentation "Minimum associative strength for chunks in visual memory")
        (define-parameter :iconic-memory-w 
            :valid-test #'nonneg
            :warning "a non-negative number"
            :default-value 1
            :documentation "Weight of activation spread from iconic memory")
        (define-parameter :vm-fcolor-w 
            :valid-test #'nonneg
            :warning "a non-negative number"
            :default-value 1
            :documentation "Weight of activation spread from color feature in iconic memory")
        (define-parameter :vm-fshape-w 
            :valid-test #'nonneg
            :warning "a non-negative number"
            :default-value 1
            :documentation "Weight of activation spread from shape feature in iconic memory")
        (define-parameter :vm-fshading-w 
            :valid-test #'nonneg
            :warning "a non-negative number"
            :default-value 1
            :documentation "Weight of activation spread from shading feature in iconic memory")
        (define-parameter :vm-fsize-w 
            :valid-test #'nonneg
            :warning "a non-negative number"
            :default-value 1
            :documentation "Weight of activation spread from size feature in iconic memory")
        (define-parameter :vm-forient-w 
            :valid-test #'nonneg
            :warning "a non-negative number"
            :default-value 1
            :documentation "Weight of activation spread from orientation feature in iconic memory")
        (define-parameter :vm-ftext-w 
            :valid-test #'nonneg
            :warning "a non-negative number"
            :default-value 1
            :documentation "Weight of activation spread from text feature in iconic memory")

        (define-parameter :move-attn-latency-new
            :valid-test #'nonneg 
            :default-value 0.05
            :warning "a non-negative number"
            :documentation "A PAAV modified time for a shift of visual attention")

        ;;;; [SC] PAAV only parameters
        (define-parameter :eye-tracking
            :valid-test #'tornil
            :default-value nil
            :warning "T or NIL"
            :documentation "Whether model's eye should be tracked and its recording be created.")

        (define-parameter :gaze-noise-weight
            :valid-test #'nonneg
            :default-value 0.5
            :warning "a non-negative number"
            :documentation "Set to 0 to disable gaussian noise added to gaze landing position around the center of visual object. Otherwise it is used as weight.")

        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;;;;; START: [HRM]
        
        ;;;; [SC] PAAV only parameters
        (define-parameter :vstm-persist-time
            :valid-test #'nonneg
            :warning "a non-negative-number"
            :default-value 10000
            :documentation "The duration in milliseconds after which the item should erased from visual short-term memory if it is not visible anymore.")

        ;;;; [SC] PAAV only parameters
        (define-parameter :vstm-capacity
            :valid-test #'posnum 
            :default-value 4
            :warning "a positive number"
            :documentation "A capacity of the visual short-term memory measured in a number of visual-objects it can hold.")
        
        ;;;; [SC] PAAV only parameters
        (define-parameter :vstm-trace
            :valid-test #'tornil
            :default-value nil
            :warning "T or NIL"
            :documentation "Whether VSTM activity info should be printed on the trace.")
        
        ;;;; [SC][2013.12.20][ENABLE-VSTM] PAAV only parameter
        (define-parameter :enable-vstm
            :valid-test #'tornil
            :default-value nil
            :warning "T or NIL"
            :documentation "A parameter for enabling/disablling VSTM functionality in PAAV.")
        ;;;;;; END: [HRM]
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    )
    
    :version "0.98e-paav"
    :documentation "Vision-module with PAAV"
    :creation #'create-paav-module 
    :reset #'reset-paav-module 
    :query #'query-vision-module    ;[SC] default module
    :request 'pm-module-request        ;[SC] default module
    :params #'params-paav-module
    :warning 'warn-vision
)                 

;;;;;; END: MODULE INIT CODE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Overriden methods from other modules

;;;; [SC] a modified function from /core-modules/declarative-memory.lisp
;;;; [SC] Original package's revision version and date: r1227, June4 2012
;;; Merge-chunk-into-dm
;;;
;;; This function will be called automatically each time a buffer is cleared.
;;;
;;; The parameters are an instance of the module, the name of the buffer that 
;;; was cleared, and the name of the chunk that was in the buffer.
;;;
;;; This module adds that chunk to declarative memory and increments its 
;;; reference count.  If a matching chunk already exists in declarative memory,
;;; then those chunks are merged together.  If this is the first occurrence of 
;;; the chunk, then its initial parameters are set accordingly.
(defun merge-chunk-into-dm (dm buffer chunk &optional (ignore-stuffing nil))

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;;;;; START: [HRM] related code; aborts DM merging for certain buffers

    (if 
        (or
            ;;;; [SC] chunk from this buffer does not go to DM since it was retrieved from VSTM
            (eq buffer 'visual-memory)
            ;;;; [SC] do not want to overload DM with useless assertion chunks; [HRM]
            (and (eq buffer 'reasoner) (chunk-type-subtype-p-fct (chunk-chunk-type-fct chunk) 'assertion))
        )
        (return-from merge-chunk-into-dm)
    )

    ;;;;;; END: [HRM]  related code; aborts DM merging for certain buffers
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


    (when (and (dm-stuff dm) (eq buffer 'retrieval) (not ignore-stuffing))
        (unless (dm-stuff-event dm)
            (setf
                (dm-stuff-event dm)
                (schedule-event-relative
                    0 'check-declarative-stuffing
                    :module 'declarative 
                    :destination 'declarative
                    :output 'low 
                    :priority :min
                    :maintenance t
                )
            )
        )
    )

    ;; Find any existing matching chunk
    (let
        (
            (existing 
                (if (dm-fast-merge dm)
                    (gethash (hash-chunk-contents chunk) (dm-chunk-hash-table dm))
                    (find
                        chunk 
                        (gethash (chunk-chunk-type-fct chunk) (dm-chunks dm))
                        :test #'equal-chunks-fct
                    )
                )
            )
        )

        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;;;;;; START: [HRM] related code

        ;;;; [SC] if chunk is cleared from a visual buffer then put that chunk into VSTM instead of DM
        (if (eq buffer 'visual)
            (let ((paav-mod (get-module :vision)))
                (if (enable-vstm paav-mod) ;; [SC][2013.12.20][ENABLE-VSTM] perform this override only if VTSM functionality is enabled
                    (progn
                        (if existing
                            ;;;; [SC] put "existing" chunk into VSTM
                            (add-vis-object-to-vstm paav-mod existing)
                        
                            ;;;; [SC] put "chunk" chunk into VSTM
                            (add-vis-object-to-vstm paav-mod chunk)
                        )
                        (return-from merge-chunk-into-dm)
                    )
                )
            )
        )

        ;;;;;; END: [HRM] related code
        ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        (if existing
            (progn
                (merge-chunks-fct existing chunk)  ;; merging functions handle params
                (when (car (dm-chunk-merge-hook dm))
                    (dolist (x (dm-chunk-merge-hook dm))
                        (funcall x chunk)
                    )
                )
            )
            
            ;; otherwise add it to the list
            (add-chunk-into-dm dm chunk)
        )
    )
)

;;;;;; END: Overriden methods from other modules
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: Auto buffer stuffing:

; defmethod visual-auto-attend ((vis-mod vision-module))
    ; called in: find-location

;;;;;; END:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


    #|(default-acuity-a :accessor default-acuity-a :initform 0)
    (default-acuity-b :accessor default-acuity-b :initform 0)
    ;;;; [SC] fitted
    (fcolor-acuity-a :accessor fcolor-acuity-a :initform 0.035)
    (fcolor-acuity-b :accessor fcolor-acuity-b :initform 0.601)
    ;;;; [SC] fitted
    (fshape-acuity-a :accessor fshape-acuity-a :initform 0.1)
    (fshape-acuity-b :accessor fshape-acuity-b :initform 0.601)
    ;;;; [SC] not fitted
    (fshading-acuity-a :accessor fshading-acuity-a :initform 0.12)
    (fshading-acuity-b :accessor fshading-acuity-b :initform 0.601)
    ;;;; [SC] not fitted
    (fsize-acuity-a :accessor fsize-acuity-a :initform 0.1)
    (fsize-acuity-b :accessor fsize-acuity-b :initform 0.57)
    ;;;; [SC] not fitted
    (forient-acuity-a :accessor forient-acuity-a :initform 0.1)
    (forient-acuity-b :accessor forient-acuity-b :initform 0.601)|#

    ;;;; [SC] those default values will be used everytime module is reset
    ;;;; [SC] acuity ser with following fit of DR for SET
    ;;;; color: , shading: , number: , shape: 
    #|(default-acuity-a :accessor default-acuity-a :initform 0)
    (default-acuity-b :accessor default-acuity-b :initform 0)
    ;;;; [SC] fitted
    (fcolor-acuity-a :accessor fcolor-acuity-a :initform 0.035)
    (fcolor-acuity-b :accessor fcolor-acuity-b :initform 0.601)
    ;;;; [SC] fitted
    (fshape-acuity-a :accessor fshape-acuity-a :initform 0.15)
    (fshape-acuity-b :accessor fshape-acuity-b :initform 0.96)
    ;;;; [SC] not fitted
    (fshading-acuity-a :accessor fshading-acuity-a :initform 0.3)
    (fshading-acuity-b :accessor fshading-acuity-b :initform 0.601)
    ;;;; [SC] not fitted
    (fsize-acuity-a :accessor fsize-acuity-a :initform 0.1)
    (fsize-acuity-b :accessor fsize-acuity-b :initform 0.601)
    ;;;; [SC] not fitted
    (forient-acuity-a :accessor forient-acuity-a :initform 0.1)
    (forient-acuity-b :accessor forient-acuity-b :initform 0.601)|#
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;;; [SC] acuity set with following fit of DR for SET
    ;;;; color: 27%, shading 18.5%, number: 16.5%, shape: 10.5%
    #|(default-acuity-a :accessor default-acuity-a :initform 0)
    (default-acuity-b :accessor default-acuity-b :initform 0)
    ;;;; [SC] fitted
    (fcolor-acuity-a :accessor fcolor-acuity-a :initform 0.035)
    (fcolor-acuity-b :accessor fcolor-acuity-b :initform 0.601)
    ;;;; [SC] fitted
    (fshape-acuity-a :accessor fshape-acuity-a :initform 0.1)
    (fshape-acuity-b :accessor fshape-acuity-b :initform 0.601)
    ;;;; [SC] not fitted
    (fshading-acuity-a :accessor fshading-acuity-a :initform 0.1)
    (fshading-acuity-b :accessor fshading-acuity-b :initform 0.65)
    ;;;; [SC] not fitted
    (fsize-acuity-a :accessor fsize-acuity-a :initform 0.1)
    (fsize-acuity-b :accessor fsize-acuity-b :initform 0.65)
    ;;;; [SC] not fitted
    (forient-acuity-a :accessor forient-acuity-a :initform 0.1)
    (forient-acuity-b :accessor forient-acuity-b :initform 0.601)|#


;;;; [SC] a modified function from /framework/buffers.lisp
;;;; [SC] Original package's revision version and date: r1227, June4 2012
#|(defun clear-buffer (buffer-name)
    
    (format t "~%CLEAR-BUFFER: ~a" buffer-name)

    (verify-current-mp  
        "clear-buffer called with no current meta-process."
        (verify-current-model
            "clear-buffer called with no current model."
            (let ((buffer (buffer-instance buffer-name)))
                (cond
                    ((null buffer)
                        (print-warning "clear-buffer called with an invalid buffer name ~S" buffer-name)
                    )
                    (t
                        (let ((chunk (act-r-buffer-chunk buffer)))
                            (when chunk
                                
                                (format t "~%CLEAR-BUFFER: HERE1")

                                (setf (act-r-buffer-chunk buffer) nil)

                                (format t "~%CLEAR-BUFFER: HERE2")

                                (setf (chunk-buffer-set-invalid chunk) t)

                                (format t "~%CLEAR-BUFFER: HERE3")

                                (when (act-r-buffer-multi buffer)
                                    (remhash chunk (act-r-buffer-chunk-set buffer))
                                    (format t "~%CLEAR-BUFFER: HERE4")
                                )

                                (dolist (module (notified-modules))
                                    (format t "~%CLEAR-BUFFER - NOTIFY MODULE - HERE1: ~a" module)
                                    (notify-module module buffer-name chunk)
                                    (format t "~%CLEAR-BUFFER - NOTIFY MODULE - HERE2: ~a" module)
                                )
                            )
                            chunk
                        )
                    )
                )
            )
        )
    )
)|#


#|
(defmacro merge-dm (&rest chunk-list)
  `(merge-dm-fct ',chunk-list))

(defun merge-dm-fct (chunk-definitions)
  
  ;; Need to find the current instance of the declarative module
  
  (let ((dm (get-module declarative)))  

    ;; if there is one, create the chunks and set the parameters

    (if (dm-p dm)  

        ;; pass the list of chunk defs off to define-chunks 
        ;; to do the creation

        (let* ((chunks (define-chunks-fct chunk-definitions))
               (ordering (mapcar (lambda (x) 
                                   (list (cons x (mapcan (lambda (y)
                                                     (when (and (chunk-p-fct y)
                                                                (find y chunks))
                                                       (list y)))
                                             (mapcar (lambda (z) (fast-chunk-slot-value-fct x z)) (chunk-type-slot-names-fct  (chunk-chunk-type-fct x)))))))
                           chunks)))
          
          (if (circular-references-dm ordering)
              (progn
                (model-warning "Chunks in call to merge-dm have circular references.")
                (model-warning "  Because of that there is no safe order for merging and they will be merged in the order provided.")
                (dolist (chunk chunks chunks)
                  (merge-chunk-into-dm dm nil chunk t)))
            
            (progn
              (setf chunks (mapcar 'caar (sort-for-binding-dm ordering)))
              (dolist (chunk chunks chunks)
                (merge-chunk-into-dm dm nil chunk t)))))
          
       ;; otherwise report a warning to the meta-process because there may not
       ;; be a current model 

      (print-warning 
       "Could not create chunks because no declarative module was found"))))
       |#


;;;; [DELETE]
#|(defun parse-buffers (buffer-list)
  (let ((res nil))
    (dolist (buffer-def buffer-list res)
      
      ;; Adding a pre-check to make sure the name is a symbol, not a keyword, and that it
      ;; doesn't end in > to avoid crazy issues with production parsing
      
      (let ((name (if (atom buffer-def) buffer-def (car buffer-def))))
        
        (unless (and (symbolp name) (not (keywordp name)))
          (print-warning "Buffer name ~s is not valid because a buffer name must be a non-keyword symbol" name)
          (return-from parse-buffers :error))
        (let ((sym (symbol-name name)))
          (when (eql #\> (aref sym (1- (length sym))))
            (print-warning "Buffer name ~s is not valid because a buffer name must not end with the character '>'" name)
            (return-from parse-buffers :error))
          (when (eql #\= (aref sym 0))
            (print-warning "Buffer name ~s is not valid because a buffer name must not start with the character '='" name)
            (return-from parse-buffers :error))))

      (cond ((or (atom buffer-def)
                 (and (listp buffer-def) (= (length buffer-def) 1)))
             (when (listp buffer-def)
               (setf buffer-def (car buffer-def)))
             (cond ((buffer-exists buffer-def)
                    (print-warning "Buffer name ~S already used, cannot reuse it.")
                    (return-from parse-buffers :error))
                   (t
                    (push (make-act-r-buffer 
                           :name buffer-def
                           :queries *required-buffer-queries*
                           :copy t
                           :parameter-name 
                           (read-from-string (format nil ":~S-activation" buffer-def)))
                          res))))
            ((and (listp buffer-def)
                  (buffer-exists (car buffer-def)))
             (print-warning "Buffer name ~S already used, cannot reuse it.")
             (return-from parse-buffers :error))
            
            ((not (listp buffer-def))
             (print-warning "Invalid buffer specification: ~S" buffer-def)
             (return-from parse-buffers :error))

            ((<= (length buffer-def) 6)
             (let (param-name param-default requests queries print-status multi searchable
                   (copy t))
               (if (and (second buffer-def) (listp (second buffer-def)))
                   (cond ((or 
                           (> (length (second buffer-def)) 2)
                           (not (keywordp (first (second buffer-def))))
                           (not (numberp (second (second buffer-def)))))
                          (print-warning "Invalid buffer specification: ~S" buffer-def)
                          (return-from parse-buffers :error))
                         (t
                          (setf param-name (first (second buffer-def)))
                          (setf param-default (second (second buffer-def)))))
                 (cond ((keywordp (second buffer-def))
                        (setf param-name (second buffer-def)))
                       ((null (second buffer-def))
                        (setf param-name
                          (read-from-string (format nil ":~S-activation" (first buffer-def)))))
                       (t
                        (print-warning "Invalid buffer specification: ~S" buffer-def)
                        (return-from parse-buffers :error))))
               (when (third buffer-def)
                 (cond ((and (listp (third buffer-def))
                             (every #'keywordp (third buffer-def)))
                        (setf requests (third buffer-def)))
                       (t
                        (print-warning "Invalid buffer specification: ~S" buffer-def)
                        (return-from parse-buffers :error))))
               (when (fourth buffer-def)
                 (cond ((and (listp (fourth buffer-def))
                             (every #'(lambda (x) 
                                        (and (symbolp x) (not (keywordp x))
                                             (not (find x *required-buffer-queries*))))
                                    (fourth buffer-def)))
                        (setf queries (fourth buffer-def)))
                       (t
                        (print-warning "Invalid buffer specification: ~S" buffer-def)
                        (return-from parse-buffers :error))))
               (when (fifth buffer-def)
                 (cond ((fctornil (fifth buffer-def))
                        (setf print-status (fifth buffer-def)))
                       (t
                        (print-warning "Invalid buffer specification: ~S" buffer-def)
                        (print-warning "status function not valid")
                        (return-from parse-buffers :error))))
               
               (when (sixth buffer-def)
                 (case (sixth buffer-def)
                   (:multi (setf multi t)
                           (setf copy nil))
                   (:search
                    (setf multi t)
                    (setf searchable t)
                    (setf copy nil))
                   (:multi-copy 
                    (setf multi t))
                   (:search-copy
                    (setf multi t)
                    (setf searchable t))
                   (t
                    (print-warning "Invalid multi-buffer specification ~S for buffer ~s." buffer-def (first buffer-def))
                    (return-from parse-buffers :error))))
                   

               
               (when (valid-parameter-name param-name) 
                 (print-warning "Buffer spread parameter ~S is already the name of a parameter." param-name)
                 (return-from parse-buffers :error))
                                
               (push (make-act-r-buffer 
                      :name (first buffer-def)
                      :queries (append queries *required-buffer-queries*)
                      :requests requests
                      :parameter-name param-name
                      :spread param-default
                      :status-printing print-status
                      :multi multi
                      :searchable searchable
                      :copy copy
                      :chunk-set (make-hash-table :test 'eq :size 5)
                      :requested nil)
                     res)))
            (t
             (print-warning "Invalid buffer specification: ~S" buffer-def)
             (return-from parse-buffers :error))))))
             |#

             ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; START: [HRM]

;;;; [DELETE]
#|
(defmethod attend-to-object ((vis-mod vision-module) obj &key (requested t))

    (format t "~%ATTEND-TO-OBJECT: ~a" obj)
  
    ;;; put the chunk in the buffer
  
    (schedule-set-buffer-chunk 'visual obj 0 :module :vision :priority 10 :requested requested)
  
    ;; record the object for tracking purposes
  
    (setf (last-obj vis-mod) obj)
  
    ;; update the time-stamp on the finst if it's already attended or
    ;; add a new finst if it's not
  
    (aif (member (icon-entry vis-mod obj) (finst-lst vis-mod) :key #'id :test 'equal)
       
        (setf (tstamp (first it)) (mp-time-ms))
       
        (add-finst vis-mod obj)
    )
)
|#

;;;; [DELETE]
#|
(defun set-buffer-chunk (buffer-name chunk-name &key (requested t))
    "Forces a copy unless it's a multi-buffer and this chunk is in the set"
    (verify-current-mp  
        "set-buffer-chunk called with no current meta-process."
        (verify-current-model
            "set-buffer-chunk called with no current model."
            (let ((buffer (buffer-instance buffer-name)))
                (cond 
                    ((null buffer)
                        (print-warning "set-buffer-chunk called with an invalid buffer name ~S" buffer-name)
                    )
                    ((null (get-chunk chunk-name))
                        (print-warning "set-buffer-chunk called with an invalid chunk name ~S" chunk-name)
                    )
                    (t
                        (when (act-r-buffer-chunk buffer)
                            (clear-buffer buffer-name)
                        )
                        (setf (act-r-buffer-requested buffer) requested)
                        (let 
                            (
                                (copy-name 
                                    (if 
                                        (or 
                                            (act-r-buffer-copy buffer)
                                            (chunk-buffer-set-invalid chunk-name)
                                            (null (gethash chunk-name (act-r-buffer-chunk-set buffer)))
                                        )
                                        (copy-chunk-fct chunk-name)
                                        chunk-name
                                    )
                                )
                            )
                            (when 
                                (and
                                    (show-copy-buffer-trace)
                                    (not (eq copy-name chunk-name))
                                )
                                
                                (schedule-event-relative 
                                    0 'show-buffer-copy
                                    :maintenance t
                                    :module 'buffer
                                    :priority :max
                                    :details (concatenate 'string "Buffer " (string buffer-name) " copied chunk " (string chunk-name) " to " (string copy-name))
                                    :output 'medium
                                )
                            )
                            (setf (act-r-buffer-chunk buffer) copy-name)
                        )
                    )
                )
            )
        )
    )
)
|#

;;;;;; END: [HRM]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;