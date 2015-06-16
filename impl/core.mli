(* module Core

   Core typechecking and evaluation functions
*)

open Syntax
open Support.Error

val kindof : context -> ty -> kind
val meetkind: context -> kind -> kind -> kind
val joinkind: context -> kind -> kind -> kind
val upperboundkind: context -> (context->term->ty) -> kind

val ctxsplit: context -> (context * context)
val ctxseperate: context -> (context * context) list

val typeof : context -> term -> ty
val subtype : context -> ty -> ty -> bool
val tyeqv : context -> ty -> ty -> bool
val simplifyty : context -> ty -> ty
type store
val emptystore : store
val shiftstore : int -> store -> store 
val eval : context -> store -> term -> term * store
val evalbinding : context -> store -> binding -> binding * store
