;;; -*- Gerbil -*-
;;; © vyzo
;;; FFI macros

(export begin-ffi)

(defsyntax (begin-ffi stx)
  (def (namespace-def ns ids)
    (displayln ids)
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
      ;; struct is the name of the struct
      ;; members is a pair of member name and type
      ;;
      ;; Usage:
      ;; for a c struct X with members a of type t1 and b of type t2
      ;; (define-c-struct X) => create symbols X and X* referring to their
      ;;    struct and pointer to the struct
      ;; (define-c-struct X ((a . t1) (b . t2))) => apart from X and X* symbols as
      ;;    described above, ir creates X-a and X-b c lambdas to get value from a pointer type
      (define-macro (define-c-struct struct #!optional (members '()))
	(let* ((struct-str (symbol->string struct))
	       (struct-ptr (string->symbol (string-append struct-str "*"))))
	  `(begin (c-define-type ,struct (struct ,struct-str))
		  (c-define-type ,struct-ptr (pointer ,struct))

		  ;; getter and setters
		  ,@(apply append
		     (map (lambda (m)
		  	    (let* ((member-name (symbol->string (car m)))
		  		   (member-type (cdr m))
		  		   (getter-name (string-append struct-str "-" member-name)))
		  	      `((define ,(string->symbol getter-name)
		  		  (c-lambda (,struct-ptr) ,member-type
		  		       ,(string-append
		  			 "___return(___arg1->" member-name ");")))
				
		  		(define ,(string->symbol
		  			  (string-append getter-name "-set!"))
		  		  (c-lambda (,struct-ptr ,member-type) void
		  		       ,(string-append
		  			 "___arg1->" member-name " = ___arg2;" "\n"
		  			 "___return;"))))))
		  	  members))
		  
		  ;; malloc
		  (define ,(string->symbol (string-append "malloc-" struct-str))
		    (c-lambda () ,struct-ptr
		  	 ,(string-append
		  	  "struct " struct-str " *var = malloc(sizeof(struct " struct-str "));" "\n"
		  	  "if (var == NULL)" "\n"
		  	  "    ___return (NULL);" "\n"
		  	  "___return(var);")))

		  ;; malloc array
		  (define ,(string->symbol (string-append "malloc-" struct-str "-array"))
		    (c-lambda (unsigned-int32) ,struct-ptr
		  	 ,(string-append
		  	  "struct " struct-str " *arr_var=malloc(___arg1*sizeof(struct " struct-str "));" "\n"
		  	  "if (arr_var == NULL)" "\n"
		  	  "    ___return (NULL);" "\n"
		  	  "___return(arr_var);")))

		  ;; ref array
		  (define ,(string->symbol (string-append struct-str "-array-ref"))
		    (c-lambda (,struct-ptr unsigned-int32) ,struct-ptr
		  	 "___return(___arg1 + ___arg2);"))

		  ;; set! array
		  (define ,(string->symbol (string-append struct-str "-array-set!"))
		    (c-lambda (,struct-ptr unsigned-int32 ,struct-ptr) void
		  	 "*(___arg1 + ___arg2) = *___arg3; ___return;")))))))

  (def (prelude-c-decls)
    '((c-declare "#include <stdlib.h>")
      (c-declare "#include <errno.h>")
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
)
      ))

  (syntax-case stx ()
    ((_ (id ...) body ...)
     (identifier-list? #'(id ...))
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
                 macros ...
                 c-decls ...
                 nsdef ...
                 body ...
                 c-defs ...))))
       (raise-syntax-error #f "Illegal expansion context; not in module context" stx)))))