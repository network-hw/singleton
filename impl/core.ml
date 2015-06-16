open Format
open Syntax
open Support.Error
open Support.Pervasive

(* ------------------------   EVALUATION  ------------------------ *)

let rec isnumericval ctx t = match t with
    TmZero(_) -> true
  | TmSucc(_,t1) -> isnumericval ctx t1
  | _ -> false

let rec isval ctx t = match t with
    TmTrue(_)  -> true
  | TmFalse(_) -> true
  | TmTag(_,l,t1,_) -> isval ctx t1
  | TmString _  -> true
  | TmUnit(_)  -> true
  | TmLoc(_,_) -> true
  | TmFloat _  -> true
  | t when isnumericval ctx t  -> true
  | TmAbs(_,_,_,_) -> true
  | TmRecord(_,fields) -> List.for_all (fun (l,ti) -> isval ctx ti) fields
  | _ -> false

type store = term list  
let emptystore = []
let extendstore store v = (List.length store, List.append store [v])
let lookuploc store l = List.nth store l
let updatestore store n v =
  let rec f s = match s with 
      (0, v'::rest) -> v::rest
    | (n, v'::rest) -> v' :: (f (n-1,rest))
    | _ -> error dummyinfo "updatestore: bad index"
  in
    f (n,store)
let shiftstore i store = List.map (fun t -> termShift i t) store 

exception NoRuleApplies
exception TypingFailed of info * string

let rec eval1 ctx store t = match t with
    TmApp(fi,TmAbs(_,x,tyT11,t12),v2) when isval ctx v2 ->
      termSubstTop v2 t12, store
  | TmApp(fi,v1,t2) when isval ctx v1 ->
      let t2',store' = eval1 ctx store t2 in
      TmApp(fi, v1, t2'), store'
  | TmApp(fi,t1,t2) ->
      let t1',store' = eval1 ctx store t1 in
      TmApp(fi, t1', t2), store'
  | TmIf(_,TmTrue(_),t2,t3) ->
      t2, store
  | TmIf(_,TmFalse(_),t2,t3) ->
      t3, store
  | TmIf(fi,t1,t2,t3) ->
      let t1',store' = eval1 ctx store t1 in
      TmIf(fi, t1', t2, t3), store'
  | TmLet(fi,x,v1,t2) when isval ctx v1 ->
      termSubstTop v1 t2, store 
  | TmLet(fi,x,t1,t2) ->
      let t1',store' = eval1 ctx store t1 in
      TmLet(fi, x, t1', t2), store' 
  | TmFix(fi,v1) as t when isval ctx v1 ->
      (match v1 with
         TmAbs(_,_,_,t12) -> termSubstTop t t12, store
       | _ -> raise NoRuleApplies)
  | TmFix(fi,t1) ->
      let t1',store' = eval1 ctx store t1
      in TmFix(fi,t1'), store'
  | TmRecord(fi,fields) ->
      let rec evalafield l = match l with 
        [] -> raise NoRuleApplies
      | (l,vi)::rest when isval ctx vi -> 
          let rest',store' = evalafield rest in
          (l,vi)::rest', store'
      | (l,ti)::rest -> 
          let ti',store' = eval1 ctx store ti in
          (l, ti')::rest, store'
      in let fields',store' = evalafield fields in
      TmRecord(fi, fields'), store'
  | TmProj(fi, (TmRecord(_, fields) as v1), l) when isval ctx v1 ->
      (try List.assoc l fields, store
       with Not_found -> raise NoRuleApplies)
  | TmProj(fi, t1, l) ->
      let t1',store' = eval1 ctx store t1 in
      TmProj(fi, t1', l), store'
  | TmTag(fi,l,t1,tyT) ->
      let t1',store' = eval1 ctx store t1 in
      TmTag(fi, l, t1',tyT), store'
  | TmCase(fi,TmTag(_,li,v11,_),branches) when isval ctx v11->
      (try 
         let (x,body) = List.assoc li branches in
         termSubstTop v11 body, store
       with Not_found -> raise NoRuleApplies)
  | TmCase(fi,t1,branches) ->
      let t1',store' = eval1 ctx store t1 in
      TmCase(fi, t1', branches), store'
  | TmAscribe(fi,v1,tyT) when isval ctx v1 ->
      v1, store
  | TmAscribe(fi,t1,tyT) ->
      let t1',store' = eval1 ctx store t1 in
      TmAscribe(fi,t1',tyT), store'
  | TmVar(fi,n,_) ->
      (match getbinding fi ctx n with
          TmAbbBind(t,_) -> t,store 
        | _ -> raise NoRuleApplies)
  | TmRef(fi,t1) ->
      if not (isval ctx t1) then
        let (t1',store') = eval1 ctx store t1
        in (TmRef(fi,t1'), store')
      else
        let (l,store') = extendstore store t1 in
        (TmLoc(dummyinfo,l), store')
  | TmMvar(fi,t1) ->
      if not (isval ctx t1) then
        let (t1',store') = eval1 ctx store t1
        in (TmMvar(fi,t1'), store')
      else
        let (l,store') = extendstore store t1 in
        (TmLoc(dummyinfo,l), store')
  | TmDeref(fi,t1) ->
      if not (isval ctx t1) then
        let (t1',store') = eval1 ctx store t1
        in (TmDeref(fi,t1'), store')
      else (match t1 with
            TmLoc(_,l) -> (lookuploc store l, store)
          | _ -> raise NoRuleApplies)
  | TmDeMvar(fi,t1) ->
      if not (isval ctx t1) then
        let (t1',store') = eval1 ctx store t1
        in (TmDeref(fi,t1'), store')
      else (match t1 with
            TmLoc(_,l) -> (lookuploc store l, store)
          | _ -> raise NoRuleApplies)
  | TmAssign(fi,t1,t2) ->
      if not (isval ctx t1) then
        let (t1',store') = eval1 ctx store t1
        in (TmAssign(fi,t1',t2), store')
      else if not (isval ctx t2) then
        let (t2',store') = eval1 ctx store t2
        in (TmAssign(fi,t1,t2'), store')
      else (match t1 with
            TmLoc(_,l) -> (TmUnit(dummyinfo), updatestore store l t2)
          | _ -> raise NoRuleApplies)
  | TmAssignMvar(fi,t1,t2) ->
      if not (isval ctx t1) then
        let (t1',store') = eval1 ctx store t1
        in (TmAssignMvar(fi,t1',t2), store')
      else if not (isval ctx t2) then
        let (t2',store') = eval1 ctx store t2
        in (TmAssignMvar(fi,t1,t2'), store')
      else (match t1 with
            TmLoc(_,l) -> (TmUnit(dummyinfo), updatestore store l t2)
          | _ -> raise NoRuleApplies)
  | TmTimesfloat(fi,TmFloat(_,f1),TmFloat(_,f2)) ->
      TmFloat(fi, f1 *. f2), store
  | TmTimesfloat(fi,(TmFloat(_,f1) as t1),t2) ->
      let t2',store' = eval1 ctx store t2 in
      TmTimesfloat(fi,t1,t2') , store'
  | TmTimesfloat(fi,t1,t2) ->
      let t1',store' = eval1 ctx store t1 in
      TmTimesfloat(fi,t1',t2) , store'
  | TmSucc(fi,t1) ->
      let t1',store' = eval1 ctx store t1 in
      TmSucc(fi, t1'), store'
  | TmPred(_,TmZero(_)) ->
      TmZero(dummyinfo), store
  | TmPred(_,TmSucc(_,nv1)) when (isnumericval ctx nv1) ->
      nv1, store
  | TmPred(fi,t1) ->
      let t1',store' = eval1 ctx store t1 in
      TmPred(fi, t1'), store'
  | TmIsZero(_,TmZero(_)) ->
      TmTrue(dummyinfo), store
  | TmIsZero(_,TmSucc(_,nv1)) when (isnumericval ctx nv1) ->
      TmFalse(dummyinfo), store
  | TmIsZero(fi,t1) ->
      let t1',store' = eval1 ctx store t1 in
      TmIsZero(fi, t1'), store'
  | TmFork(fi,t) -> (match t with 
      TmProduct(fi',v1,v2) when (isval ctx v2) && (isval ctx v1) -> 
        TmProduct(fi',v1,v2), store
    (*
    | TmProduct(fi',v1,t2) when (isval ctx v1) ->
        let t2',store' = eval1 ctx store t2 in
        TmFork(fi,TmProduct(fi',v1,t2')), store'
    *)
    | TmProduct(fi',t1,t2) ->
        let rand = Random.int 1000 in
        (* pr (string_of_int rand); pr "\n"; *)
        if rand >= 500 then
          let t1',store' = eval1 ctx store t1 in
          TmFork(fi,TmProduct(fi',t1',t2)), store'
        else 
          let t2',store' = eval1 ctx store t2 in
          TmFork(fi,TmProduct(fi',t1, t2')), store')
  | _ -> 
      raise NoRuleApplies

let rec eval ctx store t =
  try let t',store' = eval1 ctx store t
      in eval ctx store' t'
  with NoRuleApplies -> t,store


(* ------------------------   KIND --------------------------- *)

let meetkind ctx knd1 knd2 = match (knd1,knd2) with 
      (KndU,KndU) -> KndU
    | _ -> KndA
    
let joinkind ctx knd1 knd2 = match (knd1,knd2) with
    (KndA, KndA) -> KndA
  | _ -> KndU

let rec kindof ctx ty = match ty with
    TyUnit -> KndU
  | TyRef(_) -> KndA
  | TyMvar(_) -> KndU
  | TyNat -> KndA
  | TyArr(_,_,knd) -> knd
  | TyProduct(ty1,ty2) -> 
      meetkind ctx (kindof ctx ty1) (kindof ctx ty2)

let upperboundkind ctx typeof =
  let rec upperbound ctx knd = 
    match ctx with 
        [] -> knd 
      | (_,VarBind(ty))::rest -> 
        let knd' = meetkind ctx (kindof ctx ty) knd in
          (* printty ctx ty; printknd knd; printknd knd'; pr "\n"; *)
          upperbound rest knd'
      (*
      | (_,TmAbbBind(t,_))::rest -> 
        printtm ctx t;
        let ty = typeof ctx t in
        let knd = kindof ctx ty in
          (* printty ctx ty; printknd knd; printknd knd'; pr "\n"; *)
          upperbound rest knd
      *)
      | (_,_)::rest -> upperbound rest knd
  in
    upperbound ctx KndU

let ctxsplit ctx = 
  let rec split1 ctx = match ctx with
        [] -> ([],[])
      | (a, VarBind(ty))::rest -> 
        let (ctxu,ctxphi) = split1 rest in
        let binding = (a,VarBind(ty)) in
        let knd = kindof ctx ty in
        printty ctx ty; pr ":"; printknd knd; pr "\n";
        (match knd with
            KndA -> (ctxu, binding::ctxphi)
          | KndU -> (binding::ctxu, ctxphi))
      | (a, TmAbbBind(t,ty))::rest -> 
          let (ctxu,ctxphi) = split1 rest in
          let binding = (a,TmAbbBind(t,ty)) in
          (match t with
              TmLoc(_,_) -> (ctxu, binding::ctxphi)
            | _ -> 
              (*let ty' = typeof ctx t in*)
              (match ty with 
                None -> (binding::ctxu, ctxphi)
              | Some(tyT) ->
                let knd = kindof ctx tyT in
                (match knd with
                    KndA -> (ctxu, binding::ctxphi)
                  | KndU -> (binding::ctxu, ctxphi))))
      | (_,_)::rest -> split1 rest
  in
  let rec split2 ctxu ctxphi = match ctxu with
      [] -> ([], ctxphi)
    | (x,bind)::rest -> 
        let (ctxu',ctxphi') = split2 rest ctxphi in
        if isnamebound ctxphi' x then (ctxu', (x,bind)::ctxphi')
        else  ((x,bind)::ctxu', ctxphi')
  in
  let (ctxu, ctxphi) = split1 ctx in
    split2 ctxu ctxphi

let rec ctxseperate xs = 
  let res = match xs with
      [] -> [([], [])]
    | x::xs' -> 
        let ys = ctxseperate xs' in
        (List.fold_left 
            (fun acc (y1,y2) -> ((x::y1),y2)::(y1,(x::y2))::acc)
            []
            ys)
  in
  (List.filter 
    (fun (y1,y2) -> 
      let rec findtuple (x1,y1) xs = match xs with
          [] -> false
        | (x,y)::xs' -> if x1 = x then true else findtuple (x1,y1) xs'
      in
      let rec findsame xs ys = match xs with
          [] -> true
        | x::xs' -> not (findtuple x ys)
      in
        findsame y1 y2)
    res)

(* ------------------------   SUBTYPING  ------------------------ *)

let evalbinding ctx store b = match b with
    TmAbbBind(t,tyT) ->
      let t',store' = eval ctx store t in 
      TmAbbBind(t',tyT), store'
  | bind -> bind,store

let istyabb ctx i = 
  match getbinding dummyinfo ctx i with
    TyAbbBind(tyT) -> true
  | _ -> false

let gettyabb ctx i = 
  match getbinding dummyinfo ctx i with
    TyAbbBind(tyT) -> tyT
  | _ -> raise NoRuleApplies

let rec computety ctx tyT = match tyT with
    TyVar(i,_) when istyabb ctx i -> gettyabb ctx i
  | _ -> raise NoRuleApplies

let rec simplifyty ctx tyT =
  try
    let tyT' = computety ctx tyT in
    simplifyty ctx tyT' 
  with NoRuleApplies -> tyT

let rec tyeqv ctx tyS tyT =
  let tyS = simplifyty ctx tyS in
  let tyT = simplifyty ctx tyT in
  match (tyS,tyT) with
    (TyTop,TyTop) -> true
  | (TyBot,TyBot) -> true
  | (TyArr(tyS1,tyS2, _),TyArr(tyT1,tyT2, _)) ->
       (tyeqv ctx tyS1 tyT1) && (tyeqv ctx tyS2 tyT2)
  | (TyString,TyString) -> true
  | (TyId(b1),TyId(b2)) -> b1=b2
  | (TyFloat,TyFloat) -> true
  | (TyUnit,TyUnit) -> true
  | (TyRef(tyT1),TyRef(tyT2)) -> tyeqv ctx tyT1 tyT2
  | (TySource(tyT1),TySource(tyT2)) -> tyeqv ctx tyT1 tyT2
  | (TySink(tyT1),TySink(tyT2)) -> tyeqv ctx tyT1 tyT2
  | (TyVar(i,_), _) when istyabb ctx i ->
      tyeqv ctx (gettyabb ctx i) tyT
  | (_, TyVar(i,_)) when istyabb ctx i ->
      tyeqv ctx tyS (gettyabb ctx i)
  | (TyVar(i,_),TyVar(j,_)) -> i=j
  | (TyBool,TyBool) -> true
  | (TyNat,TyNat) -> true
  | (TyRecord(fields1),TyRecord(fields2)) -> 
       List.length fields1 = List.length fields2
       &&                                         
       List.for_all 
         (fun (li2,tyTi2) ->
            try let (tyTi1) = List.assoc li2 fields1 in
                tyeqv ctx tyTi1 tyTi2
            with Not_found -> false)
         fields2
  | (TyVariant(fields1),TyVariant(fields2)) ->
       (List.length fields1 = List.length fields2)
       && List.for_all2
            (fun (li1,tyTi1) (li2,tyTi2) ->
               (li1=li2) && tyeqv ctx tyTi1 tyTi2)
            fields1 fields2
  | _ -> false

let rec subtype ctx tyS tyT =
   tyeqv ctx tyS tyT ||
   let tyS = simplifyty ctx tyS in
   let tyT = simplifyty ctx tyT in
   match (tyS,tyT) with
     (_,TyTop) -> 
       true
   | (TyBot,_) -> 
       true
   | (TyArr(tyS1,tyS2, _),TyArr(tyT1,tyT2, _)) ->
       (subtype ctx tyT1 tyS1) && (subtype ctx tyS2 tyT2)
   | (TyRecord(fS), TyRecord(fT)) ->
       List.for_all
         (fun (li,tyTi) -> 
            try let tySi = List.assoc li fS in
                subtype ctx tySi tyTi
            with Not_found -> false)
         fT
   | (TyVariant(fS), TyVariant(fT)) ->
       List.for_all
         (fun (li,tySi) -> 
            try let tyTi = List.assoc li fT in
                subtype ctx tySi tyTi
            with Not_found -> false)
         fS
   | (TyRef(tyT1),TyRef(tyT2)) ->
       subtype ctx tyT1 tyT2 && subtype ctx tyT2 tyT1
   | (TyRef(tyT1),TySource(tyT2)) ->
       subtype ctx tyT1 tyT2
   | (TySource(tyT1),TySource(tyT2)) ->
       subtype ctx tyT1 tyT2
   | (TyRef(tyT1),TySink(tyT2)) ->
       subtype ctx tyT2 tyT1
   | (TySink(tyT1),TySink(tyT2)) ->
       subtype ctx tyT2 tyT1
   | (_,_) -> 
       false

let rec join ctx tyS tyT =
  if subtype ctx tyS tyT then tyT else 
  if subtype ctx tyT tyS then tyS else
  let tyS = simplifyty ctx tyS in
  let tyT = simplifyty ctx tyT in
  match (tyS,tyT) with
    (TyRecord(fS), TyRecord(fT)) ->
      let labelsS = List.map (fun (li,_) -> li) fS in
      let labelsT = List.map (fun (li,_) -> li) fT in
      let commonLabels = 
        List.find_all (fun l -> List.mem l labelsT) labelsS in
      let commonFields = 
        List.map (fun li -> 
                    let tySi = List.assoc li fS in
                    let tyTi = List.assoc li fT in
                    (li, join ctx tySi tyTi))
                 commonLabels in
      TyRecord(commonFields)
  | (TyArr(tyS1,tyS2,knd1),TyArr(tyT1,tyT2,knd2)) ->
      TyArr(meet ctx tyS1 tyT1, join ctx tyS2 tyT2, meetkind ctx knd1 knd2)
  | (TyRef(tyT1),TyRef(tyT2)) ->
      if subtype ctx tyT1 tyT2 && subtype ctx tyT2 tyT1 
        then TyRef(tyT1)
        else (* Warning: this is incomplete... *)
             TySource(join ctx tyT1 tyT2)
  | (TySource(tyT1),TySource(tyT2)) ->
      TySource(join ctx tyT1 tyT2)
  | (TyRef(tyT1),TySource(tyT2)) ->
      TySource(join ctx tyT1 tyT2)
  | (TySource(tyT1),TyRef(tyT2)) ->
      TySource(join ctx tyT1 tyT2)
  | (TySink(tyT1),TySink(tyT2)) ->
      TySink(meet ctx tyT1 tyT2)
  | (TyRef(tyT1),TySink(tyT2)) ->
      TySink(meet ctx tyT1 tyT2)
  | (TySink(tyT1),TyRef(tyT2)) ->
      TySink(meet ctx tyT1 tyT2)
  | _ -> 
      TyTop

and meet ctx tyS tyT =
  if subtype ctx tyS tyT then tyS else 
  if subtype ctx tyT tyS then tyT else 
  let tyS = simplifyty ctx tyS in
  let tyT = simplifyty ctx tyT in
  match (tyS,tyT) with
    (TyRecord(fS), TyRecord(fT)) ->
      let labelsS = List.map (fun (li,_) -> li) fS in
      let labelsT = List.map (fun (li,_) -> li) fT in
      let allLabels = 
        List.append
          labelsS 
          (List.find_all 
            (fun l -> not (List.mem l labelsS)) labelsT) in
      let allFields = 
        List.map (fun li -> 
                    if List.mem li allLabels then
                      let tySi = List.assoc li fS in
                      let tyTi = List.assoc li fT in
                      (li, meet ctx tySi tyTi)
                    else if List.mem li labelsS then
                      (li, List.assoc li fS)
                    else
                      (li, List.assoc li fT))
                 allLabels in
      TyRecord(allFields)
  | (TyArr(tyS1,tyS2,knd1),TyArr(tyT1,tyT2,knd2)) ->
      TyArr(join ctx tyS1 tyT1, meet ctx tyS2 tyT2, joinkind ctx knd1 knd2)
  | (TyRef(tyT1),TyRef(tyT2)) ->
      if subtype ctx tyT1 tyT2 && subtype ctx tyT2 tyT1 
        then TyRef(tyT1)
        else (* Warning: this is incomplete... *)
             TySource(meet ctx tyT1 tyT2)
  | (TySource(tyT1),TySource(tyT2)) ->
      TySource(meet ctx tyT1 tyT2)
  | (TyRef(tyT1),TySource(tyT2)) ->
      TySource(meet ctx tyT1 tyT2)
  | (TySource(tyT1),TyRef(tyT2)) ->
      TySource(meet ctx tyT1 tyT2)
  | (TySink(tyT1),TySink(tyT2)) ->
      TySink(join ctx tyT1 tyT2)
  | (TyRef(tyT1),TySink(tyT2)) ->
      TySink(join ctx tyT1 tyT2)
  | (TySink(tyT1),TyRef(tyT2)) ->
      TySink(join ctx tyT1 tyT2)
  | _ -> 
      TyBot

(* ------------------------   TYPING  ------------------------ *)
let rec typeof ctx t =
  match t with
    TmInert(fi,tyT) ->
      tyT
  | TmVar(fi,i,_) -> getTypeFromContext fi ctx i
  | TmAbs(fi,x,tyT1,t2) ->
      (* printtm ctx t2; pr "\n"; *)
      (* here to extend the context *)
      let ctx' = addbinding ctx x (VarBind(tyT1)) in
      (* and the type of T2 has been found *)
      let tyT2 = typeof ctx' t2 in
      (* we need to check the upperbound at last *)
      let upKnd = upperboundkind ctx typeof in
      TyArr(tyT1, typeShift (-1) tyT2, upKnd) (* back later *)
  | TmApp(fi,t1,t2) ->
      (* first we split our context *)
      let (ctxu, ctxphi) = ctxsplit ctx in
      
      prcontext ctx;
      pr "ctxu: \n";
      prcontext ctxu;
      pr "ctxphi: \n";
      prcontext ctxphi;
      
      (* then we check each ctx1,ctx2 in the seperated ctxphi *)      
      let rec walk ctxss = 
        match ctxss with
          [] -> raise (TypingFailed (fi,"no context applied"))
        | (ctx1,ctx2)::ctxss' ->
          pr "try: \n"; prcontext ctx1; prcontext ctx2;
          let ctx11 = List.concat [ctx1;ctxu] in
          let ctx12 = List.concat [ctx2;ctxu] in
          try  
            let tyT1 = typeof ctx11 t1 in
            let tyT2 = typeof ctx12 t2 in
            (match simplifyty ctx tyT1 with
                TyArr(tyT11,tyT12,_) ->
                  if subtype ctx tyT2 tyT11 then tyT12
                  else raise (TypingFailed (fi,"parameter type mismatch"))
              | TyBot -> TyBot
              | _ -> raise (TypingFailed (fi,"arrow type expected")))
          with 
            TypingFailed(_,msg) ->
              (*pr msg;*)
              walk ctxss'
          | Syntax.GetTypeFailure -> 
              (*pr "GetTypeFailure\n";*)
              walk ctxss'
      in
      let ctxss = (ctxseperate ctxphi) in
        (*pr "bindings in ctxphi...\n";
        List.iter (fun (s,b) -> pr s; prbinding ctxphi b; pr "\n") ctxphi;*)
        walk ctxss
  | TmTrue(fi) -> 
      TyBool
  | TmFalse(fi) -> 
      TyBool
  | TmIf(fi,t1,t2,t3) ->
      if subtype ctx (typeof ctx t1) TyBool then
        join ctx (typeof ctx t2) (typeof ctx t3)
      else error fi "guard of conditional not a boolean"
  | TmLet(fi,x,t1,t2) ->
      let (ctxu,ctxphi) = ctxsplit ctx in
      (*
      prcontext ctx;
      pr "ctxu: \n";
      prcontext ctxu;
      pr "ctxphi: \n";
      prcontext ctxphi;
      *)
      (* then we check each ctx1,ctx2 in the seperated ctxphi *)      
      let rec walk ctxss = 
        match ctxss with
          [] -> raise (TypingFailed (fi,"no context applied"))
        | (ctx1,ctx2)::ctxss' ->
          pr "try: \n"; prcontext ctx1; prcontext ctx2;
          let ctx11 = List.concat [ctx1;ctxu] in
          let ctx12 = List.concat [ctx2;ctxu] in
          try
            let tyT1 = typeof ctx11 t1 in
            let ctx12' = addbinding ctx12 x (VarBind(tyT1)) in
            let tyT2 = typeof ctx12' t2 in
              typeShift (-1) tyT2
          with 
            TypingFailed(_,msg) ->
              (*pr msg;*)
              walk ctxss'
          | Syntax.GetTypeFailure -> 
              (*pr "GetTypeFailure\n";*)
              walk ctxss'
      in
      let ctxss = (ctxseperate ctxphi) in
        (*pr "bindings in ctxphi...\n";
        List.iter (fun (s,b) -> pr s; prbinding ctxphi b; pr "\n") ctxphi;*)
        walk ctxss
  | TmProduct(fi,t1,t2)->
      let tyT1 = typeof ctx t1 in
      let tyT2 = typeof ctx t2 in 
      TyProduct(tyT1, tyT2)
  | TmRecord(fi, fields) ->
      let fieldtys = 
        List.map (fun (li,ti) -> (li, typeof ctx ti)) fields in
      TyRecord(fieldtys)
  | TmProj(fi, t1, l) ->
      (match simplifyty ctx (typeof ctx t1) with
          TyRecord(fieldtys) ->
            (try List.assoc l fieldtys
             with Not_found -> error fi ("label "^l^" not found"))
        | TyBot -> TyBot
        | _ -> error fi "Expected record type")
  | TmCase(fi, t, cases) ->
      (match simplifyty ctx (typeof ctx t) with
         TyVariant(fieldtys) ->
           List.iter
             (fun (li,(xi,ti)) ->
                try let _ = List.assoc li fieldtys in ()
                with Not_found -> error fi ("label "^li^" not in type"))
             cases;
           let casetypes =
             List.map (fun (li,(xi,ti)) ->
                         let tyTi =
                           try List.assoc li fieldtys
                           with Not_found ->
                             error fi ("label "^li^" not found") in
                         let ctx' = addbinding ctx xi (VarBind(tyTi)) in
                         typeShift (-1) (typeof ctx' ti))
                      cases in
           List.fold_left (join ctx) TyBot casetypes
        | TyBot -> TyBot
        | _ -> error fi "Expected variant type")
  | TmFix(fi, t1) ->
      let tyT1 = typeof ctx t1 in
      (match simplifyty ctx tyT1 with
           TyArr(tyT11,tyT12,_) ->
             if subtype ctx tyT12 tyT11 then tyT12
             else error fi "result of body not compatible with domain"
         | TyBot -> TyBot
         | _ -> error fi "arrow type expected")
  | TmTag(fi, li, ti, tyT) ->
      (match simplifyty ctx tyT with
          TyVariant(fieldtys) ->
            (try
               let tyTiExpected = List.assoc li fieldtys in
               let tyTi = typeof ctx ti in
               if subtype ctx tyTi tyTiExpected
                 then tyT
                 else error fi "field does not have expected type"
             with Not_found -> error fi ("label "^li^" not found"))
        | _ -> error fi "Annotation is not a variant type")
  | TmAscribe(fi,t1,tyT) ->
     if subtype ctx (typeof ctx t1) tyT then
       tyT
     else
       error fi "body of as-term does not have the expected type"
  | TmString _ -> TyString
  | TmUnit(fi) -> TyUnit
  | TmRef(fi,t1) ->
      TyRef(typeof ctx t1)
  | TmMvar(fi,t1) ->
      TyMvar(typeof ctx t1)
  | TmLoc(fi,l) ->
      error fi "locations are not supposed to occur in source programs!"
  | TmDeref(fi,t1) ->
      (match simplifyty ctx (typeof ctx t1) with
          TyRef(tyT1) -> tyT1
        | TyBot -> TyBot
        | TySource(tyT1) -> tyT1
        | _ -> error fi "argument of ! is not a Ref or Source")
  | TmDeMvar(fi,t1) ->
      (match simplifyty ctx (typeof ctx t1) with
          TyMvar(tyT1) -> tyT1
        | TyBot -> TyBot
        | TySource(tyT1) -> tyT1
        | _ -> error fi "argument of $ is not a Ref or Source")
  | TmAssign(fi,t1,t2) ->
      (match simplifyty ctx (typeof ctx t1) with
          TyRef(tyT1) ->
            if subtype ctx (typeof ctx t2) tyT1 then
              TyUnit
            else
              error fi "arguments of := are incompatible"
        | TyBot -> let _ = typeof ctx t2 in TyBot
        | TySink(tyT1) ->
            if subtype ctx (typeof ctx t2) tyT1 then
              TyUnit
            else
              error fi "arguments of := are incompatible"
        | _ -> error fi "argument of ! is not a Ref or Sink")
  | TmAssignMvar(fi,t1,t2) ->
      (match simplifyty ctx (typeof ctx t1) with
          TyMvar(tyT1) ->
            if subtype ctx (typeof ctx t2) tyT1 then
              TyUnit
            else
              error fi "arguments of =<< are incompatible"
        | TyBot -> let _ = typeof ctx t2 in TyBot
        | TySink(tyT1) ->
            if subtype ctx (typeof ctx t2) tyT1 then
              TyUnit
            else
              error fi "arguments of =<< are incompatible"
        | _ -> error fi "argument of $ is not a Ref or Sink")
  | TmFloat _ -> TyFloat
  | TmTimesfloat(fi,t1,t2) ->
      if subtype ctx (typeof ctx t1) TyFloat
      && subtype ctx (typeof ctx t2) TyFloat then TyFloat
      else error fi "argument of timesfloat is not a number"
  | TmZero(fi) ->
      TyNat
  | TmSucc(fi,t1) ->
      if subtype ctx (typeof ctx t1) TyNat then TyNat
      else error fi "argument of succ is not a number"
  | TmPred(fi,t1) ->
      if subtype ctx (typeof ctx t1) TyNat then TyNat
      else error fi "argument of pred is not a number"
  | TmIsZero(fi,t1) ->
      if subtype ctx (typeof ctx t1) TyNat then TyBool
      else error fi "argument of iszero is not a number"
  | TmFork(fi,t) -> 
    match t with
      TmProduct(fi,t1,t2) -> typeof ctx t
    | _ -> raise (TypingFailed (fi, "fork with non-product term"))
