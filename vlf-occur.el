;;; vlf-occur.el --- Occur-like functionality for VLF  -*- lexical-binding: t -*-

;; Copyright (C) 2014 Free Software Foundation, Inc.

;; Keywords: large files, indexing, occur
;; Author: Andrey Kotlarski <m00naticus@gmail.com>
;; URL: https://github.com/m00natic/vlfi

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;; This package provides the `vlf-occur' command which builds
;; index of search occurrences in large file just like occur.

;;; Code:

(require 'vlf)

(defvar vlf-occur-vlf-file nil "VLF file that is searched.")
(make-variable-buffer-local 'vlf-occur-vlf-file)

(defvar vlf-occur-vlf-buffer nil "VLF buffer that is scanned.")
(make-variable-buffer-local 'vlf-occur-vlf-buffer)

(defvar vlf-occur-regexp)
(make-variable-buffer-local 'vlf-occur-regexp)

(defvar vlf-occur-hexl nil "Is `hexl-mode' active?")
(make-variable-buffer-local 'vlf-occur-hexl)

(defvar vlf-occur-lines 0 "Number of lines scanned by `vlf-occur'.")
(make-variable-buffer-local 'vlf-occur-lines)

(defvar vlf-occur-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "n" 'vlf-occur-next-match)
    (define-key map "p" 'vlf-occur-prev-match)
    (define-key map "\C-m" 'vlf-occur-visit)
    (define-key map "\M-\r" 'vlf-occur-visit-new-buffer)
    (define-key map [mouse-1] 'vlf-occur-visit)
    (define-key map "o" 'vlf-occur-show)
    (define-key map [remap save-buffer] 'vlf-occur-save)
    map)
  "Keymap for command `vlf-occur-mode'.")

(define-derived-mode vlf-occur-mode special-mode "VLF[occur]"
  "Major mode for showing occur matches of VLF opened files."
  (add-hook 'write-file-functions 'vlf-occur-save nil t))

(defun vlf-occur-next-match ()
  "Move cursor to next match."
  (interactive)
  (if (eq (get-text-property (point) 'face) 'match)
      (goto-char (next-single-property-change (point) 'face)))
  (goto-char (or (text-property-any (point) (point-max) 'face 'match)
                 (text-property-any (point-min) (point)
                                    'face 'match))))

(defun vlf-occur-prev-match ()
  "Move cursor to previous match."
  (interactive)
  (if (eq (get-text-property (point) 'face) 'match)
      (goto-char (previous-single-property-change (point) 'face)))
  (while (not (eq (get-text-property (point) 'face) 'match))
    (goto-char (or (previous-single-property-change (point) 'face)
                   (point-max)))))

(defun vlf-occur-show (&optional event)
  "Visit current `vlf-occur' link in a vlf buffer but stay in the \
occur buffer.  If original VLF buffer has been killed,
open new VLF session each time.
EVENT may hold details of the invocation."
  (interactive (list last-nonmenu-event))
  (let ((occur-buffer (if event
                          (window-buffer (posn-window
                                          (event-end event)))
                        (current-buffer))))
    (vlf-occur-visit event)
    (pop-to-buffer occur-buffer)))

(defun vlf-occur-visit-new-buffer ()
  "Visit `vlf-occur' link in new vlf buffer."
  (interactive)
  (let ((current-prefix-arg t))
    (vlf-occur-visit)))

(defun vlf-occur-visit (&optional event)
  "Visit current `vlf-occur' link in a vlf buffer.
With prefix argument or if original VLF buffer has been killed,
open new VLF session.
EVENT may hold details of the invocation."
  (interactive (list last-nonmenu-event))
  (when event
    (set-buffer (window-buffer (posn-window (event-end event))))
    (goto-char (posn-point (event-end event))))
  (let* ((pos (point))
         (pos-relative (- pos (line-beginning-position) 1))
         (chunk-start (get-text-property pos 'chunk-start)))
    (if chunk-start
        (let ((chunk-end (get-text-property pos 'chunk-end))
              (file (if (file-exists-p vlf-occur-vlf-file)
                        vlf-occur-vlf-file
                      (setq vlf-occur-vlf-file
                            (read-file-name
                             (concat vlf-occur-vlf-file
                                     " doesn't exist, locate it: ")))))
              (vlf-buffer vlf-occur-vlf-buffer)
              (not-hexl (not vlf-occur-hexl))
              (occur-buffer (current-buffer))
              (match-pos (+ (get-text-property pos 'line-pos)
                            pos-relative)))
          (cond (current-prefix-arg
                 (setq vlf-buffer (vlf file t))
                 (or not-hexl (vlf-tune-hexlify))
                 (switch-to-buffer occur-buffer))
                ((not (buffer-live-p vlf-buffer))
                 (unless (catch 'found
                           (dolist (buf (buffer-list))
                             (set-buffer buf)
                             (and vlf-mode
                                  (equal file buffer-file-name)
                                  (eq (not (derived-mode-p 'hexl-mode))
                                      not-hexl)
                                  (setq vlf-buffer buf)
                                  (throw 'found t))))
                   (setq vlf-buffer (vlf file t))
                   (or not-hexl (vlf-tune-hexlify)))
                 (switch-to-buffer occur-buffer)
                 (setq vlf-occur-vlf-buffer vlf-buffer)))
          (pop-to-buffer vlf-buffer)
          (vlf-move-to-chunk chunk-start chunk-end)
          (goto-char match-pos)))))

(defun vlf-occur-other-buffer (regexp)
  "Make whole file occur style index for REGEXP branching to new buffer.
Prematurely ending indexing will still show what's found so far."
  (let ((vlf-buffer (current-buffer))
        (file buffer-file-name)
        (file-size vlf-file-size)
        (batch-size vlf-batch-size)
        (is-hexl (derived-mode-p 'hexl-mode))
        (insert-bps vlf-tune-insert-bps)
        (encode-bps vlf-tune-encode-bps)
        (hexl-bps vlf-tune-hexl-bps)
        (insert-raw-bps vlf-tune-insert-raw-bps))
    (with-temp-buffer
      (setq buffer-file-name file
            buffer-file-truename file
            buffer-undo-list t
            vlf-file-size file-size)
      (set-buffer-modified-p nil)
      (set (make-local-variable 'vlf-batch-size) batch-size)
      (when vlf-tune-enabled
        (setq vlf-tune-insert-bps insert-bps
              vlf-tune-encode-bps encode-bps)
        (if is-hexl
            (progn (setq vlf-tune-hexl-bps hexl-bps
                         vlf-tune-insert-raw-bps insert-raw-bps)
                   (vlf-tune-batch '(:hexl :raw) t))
          (vlf-tune-batch '(:insert :encode) t)))
      (vlf-mode 1)
      (if is-hexl (hexl-mode))
      (goto-char (point-min))
      (vlf-build-occur regexp vlf-buffer)
      (when vlf-tune-enabled
        (setq insert-bps vlf-tune-insert-bps
              encode-bps vlf-tune-encode-bps)
        (if is-hexl
            (setq hexl-bps vlf-tune-hexl-bps
                  insert-raw-bps vlf-tune-insert-raw-bps))))
    (when vlf-tune-enabled              ;merge back tune measurements
      (setq vlf-tune-insert-bps insert-bps
            vlf-tune-encode-bps encode-bps)
      (if is-hexl
          (setq vlf-tune-hexl-bps hexl-bps
                vlf-tune-insert-raw-bps insert-raw-bps)))))

(defun vlf-occur (regexp)
  "Make whole file occur style index for REGEXP.
Prematurely ending indexing will still show what's found so far."
  (interactive (list (read-regexp "List lines matching regexp"
                                  (if regexp-history
                                      (car regexp-history)))))
  (run-hook-with-args 'vlf-before-batch-functions 'occur)
  (if (or (buffer-modified-p)
          (< vlf-batch-size vlf-start-pos))
      (vlf-occur-other-buffer regexp)
    (let ((start-pos vlf-start-pos)
          (end-pos vlf-end-pos)
          (pos (point))
          (batch-size vlf-batch-size)
          (is-hexl (derived-mode-p 'hexl-mode)))
      (vlf-tune-batch (if (derived-mode-p 'hexl-mode)
                          '(:hexl :raw)
                        '(:insert :encode)) t)
      (vlf-with-undo-disabled
       (vlf-move-to-batch 0)
       (goto-char (point-min))
       (unwind-protect (vlf-build-occur regexp (current-buffer))
         (vlf-move-to-chunk start-pos end-pos)
         (if is-hexl (vlf-tune-hexlify))
         (goto-char pos)
         (setq vlf-batch-size batch-size)))))
  (run-hook-with-args 'vlf-after-batch-functions 'occur))

(defun vlf-build-occur (regexp vlf-buffer)
  "Build occur style index for REGEXP over VLF-BUFFER."
  (let* ((tramp-verbose (if (boundp 'tramp-verbose)
                            (min tramp-verbose 2)))
         (case-fold-search t)
         (line 1)
         (last-match-line 0)
         (last-line-pos (point-min))
         (total-matches 0)
         (match-end-pos (+ vlf-start-pos (position-bytes (point))))
         (occur-buffer (generate-new-buffer
                        (concat "*VLF-occur " (file-name-nondirectory
                                               buffer-file-name)
                                "*")))
         (line-regexp (concat "\\(?5:[\n\C-m]\\)\\|\\(?10:"
                              regexp "\\)"))
         (batch-step (min 1024 (/ vlf-batch-size 8)))
         (is-hexl (derived-mode-p 'hexl-mode))
         (end-of-file nil)
         (time (float-time))
         (tune-types (if is-hexl '(:hexl :raw)
                       '(:insert :encode)))
         (reporter (make-progress-reporter
                    (concat "Building index for " regexp "...")
                    vlf-start-pos vlf-file-size)))
    (with-current-buffer occur-buffer
      (setq buffer-undo-list t))
    (unwind-protect
        (progn
          (while (not end-of-file)
            (if (re-search-forward line-regexp nil t)
                (progn
                  (setq match-end-pos (+ vlf-start-pos
                                         (position-bytes
                                          (match-end 0))))
                  (if (match-string 5)
                      (setq line (1+ line) ; line detected
                            last-line-pos (point))
                    (let* ((chunk-start vlf-start-pos)
                           (chunk-end vlf-end-pos)
                           (line-pos (line-beginning-position))
                           (line-text (buffer-substring
                                       line-pos (line-end-position))))
                      (with-current-buffer occur-buffer
                        (unless (= line last-match-line) ;new match line
                          (insert "\n:") ; insert line number
                          (let* ((overlay-pos (1- (point)))
                                 (overlay (make-overlay
                                           overlay-pos
                                           (1+ overlay-pos))))
                            (overlay-put overlay 'before-string
                                         (propertize
                                          (number-to-string line)
                                          'face 'shadow)))
                          (insert (propertize line-text ; insert line
                                              'chunk-start chunk-start
                                              'chunk-end chunk-end
                                              'mouse-face '(highlight)
                                              'line-pos line-pos
                                              'help-echo
                                              (format "Move to line %d"
                                                      line))))
                        (setq last-match-line line
                              total-matches (1+ total-matches))
                        (let ((line-start (1+
                                           (line-beginning-position)))
                              (match-pos (match-beginning 10)))
                          (add-text-properties ; mark match
                           (+ line-start match-pos (- last-line-pos))
                           (+ line-start (match-end 10)
                              (- last-line-pos))
                           (list 'face 'match
                                 'help-echo
                                 (format "Move to match %d"
                                         total-matches))))))))
              (setq end-of-file (= vlf-end-pos vlf-file-size))
              (unless end-of-file
                (vlf-tune-batch tune-types)
                (let* ((batch-move (- vlf-end-pos batch-step))
                       (start (if (or is-hexl (< match-end-pos
                                                 batch-move))
                                  batch-move
                                match-end-pos)))
                  (vlf-move-to-chunk start (+ start
                                              vlf-batch-size) t))
                (goto-char (if (or is-hexl
                                   (<= match-end-pos vlf-start-pos))
                               (point-min)
                             (or (byte-to-position (- match-end-pos
                                                      vlf-start-pos))
                                 (point-min))))
                (setq last-match-line 0
                      last-line-pos (line-beginning-position))
                (progress-reporter-update reporter vlf-end-pos))))
          (progress-reporter-done reporter))
      (set-buffer-modified-p nil)
      (if (zerop total-matches)
          (progn (kill-buffer occur-buffer)
                 (message "No matches for \"%s\" (%f secs)"
                          regexp (- (float-time) time)))
        (let ((file buffer-file-name)
              (dir default-directory))
          (with-current-buffer occur-buffer
            (goto-char (point-min))
            (insert (propertize
                     (format "%d matches from %d lines for \"%s\" \
in file: %s" total-matches line regexp file)
                     'face 'underline))
            (set-buffer-modified-p nil)
            (forward-char 2)
            (vlf-occur-mode)
            (setq default-directory dir
                  vlf-occur-vlf-file file
                  vlf-occur-vlf-buffer vlf-buffer
                  vlf-occur-regexp regexp
                  vlf-occur-hexl is-hexl
                  vlf-occur-lines line)))
        (display-buffer occur-buffer)
        (message "Occur finished for \"%s\" (%f secs)"
                 regexp (- (float-time) time))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; save, load vlf-occur data

(defun vlf-occur-save (file)
  "Serialize `vlf-occur' results to FILE which can later be reloaded."
  (interactive (list (or buffer-file-name
                         (read-file-name "Save vlf-occur results in: "
                                         nil nil nil
                                         (concat
                                          (file-name-nondirectory
                                           vlf-occur-vlf-file)
                                          ".vlfo")))))
  (setq buffer-file-name file)
  (let ((vlf-occur-save-buffer
         (generate-new-buffer (concat "*VLF-occur-save "
                                      (file-name-nondirectory file)
                                      "*"))))
    (with-current-buffer vlf-occur-save-buffer
      (setq buffer-file-name file
            buffer-undo-list t)
      (insert ";; -*- eval: (vlf-occur-load) -*-\n"))
    (prin1 (list vlf-occur-vlf-file vlf-occur-regexp vlf-occur-hexl
                 vlf-occur-lines)
           vlf-occur-save-buffer)
    (save-excursion
      (goto-char (point-min))
      (while (zerop (forward-line))
        (let* ((pos (1+ (point)))
               (line (get-char-property (1- pos) 'before-string)))
          (if line
              (prin1 (list (string-to-number line)
                           (get-text-property pos 'chunk-start)
                           (get-text-property pos 'chunk-end)
                           (get-text-property pos 'line-pos)
                           (buffer-substring-no-properties
                            pos (line-end-position)))
                     vlf-occur-save-buffer)))))
    (with-current-buffer vlf-occur-save-buffer
      (save-buffer))
    (kill-buffer vlf-occur-save-buffer))
  t)

;;;###autoload
(defun vlf-occur-load ()
  "Load serialized `vlf-occur' results from current buffer."
  (interactive)
  (goto-char (point-min))
  (let* ((vlf-occur-data-buffer (current-buffer))
         (header (read vlf-occur-data-buffer))
         (vlf-file (nth 0 header))
         (regexp (nth 1 header))
         (all-lines (nth 3 header))
         (file buffer-file-name)
         (vlf-occur-buffer
          (generate-new-buffer (concat "*VLF-occur "
                                       (file-name-nondirectory file)
                                       "*"))))
    (switch-to-buffer vlf-occur-buffer)
    (setq buffer-file-name file
          buffer-undo-list t)
    (goto-char (point-min))
    (let ((match-count 0)
          (form 0))
      (while (setq form (ignore-errors (read vlf-occur-data-buffer)))
        (goto-char (point-max))
        (insert "\n:")
        (let* ((overlay-pos (1- (point)))
               (overlay (make-overlay overlay-pos (1+ overlay-pos)))
               (line (number-to-string (nth 0 form)))
               (pos (point)))
          (overlay-put overlay 'before-string
                       (propertize line 'face 'shadow))
          (insert (propertize (nth 4 form) 'chunk-start (nth 1 form)
                              'chunk-end (nth 2 form)
                              'mouse-face '(highlight)
                              'line-pos (nth 3 form)
                              'help-echo (concat "Move to line "
                                                 line)))
          (goto-char pos)
          (while (re-search-forward regexp nil t)
            (add-text-properties
             (match-beginning 0) (match-end 0)
             (list 'face 'match 'help-echo
                   (format "Move to match %d"
                           (setq match-count (1+ match-count))))))))
      (kill-buffer vlf-occur-data-buffer)
      (goto-char (point-min))
      (insert (propertize
               (format "%d matches from %d lines for \"%s\" in file: %s"
                       match-count all-lines regexp vlf-file)
               'face 'underline)))
    (set-buffer-modified-p nil)
    (vlf-occur-mode)
    (setq vlf-occur-vlf-file vlf-file
          vlf-occur-regexp regexp
          vlf-occur-hexl (nth 2 header)
          vlf-occur-lines all-lines)))

(provide 'vlf-occur)

;;; vlf-occur.el ends here
