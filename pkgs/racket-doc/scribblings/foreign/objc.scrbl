#lang scribble/doc
@(require scribble/manual
          scribble/eval
          (for-label racket/base
                     racket/contract
                     ffi/unsafe/objc
                     (except-in ffi/unsafe ->)
                     (only-in ffi/objc objc-unsafe!)
                     (only-in scheme/foreign unsafe!)))

@(define objc-eval (make-base-eval))
@(interaction-eval #:eval objc-eval (define-struct cpointer:id ()))

@(define seeCtype
   @elem{see @secref["ctype"]})

@title{Objective-C FFI}

@defmodule[ffi/unsafe/objc]{The
@racketmodname[ffi/unsafe/objc] library builds on
@racketmodname[ffi/unsafe] to support interaction with
@link["http://developer.apple.com/documentation/Cocoa/Conceptual/ObjectiveC/"]{Objective-C}.}

The library supports Objective-C interaction in two layers. The upper
layer provides syntactic forms for sending messages and deriving
subclasses. The lower layer is a thin wrapper on the
@link["https://developer.apple.com/documentation/objectivec"]{Objective-C
runtime library} functions. Even the upper layer is unsafe and
relatively low-level compared to normal Racket libraries, because
argument and result types must be declared in terms of FFI C types
(@seeCtype).

@; ----------------------------------------------------------------------

@section{FFI Types and Constants}

@defthing[_id ctype?]{

The type of an Objective-C object, an opaque pointer.}

@defthing[_Class ctype?]{

The type of an Objective-C class, which is also an @racket[_id].}

@defthing[_Protocol ctype?]{

The type of an Objective-C protocol, which is also an @racket[_id].}

@defthing[_SEL ctype?]{

The type of an Objective-C selector, an opaque pointer.}

@defthing[_BOOL ctype?]{

The Objective-C boolean type. Racket values are converted for C in the
usual way: @racket[#f] is false and any other value is true. C values
are converted to Racket booleans.}

@defthing[YES boolean?]{

Synonym for @racket[#t]}

@defthing[NO boolean?]{

Synonym for @racket[#f]}

@; ----------------------------------------------------------------------

@section{Syntactic Forms and Procedures}

@defform*/subs[[(tell result-type obj-expr method-id)
                (tell result-type obj-expr arg ...)]
               ([result-type code:blank
                             (code:line #:type ctype-expr)]
                [arg (code:line method-id arg-expr)
                     (code:line method-id #:type ctype-expr arg-expr)])]{

Sends a message to the Objective-C object produced by
@racket[obj-expr]. When a type is omitted for either the result or an
argument, the type is assumed to be @racket[_id], otherwise it must
be specified as an FFI C type (@seeCtype).

If a single @racket[method-id] is provided with no arguments, then
@racket[method-id] must not end with @litchar{:}; otherwise, each
@racket[method-id] must end with @litchar{:}.

@examples[
#:eval objc-eval
(eval:alts (tell NSString alloc) (make-cpointer:id))
(eval:alts (tell (tell NSString alloc)
                 initWithUTF8String: #:type _string "Hello")
           (make-cpointer:id))
]}

@defform*[[(tellv obj-expr method-id)
           (tellv obj-expr arg ...)]]{

Like @racket[tell], but with a result type @racket[_void].}

@defform[(import-class class-id ...)]{

Defines each @racket[class-id] to the class (a value with FFI type
@racket[_Class]) that is registered with the string form of
@racket[class-id]. The registered class is obtained via
@racket[objc_lookUpClass].

@examples[
#:eval objc-eval
(eval:alts (import-class NSString) (void))
]

A class accessed by @racket[import-class] is normally declared as a
side effect of loading a foreign library. For example, if you want to
import the class @tt{NSString} on Mac OS, the @filepath{Foundation}
framework must be loaded, first. Beware that if you use
@racket[import-class] in DrRacket or a module that @racket[require]s
@racketmodname[racket/gui/base], then @filepath{Foundation} will have
been loaded into the Racket process already. To avoid relying on other
libraries to load @filepath{Foundation}, explicitly load it with
@racket[ffi-lib]:

@interaction[
#:eval objc-eval
(eval:alts (ffi-lib
            "/System/Library/Frameworks/Foundation.framework/Foundation") (void))
(eval:alts (import-class NSString) (void))
]}

@defform[(import-protocol protocol-id ...)]{

Defines each @racket[protocol-id] to the protocol (a value with FFI type
@racket[_Protocol]) that is registered with the string form of
@racket[protocol-id]. The registered class is obtained via
@racket[objc_getProtocol].

@examples[
#:eval objc-eval
(eval:alts (import-protocol NSCoding) (void))
]}

@defform/subs[#:literals (+ - +a -a)
              (define-objc-class class-id superclass-expr
                maybe-mixins
                maybe-protocols
                [field-id ...]
                method ...)
              ([maybe-mixins code:blank
                             (code:line #:mixins (mixin-expr ...))]
               [maybe-protocols code:blank
                                (code:line #:protocols (protocol-expr ...))]
               [method (mode maybe-async result-ctype-expr (method-id) body ...+)
                       (mode maybe-async result-ctype-expr (arg ...+) body ...+)]
               [mode + - +a -a]
               [maybe-async code:blank
                            (code:line #:async-apply async-apply-expr)]
               [arg (code:line method-id [ctype-expr arg-id])])]{

Defines @racket[class-id] as a new, registered Objective-C class (of
FFI type @racket[_Class]). The @racket[superclass-expr] should produce
an Objective-C class or @racket[#f] for the superclass. An optional
@racket[#:mixins] clause can specify mixins defined with
@racket[define-objc-mixin]. An optional @racket[#:protocols] clause
can specify Objective-C protocols to be implemented by the class, where
a @racket[#f] result for a @racket[protocol-expr] is ignored.

Each @racket[field-id] is an instance field that holds a Racket value
and that is initialized to @racket[#f] when the object is
allocated. The @racket[field-id]s can be referenced and @racket[set!]
directly when the method @racket[body]s. Outside the object, they can
be referenced and set with @racket[get-ivar] and @racket[set-ivar!].

Each @racket[method] adds or overrides a method to the class (when
@racket[mode] is @racket[-] or @racket[-a]) to be called on instances,
or it adds a method to the meta-class (when @racket[mode] is
@racket[+] or @racket[+a]) to be called on the class itself. All
result and argument types must be declared using FFI C types
(@seeCtype). When @racket[mode] is @racket[+a] or @racket[-a], the
method is called in atomic mode (see @racket[_cprocedure]).
An optional @racket[#:async-apply] specification determines how
the method works when called from a foreign thread in the
same way as for @racket[_cprocedure].

If a @racket[method] is declared with a single @racket[method-id] and
no arguments, then @racket[method-id] must not end with
@litchar{:}. Otherwise, each @racket[method-id] must end with
@litchar{:}.

If the special method @racket[dealloc] is declared for mode
@racket[-], it must not call the superclass method, because a
@racket[(super-tell dealloc)] is added to the end of the method
automatically. In addition, before @racket[(super-tell dealloc)],
space for each @racket[field-id] within the instance is deallocated.

@examples[
#:eval objc-eval
(eval:alts
 (define-objc-class MyView NSView
   [bm] (code:comment @#,elem{<- one field})
   (- _racket (swapBitwmap: [_racket new-bm])
      (begin0 bm (set! bm new-bm)))
   (- _void (drawRect: [@#,racketidfont{_NSRect} exposed-rect])
      (super-tell drawRect: exposed-rect)
      (draw-bitmap-region bm exposed-rect))
   (- _void (dealloc)
      (when bm (done-with-bm bm))))
 (void))
]

@history[#:changed "6.90.0.26" @elem{Changed @racket[#:protocols] handling to
                                     ignore @racket[#f] expression results.}]}

@defform[(define-objc-mixin (class-id superclass-id)
           maybe-mixins
           maybe-protocols
           [field-id ...]
           method ...)]{

Like @racket[define-objc-class], but defines a mixin to be combined
with other method definitions through either
@racket[define-objc-class] or @racket[define-objc-mixin]. The
specified @racket[field-id]s are not added by the mixin, but must be a
subset of the @racket[field-id]s declared for the class to which the
methods are added.}


@defidform[self]{

When used within the body of a @racket[define-objc-class] or
@racket[define-objc-mixin] method, refers to the object whose method
was called. This form cannot be used outside of a
@racket[define-objc-class] or @racket[define-objc-mixin] method.}

@defform*[[(super-tell result-type method-id)
           (super-tell result-type arg ...)]]{

When used within the body of a @racket[define-objc-class] or
@racket[define-objc-mixin] method, calls a superclass method. The
@racket[result-type] and @racket[arg] sub-forms have the same syntax
as in @racket[tell]. This form cannot be used outside of a
@racket[define-objc-class] or @racket[define-objc-mixin] method.}


@defform[(get-ivar obj-expr field-id)]{

Extracts the Racket value of a field in a class created with
@racket[define-objc-class].}

@defform[(set-ivar! obj-expr field-id value-expr)]{

Sets the Racket value of a field in a class created with
@racket[define-objc-class].}

@defform[(selector method-id)]{

Returns a selector (of FFI type @racket[_SEL]) for the string form of
@racket[method-id].

@examples[
(eval:alts (tellv button setAction: #:type _SEL (selector terminate:)) (void))
]}

@defproc[(objc-is-a? [obj _id] [cls _Class]) boolean?]{

Check whether @racket[obj] is an instance of the Objective-C class
@racket[cls] or a subclass.

@history[#:changed "6.1.0.5" @elem{Recognize subclasses, instead of requiring an
                                   exact class match.}]}

@defproc[(objc-subclass? [subcls _Class] [cls _Class]) boolean?]{

Check whether @racket[subcls] is @racket[cls] or a subclass.

@history[#:added "6.1.0.5"]}


@defproc[(objc-get-class [obj _id]) _Class]{

Extract the class of @racket[obj].

@history[#:added "6.3"]}


@defproc[(objc-set-class! [obj _id] [cls _Class]) void?]{

Changes the class of @racket[obj] to @racket[cls]. The object's
existing representation must be compatible with the new class.

@history[#:added "6.3"]}


@defproc[(objc-get-superclass [cls _Class]) _Class]{

Returns the superclass of @racket[cls].

@history[#:added "6.3"]}


@defproc[(objc-dispose-class [cls _Class]) void?]{

Destroys @racket[cls], which must have no existing instances or
subclasses.

@history[#:added "6.3"]}


@defproc[(objc-block [function-type? ctype]
                     [proc procedure?]
                     [#:keep keep (box/c list?)])
         cpointer?]{

Wraps a Racket function @racket[proc] as an Objective-C block. The
procedure must accept an initial pointer argument that is the ``self''
argument for the block, and that extra argument must be included in
the given @racket[function-type].

Extra records that are allocated to implement the block are added to
the list in @racket[keep], which might also be included in
@racket[function-type] through a @racket[#:keep] option to
@racket[_fun]. The pointers registered in @racket[keep] must be
retained as long as the block remains in use.

@history[#:added "6.3"]}


@defproc[(objc-block-function-pointer [block cpointer?]) fpointer?]{

Extracts the function pointer of an Objective-C block. Cast this
function pointer to a suitable function type to call it, where the
block itself must be passed as the first argument to the function.

@history[#:added "8.13.0.1"]}


@defform[(with-blocking-tell form ...+)]{

Causes any @racket[tell], @racket[tellv], or @racket[super-tell]
expression syntactically within the @racket[form]s to be blocking in
the sense of the @racket[#:blocking?] argument to
@racket[_cprocedure]. Otherwise, @racket[(with-blocking-tell form
...+)] is equivalent to @racket[(let () form ...+)].

@history[#:added "7.0.0.19"]}

@; ----------------------------------------------------------------------

@section{Raw Runtime Functions}

@defproc[(objc_lookUpClass [s string?]) (or/c _Class #f)]{

Finds a registered class by name.}

@defproc[(objc_getProtocol [s string?]) (or/c _Protocol #f)]{

Finds a registered protocol by name.}

@defproc[(sel_registerName [s string?]) _SEL]{

Interns a selector given its name in string form.}

@defproc[(objc_allocateClassPair [cls _Class] [s string?] [extra integer?])
         _Class]{

Allocates a new Objective-C class.}

@defproc[(objc_registerClassPair [cls _Class]) void?]{

Registers an Objective-C class.}

@defproc[(object_getClass [obj _id]) _Class]{

Returns the class of an object (or the meta-class of a class).}

@defproc[(class_getSuperclass [cls _Class])
         _Class]{

Returns the superclass of @racket[cls] or @racket[#f] if @racket[cls]
has no superclass.

@history[#:added "6.1.0.5"]}

@defproc[(class_addMethod [cls _Class] [sel _SEL] 
                          [imp procedure?]
                          [type ctype?]
                          [type-encoding string?])
         boolean?]{

Adds a method to a class. The @racket[type] argument must be a FFI C
type (@seeCtype) that matches both @racket[imp] and the not
Objective-C type string @racket[type-encoding].}

@defproc[(class_addIvar [cls _Class] [name string?] [size exact-nonnegative-integer?]
                        [log-alignment exact-nonnegative-integer?] [type-encoding string?])
         boolean?]{

Adds an instance variable to an Objective-C class.}

@defproc[(object_getInstanceVariable [obj _id]
                                     [name string?])
         (values _Ivar any/c)]{

Gets the value of an instance variable whose type is @racket[_pointer].}

@defproc[(object_setInstanceVariable [obj _id]
                                     [name string?]
                                     [val any/c])
         _Ivar]{

Sets the value of an instance variable whose type is @racket[_pointer].}

@defthing[_Ivar ctype?]{

The type of an Objective-C instance variable, an opaque pointer.}

@defproc[((objc_msgSend/typed [types (vector/c result-ctype arg-ctype ...)])
          [obj _id]
          [sel _SEL]
          [arg any/c])
         any/c]{

Calls the Objective-C method on @racket[_id] named by @racket[sel].
The @racket[types] vector must contain one more than the number of
supplied @racket[arg]s; the first FFI C type in @racket[type] is used
as the result type.}

@defproc[((objc_msgSendSuper/typed [types (vector/c result-ctype arg-ctype ...)])
          [super _objc_super]
          [sel _SEL]
          [arg any/c])
         any/c]{

Like @racket[objc_msgSend/typed], but for a super call.}

@deftogether[(
@defproc[(make-objc_super [id _id] [super _Class]) _objc_super]
@defthing[_objc_super ctype?]
)]{

Constructor and FFI C type use for super calls.}

@deftogether[(
@defproc[((objc_msgSend/typed/blocking [types (vector/c result-ctype arg-ctype ...)])
          [obj _id]
          [sel _SEL]
          [arg any/c])
         any/c]
@defproc[((objc_msgSendSuper/typed/blocking [types (vector/c result-ctype arg-ctype ...)])
          [super _objc_super]
          [sel _SEL]
          [arg any/c])
         any/c]
)]{

The same as @racket[objc_msgSend/typed] and
@racket[objc_msgSendSuper/typed], but specifying that the send should
be blocking in the sense of the @racket[#:blocking?] argument to
@racket[_cprocedure].

@history[#:added "7.0.0.19"]}

@; ----------------------------------------------------------------------

@section{Legacy Library}

@defmodule[ffi/objc]{The @racketmodname[ffi/objc] library is a
deprecated entry point to @racketmodname[ffi/unsafe/objc]. It
exports only safe operations directly, and unsafe operations are
imported using @racket[objc-unsafe!], analogous to @racketmodname[scheme/foreign #:indirect].}

@defform[(objc-unsafe!)]{

Makes unsafe bindings of
@racketmodname[ffi/unsafe/objc] available in the importing
module.}


@close-eval[objc-eval]
