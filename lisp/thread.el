;;; thread.el --- Thread support in Emacs Lisp -*- lexical-binding: t -*-

;; Copyright (C) 2018 Free Software Foundation, Inc.

;; Author: Gemini Lasswell <gazally@runbox.com>
;; Maintainer: emacs-devel@gnu.org
;; Keywords: thread, tools

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'pcase)
(require 'subr-x)

;;;###autoload
(defun thread-handle-event (event)
  "Handle thread events, propagated by `thread-signal'.
An EVENT has the format
  (thread-event THREAD ERROR-SYMBOL DATA)"
  (interactive "e")
  (if (and (consp event)
           (eq (car event) 'thread-event)
	   (= (length event) 4))
      (let ((thread (cadr event))
            (err (cddr event)))
        (message "Error %s: %S" thread err))))

(make-obsolete 'thread-alive-p 'thread-live-p "27.1")

;;; The thread list buffer and list-threads command

(defcustom thread-list-refresh-seconds 0.5
  "Seconds between automatic refreshes of the *Threads* buffer."
  :group 'thread-list
  :type 'number
  :version "27.1")

(defvar thread-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map "s" nil)
    (define-key map "sq" #'thread-list-send-quit-signal)
    (define-key map "se" #'thread-list-send-error-signal)
    (easy-menu-define nil map ""
      '("Threads"
	["Send Quit Signal" thread-list-send-quit-signal t]
        ["Send Error Signal" thread-list-send-error-signal t]))
    map)
  "Local keymap for `thread-list-mode' buffers.")

(define-derived-mode thread-list-mode tabulated-list-mode "Thread-List"
  "Major mode for monitoring Lisp threads."
  (setq tabulated-list-format
        [("Thread Name" 15 t)
         ("Status" 10 t)
         ("Blocked On" 30 t)])
  (setq tabulated-list-sort-key (cons (car (aref tabulated-list-format 0)) nil))
  (setq tabulated-list-entries #'thread-list--get-entries)
  (tabulated-list-init-header))

;;;###autoload
(defun list-threads ()
  "Display a list of threads."
  (interactive)
  ;; Generate the Threads list buffer, and switch to it.
  (let ((buf (get-buffer-create "*Threads*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'thread-list-mode)
        (thread-list-mode)
        (run-at-time 0 nil #'thread-list--timer-func buf)))
    (switch-to-buffer buf)))
;; This command can be destructive if they don't know what they are
;; doing.  Kids, don't try this at home!
;;;###autoload (put 'list-threads 'disabled "Beware: manually canceling threads can ruin your Emacs session.")

(defun thread-list--timer-func (buffer)
  "Revert BUFFER and set a timer to do it again."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (revert-buffer))
    (run-at-time thread-list-refresh-seconds nil
                 #'thread-list--timer-func buffer)))

(defun thread-list--get-entries ()
  "Return tabulated list entries for the currently live threads."
  (let (entries)
    (dolist (thread (all-threads))
      (pcase-let ((`(,status ,blocker) (thread-list--get-status thread)))
        (push `(,thread [,(or (thread-name thread)
                              (and (eq thread main-thread) "Main")
                              (prin1-to-string thread))
                         ,status ,blocker])
              entries)))
    entries))

(defun thread-list--get-status (thread)
  "Describe the status of THREAD.
Return a list of two strings, one describing THREAD's status, the
other describing THREAD's blocker, if any."
  (cond
   ((not (thread-alive-p thread)) '("Finished" ""))
   ((eq thread (current-thread)) '("Running" ""))
   (t (if-let ((blocker (thread--blocker thread)))
          `("Blocked" ,(prin1-to-string blocker))
        '("Yielded" "")))))

(defun thread-list-send-quit-signal ()
  "Send a quit signal to the thread at point."
  (interactive)
  (thread-list--send-signal 'quit))

(defun thread-list-send-error-signal ()
  "Send an error signal to the thread at point."
  (interactive)
  (thread-list--send-signal 'error))

(defun thread-list--send-signal (signal)
  "Send the specified SIGNAL to the thread at point.
Ask for user confirmation before signaling the thread."
  (let ((thread (tabulated-list-get-id)))
    (if (and (threadp thread) (thread-alive-p thread))
        (when (y-or-n-p (format "Send %s signal to %s? " signal thread))
          (if (and (threadp thread) (thread-alive-p thread))
              (thread-signal thread signal nil)
            (message "This thread is no longer alive")))
      (message "This thread is no longer alive"))))

(provide 'thread)
;;; thread.el ends here
