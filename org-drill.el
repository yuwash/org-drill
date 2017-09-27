;;; -*- coding: utf-8-unix -*-
;;; org-drill.el - Self-testing using spaced repetition
;;;
;;; Copyright (C) 2010-2015  Paul Sexton
;;;
;;; Author: Paul Sexton <eeeickythump@gmail.com>
;;; Version: 2.6.1
;;; Keywords: flashcards, memory, learning, memorization
;;; Repository at http://bitbucket.org/eeeickythump/org-drill/
;;;
;;; This file is not part of GNU Emacs.
;;;
;;; This program is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;;
;;;
;;; Synopsis
;;; ========
;;;
;;; Within an Org mode outline or outlines, headings and associated content are
;;; treated as "flashcards". Spaced repetition algorithms are used to conduct
;;; interactive "drill sessions", where a selection of these flashcards is
;;; presented to the student in random order. The student rates his or her
;;; recall of each item, and this information is used to schedule the item for
;;; later revision.
;;;
;;; Each drill session can be restricted to topics in the current buffer
;;; (default), one or several files, all agenda files, or a subtree. A single
;;; topic can also be tested.
;;;
;;; Different "card types" can be defined, which present their information to
;;; the student in different ways.
;;;
;;; See the file README.org for more detailed documentation.


(defcustom org-drill-question-tag
  "drill"
  "Tag which topics must possess in order to be identified as review topics
by `org-drill'."
  :group 'org-drill
  :type 'string)


(defcustom org-drill-maximum-items-per-session
  30
  "Each drill session will present at most this many topics for review.
Nil means unlimited."
  :group 'org-drill
  :type '(choice integer (const nil)))



(defcustom org-drill-maximum-duration
  20
  "Maximum duration of a drill session, in minutes.
Nil means unlimited."
  :group 'org-drill
  :type '(choice integer (const nil)))


(defcustom org-drill-item-count-includes-failed-items-p
  nil
  "If non-nil, when you fail an item it still counts towards the
count of items reviewed for the current session. If nil (default),
only successful items count towards this total."
  :group 'org-drill
  :type 'boolean)


(defcustom org-drill-failure-quality
  2
  "If the quality of recall for an item is this number or lower,
it is regarded as an unambiguous failure, and the repetition
interval for the card is reset to 0 days.  If the quality is higher
than this number, it is regarded as successfully recalled, but the
time interval to the next repetition will be lowered if the quality
was near to a fail.

By default this is 2, for SuperMemo-like behaviour. For
Mnemosyne-like behaviour, set it to 1.  Other values are not
really sensible."
  :group 'org-drill
  :type '(choice (const 2) (const 1)))


(defcustom org-drill-forgetting-index
  10
  "What percentage of items do you consider it is 'acceptable' to
forget each drill session? The default is 10%. A warning message
is displayed at the end of the session if the percentage forgotten
climbs above this number."
  :group 'org-drill
  :type 'integer)


(defcustom org-drill-leech-failure-threshold
  15
  "If an item is forgotten more than this many times, it is tagged
as a 'leech' item."
  :group 'org-drill
  :type '(choice integer (const nil)))


(defcustom org-drill-leech-method
  'skip
  "How should 'leech items' be handled during drill sessions?
Possible values:
- nil :: Leech items are treated the same as normal items.
- skip :: Leech items are not included in drill sessions.
- warn :: Leech items are still included in drill sessions,
  but a warning message is printed when each leech item is
  presented."
  :group 'org-drill
  :type '(choice (const warn) (const skip) (const nil)))


(defface org-drill-visible-cloze-face
  '((t (:foreground "darkseagreen")))
  "The face used to hide the contents of cloze phrases."
  :group 'org-drill)


(defface org-drill-visible-cloze-hint-face
  '((t (:foreground "dark slate blue")))
  "The face used to hide the contents of cloze phrases."
  :group 'org-drill)


(defface org-drill-hidden-cloze-face
  '((t (:foreground "deep sky blue" :background "blue")))
  "The face used to hide the contents of cloze phrases."
  :group 'org-drill)


(defcustom org-drill-use-visible-cloze-face-p
  nil
  "Use a special face to highlight cloze-deleted text in org mode
buffers?"
  :group 'org-drill
  :type 'boolean)


(defcustom org-drill-hide-item-headings-p
  nil
  "Conceal the contents of the main heading of each item during drill
sessions? You may want to enable this behaviour if item headings or tags
contain information that could 'give away' the answer."
  :group 'org-drill
  :type 'boolean)


(defcustom org-drill-new-count-color
  "royal blue"
  "Foreground colour used to display the count of remaining new items
during a drill session."
  :group 'org-drill
  :type 'color)

(defcustom org-drill-mature-count-color
  "green"
  "Foreground colour used to display the count of remaining mature items
during a drill session. Mature items are due for review, but are not new."
  :group 'org-drill
  :type 'color)

(defcustom org-drill-failed-count-color
  "red"
  "Foreground colour used to display the count of remaining failed items
during a drill session."
  :group 'org-drill
  :type 'color)

(defcustom org-drill-done-count-color
  "sienna"
  "Foreground colour used to display the count of reviewed items
during a drill session."
  :group 'org-drill
  :type 'color)

(defcustom org-drill-left-cloze-delimiter
  "["
  "String used within org buffers to delimit cloze deletions."
  :group 'org-drill
  :type 'string)

(defcustom org-drill-right-cloze-delimiter
  "]"
  "String used within org buffers to delimit cloze deletions."
  :group 'org-drill
  :type 'string)


(setplist 'org-drill-cloze-overlay-defaults
          `(display ,(format "%s...%s"
                             org-drill-left-cloze-delimiter
                             org-drill-right-cloze-delimiter)
                    face org-drill-hidden-cloze-face
                    window t))

(setplist 'org-drill-hidden-text-overlay
          '(invisible t))

(setplist 'org-drill-replaced-text-overlay
          '(display "Replaced text"
                    face default
                    window t))

(add-hook 'org-font-lock-set-keywords-hook 'org-drill-add-cloze-fontification)


(defvar org-drill-hint-separator "||"
  "String which, if it occurs within a cloze expression, signifies that the
rest of the expression after the string is a `hint', to be displayed instead of
the hidden cloze during a test.")

(defun org-drill--compute-cloze-regexp ()
  (concat "\\("
          (regexp-quote org-drill-left-cloze-delimiter)
          "[[:cntrl:][:graph:][:space:]]+?\\)\\(\\|"
          (regexp-quote org-drill-hint-separator)
          ".+?\\)\\("
          (regexp-quote org-drill-right-cloze-delimiter)
          "\\)"))

(defun org-drill--compute-cloze-keywords ()
  (list (list (org-drill--compute-cloze-regexp)
              (copy-list '(1 'org-drill-visible-cloze-face nil))
              (copy-list '(2 'org-drill-visible-cloze-hint-face t))
              (copy-list '(3 'org-drill-visible-cloze-face nil))
              )))

(defvar-local org-drill-cloze-regexp
  (org-drill--compute-cloze-regexp))


(defvar-local org-drill-cloze-keywords
  (org-drill--compute-cloze-keywords))


;; Variables defining what keys can be pressed during drill sessions to quit the
;; session, edit the item, etc.
(defvar org-drill--quit-key ?q
  "If this character is pressed during a drill session, quit the session.")
(defvar org-drill--edit-key ?e
  "If this character is pressed during a drill session, suspend the session
with the cursor at the current item..")
(defvar org-drill--help-key ??
  "If this character is pressed during a drill session, show help.")
(defvar org-drill--skip-key ?s
  "If this character is pressed during a drill session, skip to the next
item.")
(defvar org-drill--tags-key ?t
  "If this character is pressed during a drill session, edit the tags for
the current item.")


(defcustom org-drill-card-type-alist
  '((nil org-drill-present-simple-card)
    ("simple" org-drill-present-simple-card)
    ("simpletyped" org-drill-present-simple-card-with-typed-answer)
    ("twosided" org-drill-present-two-sided-card nil t)
    ("multisided" org-drill-present-multi-sided-card nil t)
    ("hide1cloze" org-drill-present-multicloze-hide1)
    ("hide2cloze" org-drill-present-multicloze-hide2)
    ("show1cloze" org-drill-present-multicloze-show1)
    ("show2cloze" org-drill-present-multicloze-show2)
    ("multicloze" org-drill-present-multicloze-hide1)
    ("hidefirst" org-drill-present-multicloze-hide-first)
    ("hidelast" org-drill-present-multicloze-hide-last)
    ("hide1_firstmore" org-drill-present-multicloze-hide1-firstmore)
    ("show1_lastmore" org-drill-present-multicloze-show1-lastmore)
    ("show1_firstless" org-drill-present-multicloze-show1-firstless)
    ("conjugate"
     org-drill-present-verb-conjugation
     org-drill-show-answer-verb-conjugation)
    ("decline_noun"
     org-drill-present-noun-declension
     org-drill-show-answer-noun-declension)
    ("spanish_verb" org-drill-present-spanish-verb)
    ("translate_number" org-drill-present-translate-number))
  "Alist associating card types with presentation functions. Each
entry in the alist takes the form:

;;; (CARDTYPE QUESTION-FN [ANSWER-FN DRILL-EMPTY-P])

Where CARDTYPE is a string or nil (for default), and QUESTION-FN
is a function which takes no arguments and returns a boolean
value.

When supplied, ANSWER-FN is a function that takes one argument --
that argument is a function of no arguments, which when called,
prompts the user to rate their recall and performs rescheduling
of the drill item. ANSWER-FN is called with the point on the
active item's heading, just prior to displaying the item's
'answer'. It can therefore be used to modify the appearance of
the answer. ANSWER-FN must call its argument before returning.

When supplied, DRILL-EMPTY-P is a boolean value, default nil.
When non-nil, cards of this type will be presented during tests
even if their bodies are empty."
  :group 'org-drill
  :type '(alist :key-type (choice string (const nil))
                :value-type function))


(defcustom org-drill-scope
  'file
  "The scope in which to search for drill items when conducting a
drill session. This can be any of:

file                 The current buffer, respecting the restriction if any.
                     This is the default.
tree                 The subtree started with the entry at point
file-no-restriction  The current buffer, without restriction
file-with-archives   The current buffer, and any archives associated with it.
agenda               All agenda files
agenda-with-archives All agenda files with any archive files associated
                     with them.
directory            All files with the extension '.org' in the same
                     directory as the current file (includes the current
                     file if it is an .org file.)
 (FILE1 FILE2 ...)   If this is a list, all files in the list will be scanned.
"
  ;; Note -- meanings differ slightly from the argument to org-map-entries:
  ;; 'file' means current file/buffer, respecting any restriction
  ;; 'file-no-restriction' means current file/buffer, ignoring restrictions
  ;; 'directory' means all *.org files in current directory
  :group 'org-drill
  :type '(choice (const :tag "The current buffer, respecting the restriction if any." file)
                 (const :tag "The subtree started with the entry at point" tree)
                 (const :tag "The current buffer, without restriction" file-no-restriction)
                 (const :tag "The current buffer, and any archives associated with it." file-with-archives)
                 (const :tag "All agenda files" agenda)
                 (const :tag "All agenda files with any archive files associated with them." agenda-with-archives)
                 (const :tag "All files with the extension '.org' in the same directory as the current file (includes the current file if it is an .org file.)"  directory)
                 (repeat :tag "List of files to scan for drill items." file)))


(defcustom org-drill-match
  nil
  "If non-nil, a string specifying a tags/property/TODO query. During
drill sessions, only items that match this query will be considered."
  :group 'org-drill
  :type '(choice (const nil) string))


(defcustom org-drill-save-buffers-after-drill-sessions-p
  t
  "If non-nil, prompt to save all modified buffers after a drill session
finishes."
  :group 'org-drill
  :type 'boolean)


(defcustom org-drill-spaced-repetition-algorithm
  'sm5
  "Which SuperMemo spaced repetition algorithm to use for scheduling items.
Available choices are:
- SM2 :: the SM2 algorithm, used in SuperMemo 2.0
- SM5 :: the SM5 algorithm, used in SuperMemo 5.0
- Simple8 :: a modified version of the SM8 algorithm. SM8 is used in
  SuperMemo 98. The version implemented here is simplified in that while it
  'learns' the difficulty of each item using quality grades and number of
  failures, it does not modify the matrix of values that
  governs how fast the inter-repetition intervals increase. A method for
  adjusting intervals when items are reviewed early or late has been taken
  from SM11, a later version of the algorithm, and included in Simple8."
  :group 'org-drill
  :type '(choice (const sm2) (const sm5) (const simple8)))


(defcustom org-drill-optimal-factor-matrix
  nil
  "Obsolete and will be removed in future. The SM5 optimal factor
matrix data is now stored in the variable
`org-drill-sm5-optimal-factor-matrix'."
  :group 'org-drill
  :type 'sexp)


(defvar org-drill-sm5-optimal-factor-matrix
  nil
  "DO NOT CHANGE THE VALUE OF THIS VARIABLE.

Persistent matrix of optimal factors, used by the SuperMemo SM5
algorithm. The matrix is saved at the end of each drill session.

Over time, values in the matrix will adapt to the individual user's
pace of learning.")


(add-to-list 'savehist-additional-variables
             'org-drill-sm5-optimal-factor-matrix)
(unless savehist-mode
  (savehist-mode 1))


(defun org-drill--transfer-optimal-factor-matrix ()
  (if (and org-drill-optimal-factor-matrix
           (null org-drill-sm5-optimal-factor-matrix))
      (setq org-drill-sm5-optimal-factor-matrix
            org-drill-optimal-factor-matrix)))

(add-hook 'after-init-hook 'org-drill--transfer-optimal-factor-matrix)


(defcustom org-drill-sm5-initial-interval
  4.0
  "In the SM5 algorithm, the initial interval after the first
successful presentation of an item is always 4 days. If you wish to change
this, you can do so here."
  :group 'org-drill
  :type 'float)


(defcustom org-drill-add-random-noise-to-intervals-p
  nil
  "If true, the number of days until an item's next repetition
will vary slightly from the interval calculated by the SM2
algorithm. The variation is very small when the interval is
small, but scales up with the interval."
  :group 'org-drill
  :type 'boolean)


(defcustom org-drill-adjust-intervals-for-early-and-late-repetitions-p
  nil
  "If true, when the student successfully reviews an item 1 or more days
before or after the scheduled review date, this will affect that date of
the item's next scheduled review, according to the algorithm presented at
 [[http://www.supermemo.com/english/algsm11.htm#Advanced%20repetitions]].

Items that were reviewed early will have their next review date brought
forward. Those that were reviewed late will have their next review
date postponed further.

Note that this option currently has no effect if the SM2 algorithm
is used."
  :group 'org-drill
  :type 'boolean)


(defcustom org-drill-cloze-text-weight
  4
  "For card types 'hide1_firstmore', 'show1_lastmore' and 'show1_firstless',
this number determines how often the 'less favoured' situation
should arise. It will occur 1 in every N trials, where N is the
value of the variable.

For example, with the hide1_firstmore card type, the first piece
of clozed text should be hidden more often than the other
pieces. If this variable is set to 4 (default), the first item
will only be shown 25% of the time (1 in 4 trials). Similarly for
show1_lastmore, the last item will be shown 75% of the time, and
for show1_firstless, the first item would only be shown 25% of the
time.

If the value of this variable is NIL, then weighting is disabled, and
all weighted card types are treated as their unweighted equivalents."
  :group 'org-drill
  :type '(choice integer (const nil)))


(defcustom org-drill-cram-hours
  12
  "When in cram mode, items are considered due for review if
they were reviewed at least this many hours ago."
  :group 'org-drill
  :type 'integer)


;;; NEW items have never been presented in a drill session before.
;;; MATURE items HAVE been presented at least once before.
;;; - YOUNG mature items were scheduled no more than
;;;   ORG-DRILL-DAYS-BEFORE-OLD days after their last
;;;   repetition. These items will have been learned 'recently' and will have a
;;;   low repetition count.
;;; - OLD mature items have intervals greater than
;;;   ORG-DRILL-DAYS-BEFORE-OLD.
;;; - OVERDUE items are past their scheduled review date by more than
;;;   LAST-INTERVAL * (ORG-DRILL-OVERDUE-INTERVAL-FACTOR - 1) days,
;;;   regardless of young/old status.


(defcustom org-drill-days-before-old
  10
  "When an item's inter-repetition interval rises above this value in days,
it is no longer considered a 'young' (recently learned) item."
  :group 'org-drill
  :type 'integer)


(defcustom org-drill-overdue-interval-factor
  1.2
  "An item is considered overdue if its scheduled review date is
more than (ORG-DRILL-OVERDUE-INTERVAL-FACTOR - 1) * LAST-INTERVAL
days in the past. For example, a value of 1.2 means an additional
20% of the last scheduled interval is allowed to elapse before
the item is overdue. A value of 1.0 means no extra time is
allowed at all - items are immediately considered overdue if
there is even one day's delay in reviewing them. This variable
should never be less than 1.0."
  :group 'org-drill
  :type 'float)


(defcustom org-drill-learn-fraction
  0.5
  "Fraction between 0 and 1 that governs how quickly the spaces
between successive repetitions increase, for all items. The
default value is 0.5. Higher values make spaces increase more
quickly with each successful repetition. You should only change
this in small increments (for example 0.05-0.1) as it has an
exponential effect on inter-repetition spacing."
  :group 'org-drill
  :type 'float)


(defvar drill-answer nil
  "Global variable that can be bound to a correct answer when an
item is being presented. If this variable is non-nil, the default
presentation function will show its value instead of the default
behaviour of revealing the contents of the drilled item.

This variable is useful for card types that compute their answers
-- for example, a card type that asks the student to translate a
random number to another language. ")


(defvar drill-typed-answer nil
  "Global variable that can be bound to the last answer typed by
the user. Used by card types that ask the user to type in an
answer, rather than just pressing spacebar to reveal the
answer.")


(defcustom org-drill-cloze-length-matches-hidden-text-p
  nil
  "If non-nil, when concealing cloze deletions, force the length of
the ellipsis to match the length of the missing text. This may be useful
to preserve the formatting in a displayed table, for example."
  :group 'org-drill
  :type 'boolean)


(defvar *org-drill-session-qualities* nil)
(defvar *org-drill-start-time* 0)
(defvar *org-drill-new-entries* nil)
(defvar *org-drill-dormant-entry-count* 0)
(defvar *org-drill-due-entry-count* 0)
(defvar *org-drill-overdue-entry-count* 0)
(defvar *org-drill-due-tomorrow-count* 0)
(defvar *org-drill-overdue-entries* nil
  "List of markers for items that are considered 'overdue', based on
the value of ORG-DRILL-OVERDUE-INTERVAL-FACTOR.")
(defvar *org-drill-young-mature-entries* nil
  "List of markers for mature entries whose last inter-repetition
interval was <= ORG-DRILL-DAYS-BEFORE-OLD days.")
(defvar *org-drill-old-mature-entries* nil
  "List of markers for mature entries whose last inter-repetition
interval was greater than ORG-DRILL-DAYS-BEFORE-OLD days.")
(defvar *org-drill-failed-entries* nil)
(defvar *org-drill-again-entries* nil)
(defvar *org-drill-done-entries* nil)
(defvar *org-drill-current-item* nil
  "Set to the marker for the item currently being tested.")
(defvar *org-drill-cram-mode* nil
  "Are we in 'cram mode', where all items are considered due
for review unless they were already reviewed in the recent past?")
(defvar org-drill-scheduling-properties
  '("LEARN_DATA" "DRILL_LAST_INTERVAL" "DRILL_REPEATS_SINCE_FAIL"
    "DRILL_TOTAL_REPEATS" "DRILL_FAILURE_COUNT" "DRILL_AVERAGE_QUALITY"
    "DRILL_EASE" "DRILL_LAST_QUALITY" "DRILL_LAST_REVIEWED"))
(defvar org-drill--lapse-very-overdue-entries-p nil
  "If non-nil, entries more than 90 days overdue are regarded as 'lapsed'.
This means that when the item is eventually re-tested it will be
treated as 'failed' (quality 2) for rescheduling purposes,
regardless of whether the test was successful.")


;;;; Utilities ================================================================


(defun round-float (floatnum fix)
  "Round the floating point number FLOATNUM to FIX decimal places.
Example: (round-float 3.56755765 3) -> 3.568"
  (let ((n (expt 10 fix)))
    (/ (float (round (* floatnum n))) n)))


;;; SM2 Algorithm =============================================================


(defun determine-next-interval-sm2 (last-interval n ef quality
                                                  failures meanq total-repeats)
  "Arguments:
- LAST-INTERVAL -- the number of days since the item was last reviewed.
- REPEATS -- the number of times the item has been successfully reviewed
- EF -- the 'easiness factor'
- QUALITY -- 0 to 5

Returns a list: (INTERVAL REPEATS EF FAILURES MEAN TOTAL-REPEATS OFMATRIX), where:
- INTERVAL is the number of days until the item should next be reviewed
- REPEATS is incremented by 1.
- EF is modified based on the recall quality for the item.
- OF-MATRIX is not modified."
  (if (zerop n) (setq n 1))
  (if (null ef) (setq ef 2.5))
  (setq meanq (if meanq
                  (/ (+ quality (* meanq total-repeats 1.0))
                     (1+ total-repeats))
                quality))
  (assert (> n 0))
  (assert (and (>= quality 0) (<= quality 5)))
  (if (<= quality org-drill-failure-quality)
      ;; When an item is failed, its interval is reset to 0,
      ;; but its EF is unchanged
      (list -1 1 ef (1+ failures) meanq (1+ total-repeats)
            org-drill-sm5-optimal-factor-matrix)
    ;; else:
    (let* ((next-ef (modify-e-factor ef quality))
           (interval
            (cond
             ((<= n 1) 1)
             ((= n 2)
              (cond
               (org-drill-add-random-noise-to-intervals-p
                (case quality
                  (5 6)
                  (4 4)
                  (3 3)
                  (2 1)
                  (t -1)))
               (t 6)))
             (t (* last-interval next-ef)))))
      (list (if org-drill-add-random-noise-to-intervals-p
                (+ last-interval (* (- interval last-interval)
                                    (org-drill-random-dispersal-factor)))
              interval)
            (1+ n)
            next-ef
            failures meanq (1+ total-repeats)
            org-drill-sm5-optimal-factor-matrix))))


;;; SM5 Algorithm =============================================================



(defun initial-optimal-factor-sm5 (n ef)
  (if (= 1 n)
      org-drill-sm5-initial-interval
    ef))

(defun get-optimal-factor-sm5 (n ef of-matrix)
  (let ((factors (assoc n of-matrix)))
    (or (and factors
             (let ((ef-of (assoc ef (cdr factors))))
               (and ef-of (cdr ef-of))))
        (initial-optimal-factor-sm5 n ef))))


(defun inter-repetition-interval-sm5 (last-interval n ef &optional of-matrix)
  (let ((of (get-optimal-factor-sm5 n ef (or of-matrix
                                             org-drill-sm5-optimal-factor-matrix))))
    (if (= 1 n)
        of
      (* of last-interval))))


(defun determine-next-interval-sm5 (last-interval n ef quality
                                                  failures meanq total-repeats
                                                  of-matrix &optional delta-days)
  (if (zerop n) (setq n 1))
  (if (null ef) (setq ef 2.5))
  (assert (> n 0))
  (assert (and (>= quality 0) (<= quality 5)))
  (unless of-matrix
    (setq of-matrix org-drill-sm5-optimal-factor-matrix))
  (setq of-matrix (cl-copy-tree of-matrix))

  (setq meanq (if meanq
                  (/ (+ quality (* meanq total-repeats 1.0))
                     (1+ total-repeats))
                quality))

  (let ((next-ef (modify-e-factor ef quality))
        (old-ef ef)
        (new-of (modify-of (get-optimal-factor-sm5 n ef of-matrix)
                           quality org-drill-learn-fraction))
        (interval nil))
    (when (and org-drill-adjust-intervals-for-early-and-late-repetitions-p
               delta-days (minusp delta-days))
      (setq new-of (org-drill-early-interval-factor
                    (get-optimal-factor-sm5 n ef of-matrix)
                    (inter-repetition-interval-sm5
                     last-interval n ef of-matrix)
                    delta-days)))

    (setq of-matrix
          (set-optimal-factor n next-ef of-matrix
                              (round-float new-of 3))) ; round OF to 3 d.p.

    (setq ef next-ef)

    (cond
     ;; "Failed" -- reset repetitions to 0,
     ((<= quality org-drill-failure-quality)
      (list -1 1 old-ef (1+ failures) meanq (1+ total-repeats)
            of-matrix))     ; Not clear if OF matrix is supposed to be
                                        ; preserved
     ;; For a zero-based quality of 4 or 5, don't repeat
     ;; ((and (>= quality 4)
     ;;       (not org-learn-always-reschedule))
     ;;  (list 0 (1+ n) ef failures meanq
     ;;        (1+ total-repeats) of-matrix))     ; 0 interval = unschedule
     (t
      (setq interval (inter-repetition-interval-sm5
                      last-interval n ef of-matrix))
      (if org-drill-add-random-noise-to-intervals-p
          (setq interval (* interval (org-drill-random-dispersal-factor))))
      (list interval
            (1+ n)
            ef
            failures
            meanq
            (1+ total-repeats)
            of-matrix)))))


;;; Simple8 Algorithm =========================================================


(defun org-drill-simple8-first-interval (failures)
  "Arguments:
- FAILURES: integer >= 0. The total number of times the item has
  been forgotten, ever.

Returns the optimal FIRST interval for an item which has previously been
forgotten on FAILURES occasions."
  (* 2.4849 (exp (* -0.057 failures))))


(defun org-drill-simple8-interval-factor (ease repetition)
  "Arguments:
- EASE: floating point number >= 1.2. Corresponds to `AF' in SM8 algorithm.
- REPETITION: the number of times the item has been tested.
1 is the first repetition (ie the second trial).
Returns:
The factor by which the last interval should be
multiplied to give the next interval. Corresponds to `RF' or `OF'."
  (+ 1.2 (* (- ease 1.2) (expt org-drill-learn-fraction (log repetition 2)))))


(defun org-drill-simple8-quality->ease (quality)
  "Returns the ease (`AF' in the SM8 algorithm) which corresponds
to a mean item quality of QUALITY."
  (+ (* 0.0542 (expt quality 4))
     (* -0.4848 (expt quality 3))
     (* 1.4916 (expt quality 2))
     (* -1.2403 quality)
     1.4515))


(defun determine-next-interval-simple8 (last-interval repeats quality
                                                      failures meanq totaln
                                                      &optional delta-days)
  "Arguments:
- LAST-INTERVAL -- the number of days since the item was last reviewed.
- REPEATS -- the number of times the item has been successfully reviewed
- EASE -- the 'easiness factor'
- QUALITY -- 0 to 5
- DELTA-DAYS -- how many days overdue was the item when it was reviewed.
  0 = reviewed on the scheduled day. +N = N days overdue.
  -N = reviewed N days early.

Returns the new item data, as a list of 6 values:
- NEXT-INTERVAL
- REPEATS
- EASE
- FAILURES
- AVERAGE-QUALITY
- TOTAL-REPEATS.
See the documentation for `org-drill-get-item-data' for a description of these."
  (assert (>= repeats 0))
  (assert (and (>= quality 0) (<= quality 5)))
  (assert (or (null meanq) (and (>= meanq 0) (<= meanq 5))))
  (let ((next-interval nil))
    (setf meanq (if meanq
                    (/ (+ quality (* meanq totaln 1.0)) (1+ totaln))
                  quality))
    (cond
     ((<= quality org-drill-failure-quality)
      (incf failures)
      (setf repeats 0
            next-interval -1))
     ((or (zerop repeats)
          (zerop last-interval))
      (setf next-interval (org-drill-simple8-first-interval failures))
      (incf repeats)
      (incf totaln))
     (t
      (let* ((use-n
              (if (and
                   org-drill-adjust-intervals-for-early-and-late-repetitions-p
                   (numberp delta-days) (plusp delta-days)
                   (plusp last-interval))
                  (+ repeats (min 1 (/ delta-days last-interval 1.0)))
                repeats))
             (factor (org-drill-simple8-interval-factor
                      (org-drill-simple8-quality->ease meanq) use-n))
             (next-int (* last-interval factor)))
        (when (and org-drill-adjust-intervals-for-early-and-late-repetitions-p
                   (numberp delta-days) (minusp delta-days))
          ;; The item was reviewed earlier than scheduled.
          (setf factor (org-drill-early-interval-factor
                        factor next-int (abs delta-days))
                next-int (* last-interval factor)))
        (setf next-interval next-int)
        (incf repeats)
        (incf totaln))))
    (list
     (if (and org-drill-add-random-noise-to-intervals-p
              (plusp next-interval))
         (* next-interval (org-drill-random-dispersal-factor))
       next-interval)
     repeats
     (org-drill-simple8-quality->ease meanq)
     failures
     meanq
     totaln
     )))
