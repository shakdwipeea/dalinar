;;; -*- Gerbil -*-
;;; © vyzo
;;; FFI macros
(import (for-syntax :std/stxutil))

(export begin-ffi)

(defsyntax (begin-ffi stx)
  (def (make-struct-ids name fields)
    (append (list (format-id name "malloc-~a" name)
		  (format-id name "malloc-~a-array" name)
		  (format-id name "~a-array-ref" name)
		  (format-id name "~a-array-set!" name)
		  (format-id name "ptr->~a" name)
		  (format-id name "~a-ptr?" name))
	    (apply append
	     (map (lambda (field) (list (format-id name "~a-~a" name field)
				   (format-id name "~a-~a-set!" name field)))
		  fields))))
  
  (def (namespace-def ns ids)

    (if (null? ids) []
	(with-syntax ((prefix (string-append (if (symbol? ns) (symbol->string ns) ns) "#"))
		      ((id ...) ids))
	  [#'(namespace (prefix id ...))])))

  (def (prelude-macros)
    '((define-macro (define-guard guard defn)
        (if (eval `(cond-expand (,guard #t) (else #f)))
          '(begin)
          (begin
            (eval `(define-cond-expand-feature ,guard))
            defn)))
      (define-macro (define-c-lambda id args ret #!optional (name #f))
        (let ((name (or name (symbol->string id))))
          `(define ,id
             (c-lambda ,args ,ret ,name))))
      (define-macro (define-const symbol)
        (let* ((str (symbol->string symbol))
               (ref (string-append "___return (" str ");")))
          `(define ,symbol
             ((c-lambda () int ,ref)))))
      (define-macro (define-const* symbol)
        (let* ((str (symbol->string symbol))
               (code (string-append
                      "#ifdef " str "\n"
                      "___return (___FIX (" str "));\n"
                      "#else \n"
                      "___return (___FAL);\n"
                      "#endif")))
          `(define ,symbol
             ((c-lambda () scheme-object ,code)))))
      (define-macro (define-with-errno symbol ffi-symbol args)
        `(define (,symbol ,@args)
           (declare (not interrupts-enabled))
           (let ((r (,ffi-symbol ,@args)))
             (if (##fx< r 0)
               (##fx- (##c-code "___RESULT = ___FIX (errno);"))
               r))))
      ;; Definitions:
      ;; struct => is the name of the struct
      ;; members => is a pair of member name and type
      ;; release-function => this is the cleanup function called by the gc.
      ;;    If no cleanup function is provided, a c function is created <struct-name>_ffi_free
      ;;    this function frees the struct pointer as well as any string members if
      ;;    they were set.
      ;;
      ;; Usage:
      ;; for a c struct X with members a of type t1 and b of type t2
      ;; (define-c-struct X) =>
      ;;
      ;; -- Types created
      ;; - X for struct
      ;; - X* for the pointer to the struct. this is the struct to which the configurable
      ;;      release function is provided
      ;; - X-ptr* similar to X*, default release function ffi_free is associated
      ;; - X-ptr-2* similat to X* but no release function
      ;;
      ;; -- Lambdas created
      ;; - X-ptr? predicate for the struct types (uses foreign-tags)
      ;; - malloc-X calls malloc for the struct and returns a pointer to it
      ;; - ptr->X get the value of X from its pointer
      ;; - (malloc-X-array N) calls malloc for N * sizeof X and returns a pointer to it, the
      ;;      returned pointer is of type X-ptr*
      ;; - (X-array-ref ptr i) returns a pointer with offset i starting at ptr, the returned
      ;;      pointer is of type X-ptr-2*
      ;; - (X-array-set! ptr i val-ptr) sets the value of the pointer at offset i from ptr to
      ;;      be val-ptr
      ;;
      ;;
      ;; (define-c-struct X ((a . t1) (b . t2))) =>
      ;; In addition to the types and lambdas defined above, following additional lambdas are provided:
      ;;
      ;; - X-a-set!, X-b-set! setter for member variables.
      ;;   Special compatibility for string types is provided, i.e. when t1 | t2 = char-string
      ;;   if a string is passed as the value, then we strdup the string and set that to the
      ;;   argument. If the struct member is already pointing to another string, then that
      ;;   string is freed and the member will now point to a new string.
      ;;   The cleanup of such strings are handled by the generated <struct>_ffi_free, if
      ;;   a custom release function is provided, care should be taken while freeing
      ;;
      ;;- X-a X-b accessor functions for struct members
      (define-macro (define-c-struct struct #!optional (members '()) release-function)
	(let* ((struct-str (symbol->string struct))
	       (struct-ptr (string->symbol (string-append struct-str "*")))
	       (shallow-ptr (string->symbol (string-append struct-str "-ptr*")))
	       (borrowed-ptr (string->symbol (string-append struct-str "-ptr2*")))
	       (string-setter-body (lambda (member-name)
				     (let ((m (string-append "___arg1->" member-name)))
				       (string-append
					"if(" m " == NULL)" "\n"
					m "= strdup(___arg2);" "\n"
					"else if (strcmp(" m ", ___arg2) != 0) {" "\n"
					"free(" m ");" "\n"
					m "= strdup(___arg2);" "\n"
					"}" "\n"
					"___return;" "\n"))))
	       (default-free-body (string-append
				   "___SCMOBJ " struct-str "_ffi_free (void *ptr) {" "\n"
				   "struct " struct-str " *obj = (struct " struct-str "*) ptr;" "\n"
				   (apply string-append
				     (map (lambda (m)
					    (case (cdr m)
					      ((char-string)
					       (let ((mem-name (symbol->string (car m))))
						 (string-append "if(obj->" mem-name ") " 
								"free(obj->" mem-name ");" "\n")))
					      (else "")))
					  members))
				   "free(obj);" "\n"
				   "return ___FIX (___NO_ERR);" "\n"
				   "}"
				   ))
	       (release-function (or release-function (string-append struct-str "_ffi_free"))))
	  `(begin (c-declare ,default-free-body)
		  (c-define-type ,struct (struct ,struct-str))
		  (c-define-type ,struct-ptr (pointer ,struct (,struct-ptr) ,release-function))
		  (c-define-type ,shallow-ptr (pointer ,struct (,struct-ptr) "ffi_free"))
		  (c-define-type ,borrowed-ptr (pointer ,struct (,struct-ptr)))

		  (define ,(string->symbol (string-append struct-str "-ptr?"))
		    (lambda (obj)
		      (and (foreign? obj)
		  	 (equal? (foreign-tags obj) (quote (,struct-ptr))))))

		  ;; getter and setters
		  ,@(apply append
		     (map (lambda (m)
		  	    (let* ((member-name (symbol->string (car m)))
		  		   (member-type (cdr m))
		  		   (getter-name (string-append struct-str "-" member-name))
		  		   (setter-body (case member-type
		  				  ((char-string)
		  				   (string-setter-body member-name))
		  				  (else
		  				   (string-append
		  				    "___arg1->" member-name " = ___arg2;" "\n"
		  				    "___return;" "\n")))))
		  	      `((define ,(string->symbol getter-name)
		  		  (c-lambda (,struct-ptr) ,member-type
		  		       ,(string-append
		  			 "___return(___arg1->" member-name ");")))
				
		  		(define ,(string->symbol (string-append getter-name "-set!"))
		  		  (c-lambda (,struct-ptr ,member-type) void
		  			    ,setter-body)))))
		  	  members))
		  
		  ;; malloc
		  (define ,(string->symbol (string-append "malloc-" struct-str))
		    (c-lambda () ,struct-ptr
		  	 ,(string-append
		  	   "struct " struct-str "* var = malloc(sizeof(struct " struct-str "));" "\n"
			   "memset(var, 0, sizeof(struct " struct-str "));"
		  	  "if (var == NULL)" "\n"
		  	  "    ___return (NULL);" "\n"
		  	  "___return(var);")))

		  (define ,(string->symbol (string-append "ptr->" struct-str))
		    (c-lambda (,struct-ptr) ,struct
			 "___return(*___arg1);"))

		  ;; malloc array
		  (define ,(string->symbol (string-append "malloc-" struct-str "-array"))
		    
		    (c-lambda (unsigned-int32) ,shallow-ptr
		  	 ,(string-append
		  	   "struct " struct-str " *arr_var=malloc(___arg1*sizeof(struct " struct-str "));" "\n"

		  	  "if (arr_var == NULL)" "\n"
		  	  "    ___return (NULL);" "\n"
		  	  "___return(arr_var);")))

		  ;; ref array
		  (define ,(string->symbol (string-append struct-str "-array-ref"))
		    (c-lambda (,struct-ptr unsigned-int32) ,borrowed-ptr
		  	 "___return (___arg1 + ___arg2);"))

		  ;; set! array
		  (define ,(string->symbol (string-append struct-str "-array-set!"))
		    (c-lambda (,struct-ptr unsigned-int32 ,struct-ptr) void
		  	 "*(___arg1 + ___arg2) = *___arg3; ___return;")))))))

  (def (prelude-c-decls)
    '((c-declare "#include <stdlib.h>")
      (c-declare "#include <errno.h>")
      (c-declare "#include <string.h>")
      (c-declare "static ___SCMOBJ ffi_free (void *ptr);")
      (c-declare #<<END-C
#ifndef ___HAVE_FFI_U8VECTOR
#define ___HAVE_FFI_U8VECTOR
#define U8_DATA(obj) ___CAST (___U8*, ___BODY_AS (obj, ___tSUBTYPED))
#define U8_LEN(obj) ___HD_BYTES (___HEADER (obj))
#endif
END-C
)
      ))

  (def (prelude-c-defs)
    '((c-declare #<<END-C
#ifndef ___HAVE_FFI_FREE
#define ___HAVE_FFI_FREE
___SCMOBJ ffi_free (void *ptr)
{
 free (ptr);
 return ___FIX (___NO_ERR);
}
#endif
END-C
)))

  (syntax-case stx ()
    ((_  (exts ...) body ...)
     (with-syntax (((id ...)
     		    (let lp ((rest #'(exts ...))
			     (ids []))
		      (syntax-case rest (struct)
			((id . rest)
			 (identifier? #'id)
			 (lp #'rest (cons #'id ids)))

			(((struct name fields ...) . rest)
			 (lp (syntax rest)
			     (foldl cons ids (make-struct-ids #'name
							      #'(fields ...)))))
			
			(() ids)))))
       (if (module-context? (current-expander-context))
	 (let (ns (or (module-context-ns (current-expander-context))
		      (expander-context-id (current-expander-context))))
	   (with-syntax (((nsdef ...) (namespace-def ns #'(id ...)))
			 ((macros ...) (prelude-macros))
			 ((c-decls ...) (prelude-c-decls))
			 ((c-defs ...) (prelude-c-defs)))
	     #'(begin
		 (extern id ...)
		 (begin-foreign
		   c-decls ...
		   macros ...
		   nsdef ...
		   body ...
		   c-defs ...))))
	 (raise-syntax-error #f "Illegal expansion context; not in module context" stx))))))