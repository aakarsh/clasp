(in-package :cscrape)

(defun maybe-remove-one-prefix-from-start (instr prefixes)
  (let ((str (string-trim '(#\newline #\space #\tab) instr)))
    (block done
      (dolist (prefix prefixes)
        (let ((pos (search prefix str)))
          (when pos
              (when (= pos 0)
                  (return-from done (string-trim '(#\newline #\space #\tab) (subseq str (length prefix))))))))
      str)))

(defun extract-function-name-from-signature (raw-sig tag)
  "* Arguments
- sig :: Function signature as string.
- tag :: the tag that provided the signature.
* Return
values function-name full-function-name simple-function
* Description
Extract the function name from the signature.  If the function name does not contain '::' then
return the (values function-name function-name T).
If the name has the form: class::name then it's a static class method 
and not a simple-function so return (values name class::name nil)"
  (declare (optimize (debug 3)) (ignore tag))
  (let* ((sig (maybe-remove-one-prefix-from-start raw-sig '("inline" "static")))
	 (tsig (string-trim '(#\newline #\space #\tab) sig))
         (first-space (position-if
                       (lambda (c) (or (char= c #\newline)
                                       (char= c #\space)
                                       (char= c #\tab)))
                       tsig))
         (open-paren (position #\( tsig :test #'char=))
         (full-function-name (string-trim '(#\newline #\space #\tab #\*) (subseq tsig first-space open-paren)))
         (colon-colon-pos (search "::" full-function-name)))
    (if colon-colon-pos
        (values (subseq full-function-name (+ 2 colon-colon-pos)) full-function-name nil)
	(values full-function-name full-function-name t))))

(defun maybe-remove-cast (str)
  (let* ((tstr (string-trim '(#\newline #\space #\tab) str))
         (close-paren (position #\( tstr :from-end t)))
    (if close-paren
        (string-trim '(#\newline #\space #\tab) (subseq tstr (1+ close-paren)))
        tstr)))
        
(defun extract-method-name-from-signature (sig)
  (declare (optimize (debug 3)))
  (let* ((tsig (maybe-remove-one-prefix-from-start sig '("virtual" "inline")))
         (first-sep (position-if
                     (lambda (c) (or (char= c #\newline)
                                     (char= c #\space)
                                     (char= c #\tab)))
                     tsig))
         (first-name-char (position-if
                           (lambda (c) (not (or (char= c #\newline)
                                                (char= c #\space)
                                                (char= c #\tab)
                                                (char= c #\*)))) ;; skip *
                           tsig
                           :start first-sep))
         (open-paren (position #\( tsig :test #'char= :start first-name-char))
         (class-method (string-trim '(#\newline #\space #\tab #\*) (subseq tsig first-name-char open-paren)))
         (colon-colon-pos (search "::" class-method)))
    (if colon-colon-pos
        (values (subseq class-method 0 colon-colon-pos)
                (subseq class-method (+ 2 colon-colon-pos)))
        (values nil class-method))))


(defun extract-function-name-from-pointer (typed-pointer tag)
  (declare (optimize debug))
  (let ((pointer-pos (position #\& typed-pointer)))
    (unless pointer-pos
      (error 'bad-pointer :pointer-text typed-pointer :tag tag))
    (let* ((just-pointer (subseq typed-pointer pointer-pos))
           (trimmed-pointer (string-trim '(#\& #\newline #\space #\tab) just-pointer))
           (str1 (maybe-remove-cast trimmed-pointer))
           (colon-colon-pos (search "::" str1 :test #'string= :from-end t)))
      (if colon-colon-pos
          (subseq trimmed-pointer (+ 2 colon-colon-pos) nil)
          trimmed-pointer))))

(defun extract-method-name-from-pointer (pointer tag)
  (extract-function-name-from-pointer pointer tag))
