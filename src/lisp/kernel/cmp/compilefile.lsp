;;;
;;;    File: compilefile.lsp
;;;

;; Copyright (c) 2014, Christian E. Schafmeister
;;
;; CLASP is free software; you can redistribute it and/or
;; modify it under the terms of the GNU Library General Public
;; License as published by the Free Software Foundation; either
;; version 2 of the License, or (at your option) any later version.
;;
;; See directory 'clasp/licenses' for full details.
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
;; THE SOFTWARE.

;; -^-


(in-package :cmp)

(defparameter *compile-verbose* nil )
(defparameter *compile-print* nil )




(defun compile-main-function (name ltv-manager-fn  )
  (cmp-log "In compile-main-function\n")
  (let ((main-fn (with-new-function (main-fn fn-env
					     :function-name name
					     :parent-env nil
					     :linkage 'llvm-sys:internal-linkage ;; 'llvm-sys:external-linkage
					     :function-type +fn-void+
					     :argument-names nil)
		   (irc-low-level-trace :up)
		   (let* ((given-name (llvm-sys:get-name main-fn)))
		     (irc-low-level-trace)
		     (cmp-log "About to add invokeLlvmFunctionVoid for ltv-manager-fn\n")
		     (irc-intrinsic "invokeLlvmFunctionVoid" ltv-manager-fn)
		     ))))
    ;;    (cmp-log-dump main-fn)
    (cmp-log "Done compile-main-function")
    main-fn
    )
  )


(defmacro with-module ((env &key module 
				 function-pass-manager 
				 source-pathname
				 source-file-info-handle
				 source-debug-namestring
				 (source-debug-offset 0)
				 (source-debug-use-lineno t)) &rest body)
  `(let ((*the-module* ,module)
         (*the-function-pass-manager* ,function-pass-manager)
         (*all-functions-for-one-compile* nil)
         (*generate-load-time-values* t)
	 (*gv-source-pathname* (jit-make-global-string-ptr ,source-pathname "source-pathname"))
	 (*gv-source-debug-namestring* (jit-make-global-string-ptr (if ,source-debug-namestring
								     ,source-debug-namestring
								     ,source-pathname) "source-debug-namestring"))
	 (*source-debug-offset* ,source-debug-offset)
	 (*source-debug-use-lineno* ,source-debug-use-lineno)
	 (*gv-source-file-info-handle* (make-gv-source-file-info-handle-in-*the-module* ,source-file-info-handle))
	 )
     (declare (special *the-function-pass-manager*))
     (with-irbuilder (,env (llvm-sys:make-irbuilder *llvm-context*))
       ,@body)))


(defun do-compilation-unit (closure &key override)
  (cond (override
	 (let* ((*active-protection* nil))
	   (do-compilation-unit closure)))
	((null *active-protection*)
	 (let* ((*active-protection* t)
		(*pending-actions* nil))
	   (unwind-protect (do-compilation-unit closure)
             (dolist (action *pending-actions*)
               (funcall action)))))
	(t
	 (funcall closure))))

(export 'do-compilation-unit)
(defmacro with-compilation-unit ((&rest options) &body body)
 `(do-compilation-unit #'(lambda () ,@body) ,@options))



#||
(defvar *compilation-messages* nil)
(defvar *compilation-warnings-p* nil)
(defvar *compilation-failures-p* nil)
         #+ecl-min (progn ,@body)
         #-ecl-min (handler-bind
                       ((error #'(lambda (c)
                                   (invoke-restart 'record-failure c)))
                        (warning #'(lambda (c)
                                     (invoke-restart 'record-warning c))))
                     ,@body))
||#



(defun describe-form (form)
  (cond
    ((and (consp form) (eq 'core:*fset (car form)))
     (let* ((name (cadr (cadr form)))
	    (is-macro (cadddr form))
	    (header (if is-macro
			"defmacro"
			"defun")))
       (bformat t ";    %s %s\n" header name)))
    (t ()))) ;; describe more forms here

(defun compile-top-level (form)
  (when *compile-print*
    (describe-form form))
  (let ((fn (compile-thunk "repl" form nil)))
    (with-ltv-function-codegen (result ltv-env)
      (irc-intrinsic "invokeTopLevelFunction" 
		     result 
		     fn 
		     (irc-renv ltv-env)
		     (jit-constant-unique-string-ptr "top-level")
                     *gv-source-file-info-handle*
		     (irc-i64-*current-source-pos-info*-filepos)
		     (irc-i32-*current-source-pos-info*-lineno)
		     (irc-i32-*current-source-pos-info*-column)
                     ))))


(defun t1progn (rest env)
  "All forms in progn at top level are top level forms"
  (dolist (form rest)
    (t1expr form env)))

(defun t1eval-when (rest env)
  (let ((situations (car rest))
	(body (cdr rest)))
    (when (or (member 'core:compile situations) (member :compile-toplevel situations))
      (cmp-log "Performing eval-when :compile-toplevel side-effects\n")
      (cmp-log "Evaluating: %s\n" body)
      (si:top-level-eval-with-env `(progn ,@body) env)
      (cmp-log "Done eval-when compile-toplevel side-effects\n"))
    (when (or (member 'core:load situations) (member :load-toplevel situations))
      (cmp-log "Compiling body due to :load-toplevel --> %s\n" body)
      ;; Each subform is a top-level form
      (dolist (subform body)
	(t1expr subform env))
      (cmp-log "Done compiling body due to :load-toplevel\n")
      )
    ))


(defun t1locally (rest env)
  (multiple-value-bind (declares code docstring specials)
      (process-declarations rest nil)
    ;; TODO: Do something with the declares!!!!!  They should be put into the environment
    (let ((new-env (core:make-value-environment-for-locally-special-entries specials env)))
      (t1progn code new-env))))

(defun t1macrolet (rest env)
  (let* ((macros (car rest))
	 (body (cdr rest))
	 (macro-env (irc-new-macrolet-environment env)))
    (mapc #'(lambda (macro-def &aux (name (car macro-def))
				 (vl (cadr macro-def))
				 (macro-body (cddr macro-def)))
	      (let* ((lambdablock (parse-macro name vl macro-body))
		     (macro-fn (eval (list 'function lambdablock))))
		(set-kind macro-fn :macro)
		(add-macro macro-env name macro-fn)))
	  macros )
    (multiple-value-bind (declares code docstring specials )
	(process-declarations body t)
      (augment-environment-with-declares macro-env declares)
      (t1progn code macro-env))))


(defun t1symbol-macrolet (rest env)
  (error "Add support for cmp:t1symbol-macrolet"))


(defun t1expr (form &optional env)
  (cmp-log "t1expr-> %s\n" form)
  (let ((head (if (atom form) form (car form))))
    (cond
      ((eq head 'cl:eval-when) (t1eval-when (cdr form) env))
      ((eq head 'cl:progn) (t1progn (cdr form) env))
      ((eq head 'cl:locally) (t1locally (cdr form) env))
      ((eq head 'cl:macrolet) (t1macrolet (cdr form) env))
      ((eq head 'cl:symbol-macrolet) (t1symbol-macrolet (cdr form) env))
      ((compiler-macro-function head env)
       (warn "Handle compiler macro functions in env for ~a" head))
#||      ((and (not (core:lexical-macro-function head env))
            (compiler-macro-function head env))
       (multiple-value-bind (expansion expanded-p)
           (compiler-macro-function head env)
         (cmp-log "COMPILE-MACROEXPANDed form[%s] expanded to [%s]\n" form expansion)
         (irc-low-level-trace)
         (t1expr expansion env)))
||#
      ((macro-function head env)
       (let ((expanded (macroexpand form env)))
	 (t1expr expanded env)))
      (t (compile-top-level form)))
    ))


(defun compile-file-t1expr (form)
  (catch 'compiler-error
    (t1expr form)))






(defun compile-form-into-module (form name)
  "This is used to generate a module from a single form - specifically
to compile prologue and epilogue code when linking modules"
  (let* ((module (create-llvm-module-for-compile-file name))
         conditions
	 (*compile-file-pathname* nil)
	 (*compile-file-truename* name)
	 (*compile-print* nil)
	 (*compile-verbose* nil)	 )
    (with-compiler-env (conditions)
      (with-module (nil :module module
			:function-pass-manager (if *use-function-pass-manager-for-compile-file* 
						   (create-function-pass-manager-for-compile-file module))
			:source-pathname (namestring name)
			)
        (let* ()
	  (with-debug-info-generator (:module *the-module*
					      :pathname *compile-file-truename*)
	    (with-load-time-value-unit (ltv-init-fn)
	      (compile-top-level form)
	      (let ((main-fn (compile-main-function name ltv-init-fn )))
		(make-boot-function-global-variable *the-module* main-fn)
		(add-main-function *the-module*)))
	    ))))
    module))



(defun cfp-output-file-default (input-file output-type &key target-backend)
  (let* ((defaults (merge-pathnames input-file *default-pathname-defaults*)))
    (when target-backend
      (setq defaults (make-pathname :host target-backend :defaults defaults)))
    (make-pathname :type (cond
			   ((eq output-type :bitcode) "bc")
			   ((eq output-type :linked-bitcode) "lbc")
			   ((eq output-type :object) "o")
			   ((eq output-type :fasl) "fasl")
			   (t (error "unsupported output-type ~a" output-type)))
		   :defaults defaults)))


;;; Copied from sbcl sb!xc:compile-file-pathname
;;;   If INPUT-FILE is a logical pathname and OUTPUT-FILE is unsupplied,
;;;   the result is a logical pathname. If INPUT-FILE is a logical
;;;   pathname, it is translated into a physical pathname as if by
;;;   calling TRANSLATE-LOGICAL-PATHNAME.
;;; So I haven't really tried to make this precisely ANSI-compatible
;;; at the level of e.g. whether it returns logical pathname or a
;;; physical pathname. Patches to make it more correct are welcome.
(defun compile-file-pathname (input-file &key (output-file nil output-file-p)
                                           (output-type :fasl)
					   type
					   target-backend
                                           &allow-other-keys)
  (when type (error "Clasp compile-file-pathname uses :output-type rather than :type"))
  (let* ((pn (if output-file-p
		 (merge-pathnames output-file (cfp-output-file-default input-file output-type :target-backend target-backend))
		 (cfp-output-file-default input-file output-type :target-backend target-backend)))
         (ext (cond
		((eq output-type :bitcode) "bc")
		((eq output-type :linked-bitcode) "lbc")
		((eq output-type :object) "o")
		((eq output-type :fasl) "fasl")
		(t (error "unsupported output-type ~a" output-type)))))
    (make-pathname :type ext :defaults pn)))



(defun cf-module-name (type pathname)
  "Create a module name from the TYPE (either :user or :kernel)
and the pathname of the source file - this will also be used as the module initialization function name"
  (string-downcase (bformat nil "___%s_%s" (string type) (pathname-name pathname))))



(defun compile-file-results (output-file conditions)
  (let (warnings-p failures-p)
    (dolist (cond conditions)
      (cond
        ((typep cond 'compiler-error)
         (setq failures-p t))
        ((typep cond 'compiler-warning)
         (setq warnings-p t))
        (t (error "Illegal condition ~a" cond))))
    (values output-file warnings-p failures-p)))



(defvar *debug-compile-file* nil)

(defun compile-file-to-module (given-input-pathname output-path &key type source-debug-namestring (source-debug-offset 0) )
  "Compile a lisp source file into an LLVM module.  type can be :kernel or :user"
  ;; TODO: Save read-table and package with unwind-protect
  (let* ((input-pathname (probe-file given-input-pathname))
	 (sin (open input-pathname :direction :input))
	 (eof-value (gensym))
	 (module (create-llvm-module-for-compile-file (namestring input-pathname)))
	 (module-name (cf-module-name type input-pathname))
	 warnings-p failure-p)
    ;; If a truename is provided then spoof the file-system to treat input-pathname
    ;; as source-truename with the given offset
    (when source-debug-namestring
      (core:source-file-info (namestring input-pathname) source-debug-namestring source-debug-offset nil))
    (when *compile-verbose*
      (bformat t "; Compiling file: %s\n" (namestring input-pathname)))
    (with-one-source-database
	(cmp-log "About to start with-compilation-unit\n")
      (let* ((*compile-file-pathname* (pathname (merge-pathnames given-input-pathname)))
	     (*compile-file-truename* (translate-logical-pathname *compile-file-pathname*)))
	(with-module (nil :module module
			  :function-pass-manager (if *use-function-pass-manager-for-compile-file* 
						     (create-function-pass-manager-for-compile-file module))
			  :source-pathname (namestring *compile-file-pathname*)
			  :source-debug-namestring source-debug-namestring
			  :source-debug-offset source-debug-offset
			  )
	  (let* ()
	    (with-debug-info-generator (:module *the-module*
						:pathname *compile-file-truename*)
	      (with-load-time-value-unit (ltv-init-fn)
		(loop
		   (let* ((core:*source-database* (core:make-source-manager))
			  (top-source-pos-info (core:input-stream-source-pos-info sin))
			  (form (read sin nil eof-value)))
		     (if (eq form eof-value)
			 (return nil)
			 (progn
			   (if cmp:*debug-compile-file* (bformat t "compile-file: %s\n" form))
			   ;; If the form contains source-pos-info then use that
			   ;; otherwise fall back to using *current-source-pos-info*
			   (let ((core:*current-source-pos-info* 
				  (core:walk-to-find-source-pos-info form top-source-pos-info)))
			     (compile-file-t1expr form))))))
		(let ((main-fn (compile-main-function output-path ltv-init-fn )))
		  (make-boot-function-global-variable *the-module* main-fn)
		  (add-main-function *the-module*)))
	      )
	    (cmp-log "About to verify the module\n")
	    (cmp-log-dump *the-module*)
	    (multiple-value-bind (found-errors error-message)
		(progn
		  (cmp-log "About to verify module prior to writing bitcode\n")
		  (llvm-sys:verify-module *the-module* 'llvm-sys:return-status-action)
		  )
	      (if found-errors
		  (progn
		    (format t "Module error: ~a~%" error-message)
		    (break "Verify module found errors"))))))))
    module))


(defun compile-file (given-input-pathname
		     &key
		       (output-file nil output-file-p)
		       (verbose *compile-verbose*)
		       (print *compile-print*)
                       (system-p nil system-p-p)
		       (external-format :default)
		       ;; If we are spoofing the source-file system to treat given-input-name
		       ;; as a part of another file then use source-truename to provide the
		       ;; truename of the file we want to mimic
		       source-debug-namestring
		       ;; This is the offset we want to spoof
		       (source-debug-offset 0)
		       ;; output-type can be (or :fasl :bitcode :object)
		       (output-type :fasl)
;;; type can be either :kernel or :user
		       (type :user)
                     &aux conditions
		       )
  "See CLHS compile-file"
  (if system-p-p (error "I don't support system-p keyword argument - use output-type"))
  (if (not output-file-p) (setq output-file (cfp-output-file-default given-input-pathname output-type)))
  (with-compiler-env (conditions)
    (let ((*compile-print* print)
	  (*compile-verbose* verbose))
      ;; Do the different kind of compile-file here
      (let* ((output-path (compile-file-pathname given-input-pathname :output-file output-file :output-type output-type ))
	     (module (compile-file-to-module given-input-pathname output-path 
					     :type type 
					     :source-debug-namestring source-debug-namestring 
					     :source-debug-offset source-debug-offset )))
	(cond
	  ((eq output-type :object)
	   (when verbose (bformat t "Writing object to %s\n" (core:coerce-to-filename output-path)))
	   (ensure-directories-exist output-path)
	   (with-open-file (fout output-path :direction :output)
	     (let ((reloc-model (cond
				  ((member :target-os-linux *features*) 'llvm-sys:reloc-model-pic-)
				  (t 'llvm-sys:reloc-model-default))))
	       (generate-obj-asm module fout :file-type 'llvm-sys:code-gen-file-type-object-file :reloc-model reloc-model))))
	  ((eq output-type :bitcode)
	   (when verbose (bformat t "Writing bitcode to %s\n" (core:coerce-to-filename output-path)))
	   (ensure-directories-exist output-path)
	   (llvm-sys:write-bitcode-to-file module (core:coerce-to-filename output-path)))
	  ((eq output-type :fasl)
	   (ensure-directories-exist output-path)
	   (let ((temp-bitcode-file (compile-file-pathname given-input-pathname :output-file output-file :output-type :bitcode)))
	     (bformat t "Writing fasl file to: %s\n" output-file)
	     (ensure-directories-exist temp-bitcode-file)
	     (llvm-sys:write-bitcode-to-file module (core:coerce-to-filename temp-bitcode-file))
	     (cmp::link-system-lto output-file :lisp-bitcode-files (list temp-bitcode-file))))
	  (t ;; fasl
	   (error "Add support to file of type: ~a" output-type)))
	(dolist (c conditions)
	  (bformat t "conditions: %s\n" c))
	(compile-file-results output-path conditions)))))

(export 'compile-file)
