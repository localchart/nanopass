(use util.match)
(use srfi-1)
(use srfi-11)

;; ---------- Core Form

(define *prim-names*
  '(vector))

(define *keywords*
  '(quote begin if set! lambda))

(define (core-form exp)
  (core-convert exp))

(define (core-convert exp)
  (if (not (pair? exp))
      (cond
        [(symbol? exp) exp]
        [(number? exp)
         `(quote ,exp)]
        [else
         (error "Bad expression" exp)])
      (match exp
        [('quote obj)
         `(quote ,obj)]
        [('begin e0 . exps)
         (if (null? exps)
             (core-convert e0)
             (let ([new-e0 (core-convert e0)]
                   [new-e1 (core-convert `(begin . ,exps))])
               `(begin ,new-e0 ,new-e1)))]
        [('if t c a)
         (let ([new-t (core-convert t)]
               [new-c (core-convert c)]
               [new-a (core-convert a)])
           `(if ,new-t ,new-c ,new-a))]
        [('set! v e)
         (cond
           [(not (symbol? v))
            (error "Bad expression" exp)]
           [else
            (let ([new-e (core-convert e)])
              `(set! ,v ,new-e))])]
        [('lambda formals . bodies)
         (if (not (and (list? formals)
                       (every symbol? formals)
                       (every (lambda (x) (not (memq x *keywords*)))
                         formals)
                       (set? formals)))
             (errorf "Bad formals ~s in ~s" formals exp)
             (let ([new-body (core-convert `(begin ,@bodies))])
               `(lambda ,formals ,new-body)))]
        [else
         (if (or (null? exp)
                 (not (list? exp))
                 (memq (car exp) *keywords*))
             (error "Bad expression" exp)
             (let ([rator (car exp)]
                   [rands (cdr exp)])
               (let ([new-rator (core-convert rator)]
                     [new-rands (core-convert-list rands)])
                 `(,new-rator . ,new-rands))))])))

(define (core-convert-list ls)
  (map core-convert ls))

;; ---------- Analyzed Form

(define (analyzed-form exp)
  (let-values ([(exp quotes poked free)
                (analyze exp '())])
    `(let ,quotes ,exp)))

(define (analyze exp env)
  (if (not (pair? exp))
      (if (memq exp env)
          (values exp '() '() (unit-set exp))
          (if (memq exp *prim-names*)
              (errorf "Primitive in non-application position ~s"
                exp)
              (errorf "Unbound variable ~s" exp)))
      (match exp
        [('quote obj)
         (if (number? obj)
             (values `(quote ,obj) '() '() '())
             (let ([var (gen-qsym)])
               (values var (list (list var exp)) '() (unit-set var))))]
        [('begin a b)
         (let-values ([(a-exp a-quotes a-poked a-free) (analyze a env)]
                      [(b-exp b-quotes b-poked b-free) (analyze b env)])
           (values `(begin ,a-exp ,b-exp)
             (append a-quotes b-quotes)
             (union a-poked b-poked)
             (union a-free b-free)))]
        [('if t c a)
         (let-values ([(t-exp t-quotes t-poked t-free) (analyze t env)]
                      [(c-exp c-quotes c-poked c-free) (analyze c env)]
                      [(a-exp a-quotes a-poked a-free) (analyze a env)])
           (values `(if ,t-exp ,c-exp ,a-exp)
             (append t-quotes c-quotes a-quotes)
             (union (union t-poked c-poked) a-poked)
             (union (union t-free c-free) a-free)))]
        [('set! v e)
         (if (not (memq v env))
             (if (memq v *prim-names*)
                 (errorf "Attempt to set! a primitive in ~s" exp)
                 (errorf "Attempt to set! a free variable in ~s"
                   exp))
             (let-values ([(e-exp e-quotes e-poked e-free) (analyze e env)])
               (values `(set! ,v ,e-exp)
                 e-quotes
                 (union (unit-set v) e-poked)
                 (union (unit-set v) e-free))))]
        [('lambda formals body)
         (let-values ([(body-exp body-quotes body-poked body-free)
                       (analyze body (append formals env))])
           (let ([poked (intersection body-poked formals)]
                 [free-poked (difference body-poked formals)]
                 [free (difference body-free formals)])
             (values `(lambda ,formals (quote (assigned . ,poked))
                        (quote (free . ,free))
                        ,body-exp)
               body-quotes
               free-poked
               free)))]
        [else
         (let ([rator (car exp)]
               [rands (cdr exp)])
           (let-values ([(rand-exps rand-quotes rand-poked rand-free)
                         (analyze-list rands env)])
             (if (and (symbol? rator)
                      (not (memq rator env))
                      (memq rator *prim-names*))
                 (values `(,rator . ,rand-exps)
                   rand-quotes rand-poked rand-free)
                 (let-values ([(rator-exp rator-quotes rator-poked rator-free)
                               (analyze rator env)])
                   (values `(,rator-exp . ,rand-exps)
                     (append rator-quotes rand-quotes)
                     (union rator-poked rand-poked)
                     (union rator-free rand-free))))))])))

(define (analyze-list ls env)
  (if (null? ls)
      (values '() '() '() '())
      (let-values ([(head-exp head-quotes head-poked head-free)
                    (analyze (car ls) env)]
                   [(tail-exps tail-quotes tail-poked tail-free)
                    (analyze-list (cdr ls) env)])
        (values (cons head-exp tail-exps)
          (append head-quotes tail-quotes)
          (union head-poked tail-poked)
          (union head-free tail-free)))))

;; ---------- Utility procedures

(define (union a b)
  (lset-union eq? a b))

(define (difference a b)
  (lset-difference eq? a b))

(define (intersection a b)
  (lset-intersection eq? a b))

(define (unit-set item)
  (list item))

(define (set? ls)
  (or (null? ls)
      (and (not (memq (car ls) (cdr ls)))
           (set? (cdr ls)))))

(define gen-qsym gensym)
