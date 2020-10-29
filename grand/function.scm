(define-module (grand function)
  #:use-module (grand examples)
  #:use-module (grand syntax)
  #:use-module (srfi srfi-1)
  #:export (impose-arity
	    arity
	    name/source
	    clip
	    pass
	    compose/values
	    iterations
	    partial
	    maybe
	    either
	    neither
	    both
	    is
	    isnt))

(use-modules (grand examples) (grand syntax) (srfi srfi-1))

(define (impose-arity n procedure)
  (let ((new-procedure (lambda args (apply procedure args))))
    (set-procedure-property! new-procedure 'name
			     (or (procedure-name procedure)
				 'fixed-arity))
    (set-procedure-property! new-procedure 'imposed-arity
			     (if (list? n) n `(,n 0 #f)))
    new-procedure))

(define (name/source procedure)
  (or (procedure-name procedure)
      (procedure-source procedure)))

(define (arity procedure)
  ;;(assert (procedure? procedure))
  (or (procedure-property procedure 'imposed-arity)
      (procedure-property procedure 'arity)))

(define (clip args #;to arity)
  (match arity
    ((min _ #f)
     (take args min))
    ((? number?)
     (take args arity))
    (_
     args)))

(define (compose/values . fns)
  (define (make-chain chains fn)
    (impose-arity
     (arity fn)
     (lambda args
       (call-with-values 
	   (lambda () (apply fn args))
	 (lambda vals (apply chains (clip vals (arity chains))))))))
  (let ((composer (fold-right make-chain values fns)))
    composer))

(define (iterations n f)
  (apply compose/values (make-list n f)))

(e.g.
 ((iterations 3 1+) 0)
 ===> 3)

(define (pass object #;to . functions)
  ((apply compose/values (reverse functions)) object))

(e.g. (pass 5 #;to 1- #;to sqrt) ===> 2)

(define ((partial function . args) . remaining-args)
  (apply function `(,@args ,@remaining-args)))

#;(assert (lambda (f x)
(if (defined? (f x))
    (equal? (f x) ((partial f) x)))))

(define ((maybe pred) x)
  (or (not x)
      (pred x)))

(e.g.
 (and ((maybe number?) 5)
      ((maybe number?) #f)))

(define ((either . preds) x)
  (any (lambda (pred)
	 (pred x))
       preds))

(define ((neither . preds) x)
  (not ((apply either preds) x)))

(e.g.
 (and ((either number? symbol?) 5)
      ((either number? symbol?) 'x)
      ((neither number? symbol?) "abc")))

(define ((both . preds) x)
  (every (lambda (pred)
	   (pred x))
	 preds))

(e.g.
 (and ((both positive? integer?) 5)
      (not ((both positive? integer?) 4.5))))


(define-syntax infix/postfix ()
  
  ((infix/postfix x somewhat?)
   (somewhat? x))

  ((infix/postfix left related-to? right)
   (related-to? left right))

  ((infix/postfix left related-to? right . likewise)
   (let ((right* right))
     (and (infix/postfix left related-to? right*)
	  (infix/postfix right* . likewise)))))

(define-syntax extract-_ (_ is isnt quote
			    quasiquote unquote
			    unquote-splicing)
  ;; ok, it's a bit rough, so it requires an explanation.
  ;; the macro operates on sequences of triples
  ;;
  ;;   (<remaining-expr> <arg-list> <processed-expr>) +
  ;;
  ;; where <remaining-expr> is being systematically
  ;; rewritten to <processed-expr>. When the _ symbol
  ;; is encountered, it is replaced with a fresh "arg"
  ;; symbol, which is appended to both <arg-list>
  ;; and <processed-expr>.
  ;;
  ;; The goal is to create a lambda where each
  ;; consecutive _ is treated as a new argument
  ;; -- unless there are no _s: then we do not
  ;; create a lambda, but a plain expression.
  ;;
  ;; The nested "is" and "isnt" operators are treated
  ;; specially, in that the _s within those operators are
  ;; not extracted.
  ;;
  ;; Similarly, the _ isn't extracted from quoted forms,
  ;; and is only extracted from quasi-quoted forms if
  ;; it appears on unquoted positions.

  ;; The support for quasiquote modifies the tuples
  ;; to have the form
  ;;
  ;;   (<remaining-expr> <arg-list> <processed-expr> . qq*) +
  ;;
  ;; where qq* is a sequence of objects that expresses
  ;; the nesting level of the 'quasiquote' operator
  ;; (i.e. quasiquote inside quasiquote etc.)

  ;; The macro consists of the following cases:
  
  ;; final case with no _s
  ((extract-_ final (() () body))
   (final (infix/postfix . body)))

  ;; final case with some _s -- generate a lambda
  ((extract-_ final (() args body))
   (lambda args (final (infix/postfix . body))))

  ;; treat 'is' and 'isnt' operators specially and
  ;; don't touch their _s
  ((extract-_ final (((is . t) . rest) args (body ...)) . *)
   (extract-_ final (rest args (body ... (is . t))) . *))

  ((extract-_ final (((isnt . t) . rest) args (body ...)) . *)
   (extract-_ final (rest args (body ... (isnt . t))) . *))

  ;; same with 'quote'
  ((extract-_ final (('literal . rest) args (body ...)) . *)
   (extract-_ final (rest args (body ... 'literal)) . *))

  ;; when 'quasiquote' is encountered, we increase the
  ;; level of quasiquotation (the length of the qq* sequence)
  ((extract-_ final
	      (((quasiquote x) . rest) args body . qq*) . *)
   (extract-_ final
	      ((x) () (quasiquote) qq . qq*)
	      (rest args body) . *))

  ;; on the other hand, for 'unquote' and
  ;; 'unquote-splicing', we decrease the nesting level
  ;; (i.e. we consume one element from the qq* sequence)
  ((extract-_ final
	      (((unquote x) . rest) args body qq . qq*) . *)
   (extract-_ final
	      ((x) () (unquote) . qq*)
	      (rest args body qq . qq*) . *))

  ((extract-_ final
	      (((unquote-splicing x) . rest) args body
	       qq . qq*) . *)
   (extract-_ final
	      ((x) () (unquote-splicing) . qq*)
	      (rest args body qq . qq*) . *))

  ;; push/unnest nested expression for processing
  ((extract-_ final (((h . t) . rest) args body . qq) . *)
   (extract-_ final ((h . t) () () . qq)
	      (rest args body . qq) . *))

  ;; unquote in the tail position
  ((extract-_ final
	      ((unquote x) args (body ...) qq . qq*) . *)
   (extract-_ final
	      ((x) args (body ... unquote) . qq*) . *))
  
  ;; generate a new arg for the _ in the head position
  ((extract-_ final ((_ . rest) (args ...) (body ...)) . *)
   (extract-_ final (rest (args ... arg) (body ... arg)) . *))

  ;; rewrite the term in the head position to the back
  ;; of the processed terms
  ((extract-_ final ((term . rest) args (body ...) . qq) . *)
   (extract-_ final (rest args (body ... term) . qq) . *))

  ;; _ in the tail position
  ((extract-_ final
	      (_ (args ...) (body ...) . qq)
	      (rest (args+ ...) (body+ ...) . qq+) . *)
   (extract-_ final
	      (rest (args+ ... args ... arg)
		    (body+ ... (body ... . arg)) . qq+) . *))

  ;; pop/nest back processed expression
  ;; ('last' is an atom; most likely (), but can also
  ;; be some value, e.g. in the case of assoc list literals)
  ((extract-_ final
	      (last (args ...) (body ...) . qq)
	      (rest (args+ ...) (body+ ...) . qq+) . *)
   (extract-_ final
	      (rest (args+ ... args ...)
		    (body+ ... (body ... . last)) . qq+) . *))
  )

(define-syntax (identity-syntax form)
  form)

(define-syntax (is . something)
  (extract-_ identity-syntax (something () ())))

(define-syntax (isnt . something)
  (extract-_ not (something () ())))

(e.g.
 (is 2 < 3))

(e.g.
 (is 1 < 2 = (+ 1 1) <= 3 odd?))

(e.g.
 (filter (is 5 < _ <= 10) '(1 3 5 7 9 11))
 ===> (7 9))

(e.g.
 (let ((<* (is (length _) < (length _))))
   (is '(1 2 3) <* '(1 2 3 4))))

(e.g.
 ((is (length (filter (is (modulo _ 2) = 0) _)) < 5)
  '(1 2 3 4 5 6 7 8 9)))

(e.g.
 (is 2 even?))

(e.g.
 (isnt 2 odd?))

(e.g.
 (every (is (+ _ _) even?) '(1 2 3 4) '(5 6 7 8)))

(e.g.
 ((is 2 _ 3) <))

(e.g.
 ((isnt 2 _ 3) >=))

(e.g.
 ((is _ _ _) 2 < 3))

(e.g.
 ((is (expt _ 2) _ (expt _ 2) _ (expt _ 2)) 2 <= -2 < -3))

(e.g. ;; a bit contrived, but shows handling of quotations
 ((is '(_ _) list `(_ ,_ ,@(_ _) `,,_ ,'_)) 5 values '(6 7) 'X)
 ===> ((_ _) (_ 5 6 7 `,X _)))

(e.g. ;; handling improper lists
 (is '(x . y) member '((a . b) (p . q) (x . y))))

(e.g.
 ((is `(p . ,_) member `((a . b) (,_ . q) (x . y)))
  'q 'p))
