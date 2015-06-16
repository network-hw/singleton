(* module Syntax: syntax trees and associated support functions *)

open Support.Pervasive
open Support.Error

type kind = KndU | KndA

(* Data type definitions *)
type ty =
    TyVar of int * int
  | TyTop
  | TyBot
  | TyId of string
  | TyArr of ty * ty * kind
  | TyRecord of (string * ty) list
  | TyVariant of (string * ty) list
  | TyRef of ty
  | TyBool
  | TyString
  | TyUnit
  | TyFloat
  | TySource of ty
  | TySink of ty
  | TyNat
  | TyMvar of ty (*definition for Mvar variable *)
  | TyProduct of ty * ty

type term =
    TmVar of info * int * int
  | TmAbs of info * string * ty * term
  | TmApp of info * term * term
  | TmTrue of info
  | TmFalse of info
  | TmIf of info * term * term * term
  | TmLet of info * string * term * term
  | TmFix of info * term
  | TmRecord of info * (string * term) list
  | TmProj of info * term * string
  | TmCase of info * term * (string * (string * term)) list
  | TmTag of info * string * term * ty
  | TmAscribe of info * term * ty
  | TmString of info * string
  | TmUnit of info
  | TmLoc of info * int
  | TmRef of info * term
  | TmDeref of info * term 
  | TmAssign of info * term * term
  | TmFloat of info * float
  | TmTimesfloat of info * term * term
  | TmZero of info
  | TmSucc of info * term
  | TmPred of info * term
  | TmIsZero of info * term
  | TmInert of info * ty
  | TmMvar of info * term (* definition for Mvar term *)
  | TmDeMvar of info * term
  | TmAssignMvar of info * term * term
  | TmProduct of info * term * term
  | TmFork of info * term

type binding =
    NameBind 
  | TyVarBind
  | VarBind of ty
  | TmAbbBind of term * (ty option)
  | TyAbbBind of ty

type command =
  | Eval of info * term
  | Bind of info * string * binding


(* Contexts *)
type context = (string * binding) list
val emptycontext : context 
val ctxlength : context -> int
val addbinding : context -> string -> binding -> context
val addname: context -> string -> context
val index2name : info -> context -> int -> string
val getbinding : info -> context -> int -> binding
val name2index : info -> context -> string -> int
val isnamebound : context -> string -> bool
exception GetTypeFailure
val getTypeFromContext : info -> context -> int -> ty

(* Shifting and substitution *)
val termShift: int -> term -> term
val termSubstTop: term -> term -> term
val typeShift : int -> ty -> ty
val typeSubstTop: ty -> ty -> ty
val tytermSubstTop: ty -> term -> term

(* Printing *)
val printtm: context -> term -> unit
val printtm_ATerm: bool -> context -> term -> unit
val printty : context -> ty -> unit
val prbinding : context -> binding -> unit
val prcontext: context -> unit
val printknd: kind -> unit
(* Misc *)
val tmInfo: term -> info

