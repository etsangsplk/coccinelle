(*external c_counter : unit -> int = "c_counter"*)
let timeout = 800
(* Optimize triples_conj by first extracting the intersection of the two sets,
which can certainly be in the intersection *)
let pTRIPLES_CONJ_OPT = ref true
(* For complement, make NegState for the negation of a single state *)
let pTRIPLES_COMPLEMENT_OPT = ref true
(* For complement, do something special for the case where the environment
and witnesses are empty *)
let pTRIPLES_COMPLEMENT_SIMPLE_OPT = ref true
(* "Double negate" the arguments of the path operators *)
let pDOUBLE_NEGATE_OPT = ref true
(* Only do pre_forall/pre_exists on new elements in fixpoint iteration *)
let pNEW_INFO_OPT = ref true
(* Filter the result of the label function to drop entries that aren't
compatible with any of the available environments *)
let pREQUIRED_ENV_OPT = ref true
(* Memoize the raw result of the label function *)
let pSATLABEL_MEMO_OPT = ref true
(* Filter results according to the required states *)
let pREQUIRED_STATES_OPT = ref true
(* Drop negative witnesses at Uncheck *)
let pUNCHECK_OPT = ref true

let inc cell = cell := !cell + 1

let satEU_calls = ref 0
let satAW_calls = ref 0
let satAU_calls = ref 0
let satEF_calls = ref 0
let satAF_calls = ref 0
let satEG_calls = ref 0
let satAG_calls = ref 0

let triples = ref 0

let ctr = ref 0
let new_let _ =
  let c = !ctr in
  ctr := c + 1;
  Printf.sprintf "_fresh_r_%d" c

(* **********************************************************************
 *
 * Implementation of a Witness Tree model checking engine for CTL-FVex 
 * 
 *
 * $Id$
 *
 * **********************************************************************)

(* ********************************************************************** *)
(* Module: SUBST (substitutions: meta. vars and values)                   *)
(* ********************************************************************** *)

module type SUBST =
  sig
    type value
    type mvar
    val eq_mvar: mvar -> mvar -> bool
    val eq_val: value -> value -> bool
    val merge_val: value -> value -> value
    val print_mvar : mvar -> unit
    val print_value : value -> unit
  end
;;

(* ********************************************************************** *)
(* Module: GRAPH (control flow graphs / model)                            *)
(* ********************************************************************** *)

module type GRAPH =
  sig
    type node
    type cfg
    val predecessors: cfg -> node -> node list
    val successors:    cfg -> node -> node list
    val print_node : node -> unit
  end
;;

module OGRAPHEXT_GRAPH = 
  struct
    type node = int;;
    type cfg = (string,unit) Ograph_extended.ograph_extended;;
    let predecessors cfg n = List.map fst ((cfg#predecessors n)#tolist);;
    let print_node i = Format.print_string (Common.i_to_s i)
  end
;;

(* ********************************************************************** *)
(* Module: PREDICATE (predicates for CTL formulae)                        *)
(* ********************************************************************** *)

module type PREDICATE =
sig
  type t
  val print_predicate : t -> unit
end


(* ********************************************************************** *)

(* ---------------------------------------------------------------------- *)
(* Misc. useful generic functions                                         *)
(* ---------------------------------------------------------------------- *)

let head = List.hd

let tail l = 
  match l with
    [] -> []
  | (x::xs) -> xs
;;

let foldl = List.fold_left;;

let foldl1 f xs = foldl f (head xs) (tail xs)

type 'a esc = ESC of 'a | CONT of 'a

let foldr = List.fold_right;;

let concat = List.concat;;

let map = List.map;;

let filter = List.filter;;

let partition = List.partition;;

let concatmap f l = List.concat (List.map f l);;

let maybe f g opt =
  match opt with
    | None -> g
    | Some x -> f x
;;

let some_map f opts = map (maybe (fun x -> Some (f x)) None) opts

let some_tolist_alt opts = concatmap (maybe (fun x -> [x]) []) opts

let rec some_tolist opts =
  match opts with
    | []             -> []
    | (Some x)::rest -> x::(some_tolist rest)
    | _::rest        -> some_tolist rest 
;;

let rec groupBy eq l =
    match l with
      [] -> []
    | (x::xs) -> 
	let (xs1,xs2) = partition (fun x' -> eq x x') xs in
	(x::xs1)::(groupBy eq xs2)
;;

let group l = groupBy (=) l;;

let rec memBy eq x l =
  match l with
    [] -> false
  | (y::ys) -> if (eq x y) then true else (memBy eq x ys)
;;

let rec nubBy eq ls =
  match ls with
    [] -> []
  | (x::xs) when (memBy eq x xs) -> nubBy eq xs
  | (x::xs) -> x::(nubBy eq xs)
;;

let rec nub ls =
  match ls with
    [] -> []
  | (x::xs) when (List.mem x xs) -> nub xs
  | (x::xs) -> x::(nub xs)
;;

let state_compare (s1,_,_) (s2,_,_) = compare s1 s2

let setifyBy eq xs = nubBy eq xs;;

let setify xs = nub xs;;

let inner_setify xs = List.sort compare (nub xs);;

let unionBy compare eq xs = function
    [] -> xs
  | ys ->
      let rec loop = function
	  [] -> ys
	| x::xs -> if memBy eq x ys then loop xs else x::(loop xs) in
      List.sort compare (loop xs)
;;

let union xs ys = unionBy state_compare (=) xs ys;;

let setdiff xs ys = filter (fun x -> not (List.mem x ys)) xs;;

let subseteqBy eq xs ys = List.for_all (fun x -> memBy eq x ys) xs;;

let subseteq xs ys = List.for_all (fun x -> List.mem x ys) xs;;
let supseteq xs ys = subseteq ys xs

let setequalBy eq xs ys = (subseteqBy eq xs ys) & (subseteqBy eq ys xs);;

let setequal xs ys = (subseteq xs ys) & (subseteq ys xs);;

(* Fix point calculation *)
let rec fix eq f x =
  let x' = f x in if (eq x' x) then x' else fix eq f x'
;;

(* Fix point calculation on set-valued functions *)
let setfix f x = (fix subseteq f x) (*if new is a subset of old, stop*)
let setgfix f x = (fix supseteq f x) (*if new is a supset of old, stop*)

(* ********************************************************************** *)
(* Module: CTL_ENGINE                                                     *)
(* ********************************************************************** *)

module CTL_ENGINE =
  functor (SUB : SUBST) -> 
    functor (G : GRAPH) ->
      functor (P : PREDICATE) ->
struct

module A = Ast_ctl

type substitution = (SUB.mvar, SUB.value) Ast_ctl.generic_substitution

type ('pred,'anno) witness =
    (G.node, substitution,
     ('pred, SUB.mvar, 'anno) Ast_ctl.generic_ctl list)
      Ast_ctl.generic_witnesstree

type ('pred,'anno) triples =
    (G.node * substitution * ('pred,'anno) witness list) list

(* ---------------------------------------------------------------------- *)
(* Pretty printing functions *)
(* ---------------------------------------------------------------------- *)

let (print_generic_substitution : substitution -> unit) = fun substxs ->
  let print_generic_subst = function
      A.Subst (mvar, v) ->
	SUB.print_mvar mvar; Format.print_string " --> "; SUB.print_value v
    | A.NegSubst (mvar, v) -> 
	SUB.print_mvar mvar; Format.print_string " -/-> "; SUB.print_value v in
  Format.print_string "[";
  Common.print_between (fun () -> Format.print_string ";" )
    print_generic_subst substxs;
  Format.print_string "]"

let rec (print_generic_witness: ('pred, 'anno) witness -> unit) =
  function
  | A.Wit (state, subst, anno, childrens) -> 
      Format.print_string "wit ";
      G.print_node state;
      print_generic_substitution subst;
      (match childrens with
	[] -> Format.print_string "{}"
      |	_ -> 
	  Format.force_newline(); Format.print_string "   "; Format.open_box 0;
	  print_generic_witnesstree childrens; Format.close_box())
  | A.NegWit  (state, subst, anno, childrens) -> 
      Format.print_string "!";
      print_generic_witness(A.Wit  (state, subst, anno, childrens))

and (print_generic_witnesstree: ('pred,'anno) witness list -> unit) =
  fun witnesstree ->
    Format.open_box 1;
    Format.print_string "{";
    Common.print_between
      (fun () -> Format.print_string ";"; Format.force_newline() ) 
      print_generic_witness witnesstree;
    Format.print_string "}";
    Format.close_box()
      
and print_generic_triple (node,subst,tree) =
  G.print_node node;
  print_generic_substitution subst;
  print_generic_witnesstree tree

and (print_generic_algo : ('pred,'anno) triples -> unit) = fun xs -> 
  Format.print_string "<";
  Common.print_between
    (fun () -> Format.print_string ";"; Format.force_newline())
    print_generic_triple xs;
  Format.print_string ">"
;;

let print_state (str : string) (l : ('pred,'anno) triples) =
  Printf.printf "%s\n" str;
  List.iter (function x ->
    print_generic_triple x; Format.print_newline(); flush stdout)
    (List.sort compare l);
  Printf.printf "\n"
    
let print_required_states = function
    None -> Printf.printf "no required states\n"
  | Some states ->
      Printf.printf "required states: ";
      List.iter
	(function x ->
	  G.print_node x; Format.print_string " "; Format.print_flush())
	states;
      Printf.printf "\n"

let mkstates states = function
    None -> states
  | Some states -> states
    
(* ---------------------------------------------------------------------- *)
(*                                                                        *)
(* ---------------------------------------------------------------------- *)
    
    
(* ************************* *)
(* Substitutions             *)
(* ************************* *)
    
let dom_sub sub =
  match sub with
  | A.Subst(x,_)    -> x
  | A.NegSubst(x,_) -> x
;;
	
let ran_sub sub =
  match sub with
  | A.Subst(_,x)    -> x
  | A.NegSubst(_,x) -> x
;;
	
let eq_subBy eqx eqv sub sub' =
  match (sub,sub') with 
    | (A.Subst(x,v),A.Subst(x',v'))       -> (eqx x x') && (eqv v v')
    | (A.NegSubst(x,v),A.NegSubst(x',v')) -> (eqx x x') && (eqv v v')
    | _                               -> false
;;

(* NOTE: functor *)
let eq_sub sub sub' = eq_subBy SUB.eq_mvar SUB.eq_val sub sub'

let eq_subst th th' = setequalBy eq_sub th th';;

let merge_subBy eqx (===) (>+<) sub sub' =
  if eqx (dom_sub sub) (dom_sub sub')
  then
    match (sub,sub') with
      (A.Subst (x,v),A.Subst (x',v')) -> 
	if (v === v')
	then Some [A.Subst(x, v >+< v')]
	else None
    | (A.NegSubst(x,v),A.Subst(x',v')) ->
	if (not (v === v'))
	then Some [A.Subst(x',v')]
	else None
    | (A.Subst(x,v),A.NegSubst(x',v')) ->
	if (not (v === v'))
	then Some [A.Subst(x,v)]
	else None
    | (A.NegSubst(x,v),A.NegSubst(x',v')) ->
	if (v === v')
	then Some [A.NegSubst(x,v)]
	else Some [A.NegSubst(x,v);A.NegSubst(x',v')]
  else Some [sub;sub']
;;

(* NOTE: functor *)
let merge_sub sub sub' = 
  merge_subBy SUB.eq_mvar SUB.eq_val SUB.merge_val sub sub'

let clean_substBy eq cmp theta = List.sort cmp (nubBy eq theta);;

(* NOTE: we sort by using the generic "compare" on (meta-)variable
 *   names; we could also require a definition of compare for meta-variables 
 *   or substitutions but that seems like overkill for sorting
 *)
let clean_subst theta = 
  let res = 
    clean_substBy eq_sub
      (fun s s' ->
	let res = compare (dom_sub s) (dom_sub s') in
	if res = 0
	then
	  match (s,s') with
	    (A.Subst(_,_),A.NegSubst(_,_)) -> -1
	  | (A.NegSubst(_,_),A.Subst(_,_)) -> 1
	  | _ -> compare (ran_sub s) (ran_sub s')
	else res)
      theta in
  let rec loop = function
      [] -> []
    | (A.Subst(x,v)::A.NegSubst(y,v')::rest) when SUB.eq_mvar x y ->
	loop (A.Subst(x,v)::rest)
    | x::xs -> x::(loop xs) in
  loop res

let top_subst = [];;			(* Always TRUE subst. *)

(* Split a theta in two parts: one with (only) "x" and one without *)
(* NOTE: functor *)
let split_subst theta x = 
  partition (fun sub -> SUB.eq_mvar (dom_sub sub) x) theta;;

exception SUBST_MISMATCH
let conj_subst theta theta' =
  match (theta,theta') with
    | ([],_) -> Some theta'
    | (_,[]) -> Some theta
    | _ ->
	try
	  Some (clean_subst (
		  foldl
		    (function rest ->
		       function sub ->
			 foldl
			   (function rest ->
			      function sub' ->
				match (merge_sub sub sub') with
				  | Some subs -> 
				      subs @ rest
				  | _       -> raise SUBST_MISMATCH)
			   rest theta')
		    [] theta))
	with SUBST_MISMATCH -> None
;;


let negate_sub sub =
  match sub with
    | A.Subst(x,v)    -> A.NegSubst (x,v)
    | A.NegSubst(x,v) -> A.Subst(x,v)
;;

(* Turn a (big) theta into a list of (small) thetas *)
let negate_subst theta = (map (fun sub -> [negate_sub sub]) theta);;


(* ************************* *)
(* Witnesses                 *)
(* ************************* *)

(* Always TRUE witness *)
let top_wit = ([] : (('pred, 'anno) witness list));;

let eq_wit wit wit' = wit = wit';;

let union_wit wit wit' = unionBy compare (=) wit wit';;

let negate_wit wit =
  match wit with
    | A.Wit(s,th,anno,ws)    -> A.NegWit(s,th,anno,ws)
    | A.NegWit(s,th,anno,ws) -> A.Wit(s,th,anno,ws)
;;

let negate_wits wits =
  List.sort compare (map (fun wit -> [negate_wit wit]) wits);;


(* ************************* *)
(* Triples                   *)
(* ************************* *)

(* Triples are equal when the constituents are equal *)
let eq_trip (s,th,wit) (s',th',wit') =
  (s = s') && (eq_wit wit wit') && (eq_subst th th');;

let triples_top states = map (fun s -> (s,top_subst,top_wit)) states;;

let triples_conj trips trips' =
  let (trips,shared,trips') =
    if !pTRIPLES_CONJ_OPT
    then
      let (shared,trips) =
	List.partition (function t -> List.mem t trips') trips in
      let trips' =
	List.filter (function t -> not(List.mem t shared)) trips' in
      (trips,shared,trips')
    else (trips,[],trips') in
  foldl (* returns a set - setify inlined *)
    (function rest ->
      function (s1,th1,wit1) ->
	foldl
	  (function rest ->
	    function (s2,th2,wit2) ->
	      if (s1 = s2) then
		(match (conj_subst th1 th2) with
		  Some th ->
		    let t = (s1,th,union_wit wit1 wit2) in
		    if List.mem t rest then rest else t::rest
		| _       -> rest)
	      else rest)
	  rest trips')
    shared trips
;;


(* *************************** *)
(* NEGATION (NegState style)   *)
(* *************************** *)

(* Constructive negation at the state level *)
type ('a) state =
    PosState of 'a
  | NegState of 'a list
;;

let compatible_states = function
    (PosState s1, PosState s2) -> 
      if s1 = s2 then Some (PosState s1) else None
  | (PosState s1, NegState s2) -> 
      if List.mem s1 s2 then None else Some (PosState s1)
  | (NegState s1, PosState s2) -> 
      if List.mem s2 s1 then None else Some (PosState s2)
  | (NegState s1, NegState s2) -> Some (NegState (s1 @ s2))
;;

(* Conjunction on triples with "special states" *)
let triples_state_conj trips trips' =
  let (trips,shared,trips') =
    if !pTRIPLES_CONJ_OPT
    then
      let (shared,trips) =
	List.partition (function t -> List.mem t trips') trips in
      let trips' =
	List.filter (function t -> not(List.mem t shared)) trips' in
      (trips,shared,trips')
    else (trips,[],trips') in
  foldl
    (function rest ->
      function (s1,th1,wit1) ->
	foldl
	  (function rest ->
	    function (s2,th2,wit2) ->
	      match compatible_states(s1,s2) with
		Some s ->
		  (match (conj_subst th1 th2) with
		    Some th ->
		      let t = (s,th,union_wit wit1 wit2) in
		      if List.mem t rest then rest else t::rest
		  | _ -> rest)
	      | _ -> rest)
	  rest trips')
    shared trips
;;

let triple_negate (s,th,wits) = 
  let negstates = (NegState [s],top_subst,top_wit) in
  let negths = map (fun th -> (PosState s,th,top_wit)) (negate_subst th) in
  let negwits = map (fun nwit -> (PosState s,th,nwit)) (negate_wits wits) in
    negstates :: (negths @ negwits) (* all different *)

(* FIX ME: it is not necessary to do full conjunction *)
let triples_complement states (trips : ('pred, 'anno) triples) =
  if !pTRIPLES_COMPLEMENT_OPT
  then
    (let cleanup (s,th,wit) =
      match s with
	PosState s' -> [(s',th,wit)]
      | NegState ss ->
	  assert (th=top_subst);
	  assert (wit=top_wit);
	  map (fun st -> (st,top_subst,top_wit)) (setdiff states ss) in
    let (simple,complex) =
      if !pTRIPLES_COMPLEMENT_SIMPLE_OPT
      then
	let (simple,complex) =
	  List.partition (function (s,[],[]) -> true | _ -> false) trips in
	let simple =
	  [(NegState(List.map (function (s,_,_) -> s) simple),
	    top_subst,top_wit)] in
	(simple,complex)
      else ([(NegState [],top_subst,top_wit)],trips) in
    let rec compl trips =
      match trips with
	[] -> simple
      | (t::ts) -> triples_state_conj (triple_negate t) (compl ts) in
    let compld = (compl complex) in
    print_state "trips" trips;
    let compld = concatmap cleanup compld in
    print_state "compld" compld;
    compld)
  else
    let negstates (st,th,wits) =
      map (function st -> (st,top_subst,top_wit)) (setdiff states [st]) in
    let negths (st,th,wits) =
      map (function th -> (st,th,top_wit)) (negate_subst th) in
    let negwits (st,th,wits) =
      map (function nwit -> (st,th,nwit)) (negate_wits wits) in
    match trips with
      [] -> map (function st -> (st,top_subst,top_wit)) states
    | x::xs ->
	setify
	  (foldl
	     (function prev ->
	       function cur ->
		 triples_conj (negstates cur @ negths cur @ negwits cur) prev)
	     (negstates x @ negths x @ negwits x) xs)
;;

let triple_negate (s,th,wits) = 
  let negths = map (fun th -> (s,th,top_wit)) (negate_subst th) in
  let negwits = map (fun nwit -> (s,th,nwit)) (negate_wits wits) in
  ([s], negths @ negwits) (* all different *)

let print_compl_state str (n,p) =
  Printf.printf "%s neg: " str;
  List.iter
    (function x -> G.print_node x; Format.print_flush(); Printf.printf " ")
    n;
  Printf.printf "\n";
  print_state "pos" p

let triples_complement states (trips : ('pred, 'anno) triples) =
  if trips = []
  then map (function st -> (st,top_subst,top_wit)) states
  else
    let cleanup (neg,pos) =
      let keep_pos =
	List.filter (function (s,_,_) -> List.mem s neg) pos in
      (map (fun st -> (st,top_subst,top_wit)) (setdiff states neg)) @
      keep_pos in
    let trips = List.sort state_compare trips in
    let all_negated = List.map triple_negate trips in
    let merge_one (neg1,pos1) (neg2,pos2) =
      let (pos1conj,pos1keep) =
	List.partition (function (s,_,_) -> List.mem s neg2) pos1 in
      let (pos2conj,pos2keep) =
	List.partition (function (s,_,_) -> List.mem s neg1) pos2 in
      (Common.union_set neg1 neg2,
       (triples_conj pos1conj pos2conj) @ pos1keep @ pos2keep) in
    let rec inner_loop = function
	x1::x2::rest -> (merge_one x1 x2) :: (inner_loop rest)
      | l -> l in
    let rec outer_loop = function
	[x] -> x
      | l -> outer_loop (inner_loop l) in
    cleanup (outer_loop all_negated)

(* ********************************** *)
(* END OF NEGATION (NegState style)   *)
(* ********************************** *)
      
let triples_union trips trips' =
  (*unionBy compare eq_trip trips trips';;*)
  (* returns -1 is t1 > t2, 1 if t2 >= t1, and 0 otherwise *)
    if !pNEW_INFO_OPT
    then
      if trips = trips'
      then trips
      else
	let subsumes (s1,th1,wit1) (s2,th2,wit2) =
	  if s1 = s2
	  then
	    (match conj_subst th1 th2 with
	      Some conj ->
		if conj = th1
		then if subseteq wit2 wit1 then 1 else 0
		else
		  if conj = th2
		  then if subseteq wit1 wit2 then (-1) else 0
		  else 0
	    | None -> 0)
	  else 0 in
	let rec first_loop second = function
	    [] -> second
	  | x::xs -> first_loop (second_loop x second) xs
	and second_loop x = function
	    [] -> [x]
	  | (y::ys) as all ->
	      match subsumes x y with
		1 -> all
	      | (-1) -> second_loop x ys
	      | _ -> y::(second_loop x ys) in
	first_loop trips trips'
    else unionBy compare eq_trip trips trips'

let triples_witness x unchecked trips = 
    let mkwit ((s,th,wit) as t) =
      let (th_x,newth) = split_subst th x in
      if th_x = []
      then
	(SUB.print_mvar x; Format.print_flush();
	 print_state ": empty witness from" [(s,th,wit)];
	 t)
      else
	if unchecked
	then (s,newth,wit)
	else (s,newth,[A.Wit(s,th_x,[],wit)]) in	(* [] = annotation *)
  (* not sure that nub is needed here.  would require empty witness case to
     make a duplicate. *)
  (* setify not needed in checked case - set before implies set after *)
    if unchecked then setify(map mkwit trips) else map mkwit trips
;;



(* ---------------------------------------------------------------------- *)
(* SAT  - Model Checking Algorithm for CTL-FVex                           *)
(*                                                                        *)
(* TODO: Implement _all_ operators (directly)                             *)
(* ---------------------------------------------------------------------- *)


(* ************************************* *)
(* The SAT algorithm and special helpers *)
(* ************************************* *)

let rec pre_exist dir (grp,_,_) y reqst =
  let check s =
    match reqst with None -> true | Some reqst -> List.mem s reqst in
  let exp (s,th,wit) =
    concatmap
      (fun s' -> if check s' then [(s',th,wit)] else [])
      (match dir with
	A.FORWARD -> G.predecessors grp s
      | A.BACKWARD -> G.successors grp s) in
  setify (concatmap exp y)
;;

exception Empty

let pre_forall dir (grp,_,states) y all reqst =
  let check s =
    match reqst with
      None -> true | Some reqst -> List.mem s reqst in
  let pred =
    match dir with
      A.FORWARD -> G.predecessors | A.BACKWARD -> G.successors in
  let succ =
    match dir with
      A.FORWARD -> G.successors | A.BACKWARD -> G.predecessors in
  let neighbors =
    List.map
      (function p -> (p,succ grp p))
      (setify
	 (concatmap
	    (function (s,_,_) -> List.filter check (pred grp s)) y)) in
  let all = List.sort state_compare all in
  let rec up_nodes child s = function
      [] -> []
    | (s1,th,wit)::xs ->
	(match compare s1 child with
	  -1 -> up_nodes child s xs
	| 0 -> (s,th,wit)::(up_nodes child s xs)
	| _ -> []) in
  let neighbor_triples =
    List.fold_left
      (function rest ->
	function (s,children) ->
	  try
	    (List.map
	       (function child ->
		 match up_nodes child s all with [] -> raise Empty | l -> l)
	       children) :: rest
	  with Empty -> rest)
      [] neighbors in
  match neighbor_triples with
    [] -> []
  | _ -> foldl1 (@) (List.map (foldl1 triples_conj) neighbor_triples)
	
(* drop_negwits will call setify *)
let satEX dir m s reqst = pre_exist dir m s reqst;;
    
let satAX dir m s reqst = pre_forall dir m s s reqst
;;

(* E[phi1 U phi2] == phi2 \/ (phi1 /\ EXE[phi1 U phi2]) *)
let satEU dir ((_,_,states) as m) s1 s2 reqst = 
  inc satEU_calls;
  if s1 = []
  then s2
  else
    let ctr = ref 0 in
    if !pNEW_INFO_OPT
    then
      let rec f y new_info =
	match new_info with
	  [] -> y
	| new_info ->
	    ctr := !ctr + 1;
	    let first = triples_conj s1 (pre_exist dir m new_info reqst) in
	    let res = triples_union first y in
	    let new_info = setdiff res y in
	    (*Printf.printf "iter %d res %d new_info %d\n"
	    !ctr (List.length res) (List.length new_info);
	    flush stdout;*)
	    f res new_info in
      f s2 s2
    else
      let f y =
	let pre = pre_exist dir m y reqst in
	triples_union s2 (triples_conj s1 pre) in
      setfix f s2
;;

(* EF phi == E[true U phi] *)
let satEF dir m s2 reqst = 
  inc satEF_calls;
  (*let ctr = ref 0 in*)
  if !pNEW_INFO_OPT
  then
    let rec f y new_info =
      match new_info with
	[] -> y
      | new_info ->
	  (*ctr := !ctr + 1;
	  print_state (Printf.sprintf "iteration %d\n" !ctr) y;*)
	  let first = pre_exist dir m new_info reqst in
	  let res = triples_union first y in
	  let new_info = setdiff res y in
	  (*Printf.printf "EF %s iter %d res %d new_info %d\n"
	    (if dir = A.BACKWARD then "reachable" else "real ef")
	    !ctr (List.length res) (List.length new_info);
	  print_state "new info" new_info;
	  flush stdout;*)
	  f res new_info in
    f s2 s2
  else
    let f y =
      let pre = pre_exist dir m y reqst in
      triples_union s2 pre in
    setfix f s2
      
(* A[phi1 U phi2] == phi2 \/ (phi1 /\ AXA[phi1 U phi2]) *)
let satAU dir ((_,_,states) as m) s1 s2 reqst =
  inc satAU_calls;
  if s1 = []
  then s2
  else
    (*let ctr = ref 0 in*)
    if !pNEW_INFO_OPT
    then
    let rec f y newinfo =
      match newinfo with
	[] -> y
      | new_info ->
	  (*ctr := !ctr + 1;
	  print_state (Printf.sprintf "iteration %d\n" !ctr) y;*)
	  let first = triples_conj s1 (pre_forall dir m new_info y reqst) in
	  let res = triples_union first y in
	  let new_info = setdiff res y in
	  (*Printf.printf "iter %d res %d new_info %d\n"
	  !ctr (List.length res) (List.length new_info);
	  flush stdout;*)
	  f res new_info in
    f s2 s2
    else
      let f y =
	let pre = pre_forall dir m y y reqst in
	triples_union s2 (triples_conj s1 pre) in
      setfix f s2
;;

let all_table =
  (Hashtbl.create(50) : (G.node,('a,'b) triples ref) Hashtbl.t)


(* reqst could be the states of s1 *)
      (*
      let lstates = mkstates states reqst in
      let initial_removed =
	triples_complement lstates (triples_union s1 s2) in
      let initial_base = triples_conj s1 (triples_complement lstates s2) in
      let rec loop base removed =
	let new_removed =
	  triples_conj base (pre_exist dir m removed reqst) in
	let new_base =
	  triples_conj base (triples_complement lstates new_removed) in
	if supseteq new_base base
	then triples_union base s2
	else loop new_base new_removed in
      loop initial_base initial_removed *)

let satAW dir ((grp,_,states) as m) s1 s2 reqst =
  inc satAW_calls;
  if s1 = []
  then s2
  else
    (*
       This works extremely badly when the region is small and the end of the
       region is very ambiguous, eg free(x) ... x
       see free.c
    if !pNEW_INFO_OPT
    then
      let get_states l = setify(List.map (function (s,_,_) -> s) l) in
      let ostates = Common.union_set (get_states s1) (get_states s2) in
      let succ =
	(match dir with
	  A.FORWARD -> G.successors grp
	| A.BACKWARD -> G.predecessors grp) in
      let states =
	List.fold_left Common.union_set ostates (List.map succ ostates) in
      let negphi = triples_complement states s1 in
      let negpsi = triples_complement states s2 in
      triples_complement ostates
	(satEU dir m negpsi (triples_conj negphi negpsi) (Some ostates))
    else
       *)
      (*let ctr = ref 0 in*)
      let f y =
	(*ctr := !ctr + 1;
	Printf.printf "iter %d y %d\n" !ctr (List.length y);*)
	flush stdout;
	let pre = pre_forall dir m y y reqst in
	let conj = triples_conj s1 pre in (* or triples_conj_AW *)
	triples_union s2 conj in
      setgfix f (triples_union s1 s2)
;;

let satAF dir m s reqst = 
  inc satAF_calls;
  if !pNEW_INFO_OPT
  then
    let rec f y newinfo =
      match newinfo with
	[] -> y
      | new_info ->
	  let first = pre_forall dir m new_info y reqst in
	  let res = triples_union first y in
	  let new_info = setdiff res y in
	  f res new_info in
    f s s
  else
    let f y =
      let pre = pre_forall dir m y y reqst in
      triples_union s pre in
    setfix f s

let satAG dir ((_,_,states) as m) s reqst =
  inc satAG_calls;
  let f y =
    let pre = pre_forall dir m y y reqst in
    triples_conj y pre in
  setgfix f s

let satEG dir ((_,_,states) as m) s reqst =
  inc satEG_calls;
  let f y =
    let pre = pre_exist dir m y reqst in
    triples_conj y pre in
  setgfix f s

(* can't drop witnesses under a negation, because eg (1,X=2,[Y=3]) contains
info other than the witness *)
let drop_wits required_states s phi =
  match required_states with
    None -> s
  | Some states -> List.filter (function (s,_,_) -> List.mem s states) s


(* ********************* *)
(* Environment functions *)
(* ********************* *)

let extend_required trips required =
  if !pREQUIRED_ENV_OPT
  then
    let envs =
      List.fold_left
	(function rest ->
	  function (_,t,_) -> if List.mem t rest then rest else t::rest)
	[] trips in
    if List.length envs > 10 then required else
    (let add x y = if List.mem x y then y else x::y in
    foldl
      (function rest ->
	function t ->
	  foldl
	    (function rest ->
	      function r ->
		match conj_subst t r with
		  None -> rest | Some th -> add th rest)
	    rest required)
      [] envs)
  else required

let drop_required v required =
  if !pREQUIRED_ENV_OPT
  then
    inner_setify
      (List.map (List.filter (function sub -> not(dom_sub sub = v))) required)
  else required

let print_required required =
  Printf.printf "required\n";
  List.iter
    (function reqd -> print_generic_substitution reqd; Format.print_newline())
    required

(* no idea how to write this function ... *)
let memo_label =
  (Hashtbl.create(50) : (P.t, (G.node * substitution) list) Hashtbl.t)

let satLabel label required p =
  let triples =
    if !pSATLABEL_MEMO_OPT
    then
      try
	let states_subs = Hashtbl.find memo_label p in
	List.map (function (st,th) -> (st,th,[])) states_subs
      with
	Not_found ->
	  let triples = setify(label p) in
	  Hashtbl.add memo_label p
	    (List.map (function (st,th,_) -> (st,th)) triples);
	  triples
    else setify(label p) in
  if !pREQUIRED_ENV_OPT
  then
    (foldl
      (function rest ->
	function ((s,th,_) as t) ->
	  if List.exists (function th' -> not(conj_subst th th' = None))
	      required
	  then t::rest
	  else rest)
      [] triples)
  else triples

let get_required_states l =
  if !pREQUIRED_STATES_OPT
  then
    Some(inner_setify (List.map (function (s,_,_) -> s) l))
  else None

let get_children_required_states dir (grp,_,_) required_states =
  if !pREQUIRED_STATES_OPT
  then
    match required_states with
      None -> None
    | Some states ->
	let fn =
	  match dir with
	    A.FORWARD -> G.successors
	  | A.BACKWARD -> G.predecessors in
	Some (inner_setify (List.concat (List.map (fn grp) states)))
  else None

let reachable_table =
  (Hashtbl.create(50) : (G.node * A.direction, G.node list) Hashtbl.t)

(* like satEF, but specialized for get_reachable *)
let reachsatEF dir (grp,_,_) s2 =
  let dirop =
    match dir with A.FORWARD -> G.successors | A.BACKWARD -> G.predecessors in
  let union = unionBy compare (=) in
  let rec f y = function
      [] -> y
    | new_info ->
	let (pre_collected,new_info) =
	  List.partition (function Common.Left x -> true | _ -> false)
	    (List.map
	       (function x ->
		 try Common.Left (Hashtbl.find reachable_table (x,dir))
		 with Not_found -> Common.Right x)
	       new_info) in
	let y =
	  List.fold_left
	    (function rest ->
	      function Common.Left x -> union x rest
		| _ -> failwith "not possible")
	    y pre_collected in
	let new_info =
	  List.map
	    (function Common.Right x -> x | _ -> failwith "not possible")
	    new_info in
	let first = inner_setify (concatmap (dirop grp) new_info) in
	let new_info = setdiff first y in
	let res = new_info @ y in
	f res new_info in
  List.rev(f s2 s2) (* put root first *)

let get_reachable dir m required_states =
  match required_states with
    None -> None
  | Some states ->
      Some
	(List.fold_left
	   (function rest ->
	     function cur ->
	       if List.mem cur rest
	       then rest
	       else
		 Common.union_set
		   (try Hashtbl.find reachable_table (cur,dir)
		   with
		     Not_found ->
		       let states = reachsatEF dir m [cur] in
		       Hashtbl.add reachable_table (cur,dir) states;
		       states)
		   rest)
	   [] states)

let ctr = ref 0
let new_var _ =
  let c = !ctr in
  ctr := !ctr + 1;
  Printf.sprintf "_c%d" c

(* **************************** *)
(* End of environment functions *)
(* **************************** *)

type ('code,'value) cell = Frozen of 'code | Thawed of 'value

let rec satloop unchecked required required_states
    ((grp,label,states) as m) phi env
    check_conj =
  let rec loop unchecked required required_states phi =
    let res =
    match A.unwrap phi with
      A.False              -> []
    | A.True               -> triples_top states
    | A.Pred(p)            -> satLabel label required p
    | A.Uncheck(phi1) ->
	let unchecked = if !pUNCHECK_OPT then true else false in
	loop unchecked required required_states phi1
    | A.Not(phi)           ->
	triples_complement (mkstates states required_states)
	  (loop unchecked required required_states phi)
    | A.Or(phi1,phi2)      ->
	triples_union
	  (loop unchecked required required_states phi1)
	  (loop unchecked required required_states phi2)
    | A.SeqOr(phi1,phi2)      ->
	let res1 = loop unchecked required required_states phi1 in
	let res2 = loop unchecked required required_states phi2 in
	let res1neg =
	  setify(List.map (function (s,th,_) -> (s,th,[])) res1) in
	triples_union res1
	  (triples_conj
	     (triples_complement (mkstates states required_states) res1neg)
	     res2)
    | A.And(phi1,phi2)     ->
	(* phi1 is considered to be more likely to be [], because of the
	   definition of asttoctl.  Could use heuristics such as the size of
	   the term *)
	(match loop unchecked required required_states phi1 with
	  [] -> []
	| phi1res ->
	    let new_required = extend_required phi1res required in
	    let new_required_states = get_required_states phi1res in
	    (match loop unchecked new_required new_required_states phi2 with
	      [] -> []
	    | phi2res ->
		let res = triples_conj phi1res phi2res in
		check_conj phi phi1res phi2res res;
		res))
    | A.EX(dir,phi)      ->
	let new_required_states =
	  get_children_required_states dir m required_states in
	satEX dir m (loop unchecked required new_required_states phi)
	  required_states
    | A.AX(dir,phi)      ->
	let new_required_states =
	  get_children_required_states dir m required_states in
	satAX dir m (loop unchecked required new_required_states phi)
	  required_states
    | A.EF(dir,phi)            ->
	let new_required_states = get_reachable dir m required_states in
	satEF dir m (loop unchecked required new_required_states phi)
	  new_required_states
    | A.AF(dir,phi)            ->
	if !Flag_ctl.loop_in_src_code
	then
	  let tr = A.rewrap phi A.True in
	  loop unchecked required required_states
	    (A.rewrap phi (A.AU(dir,tr,phi)))
	else
	  let new_required_states = get_reachable dir m required_states in
	  satAF dir m (loop unchecked required new_required_states phi)
	    new_required_states
    | A.EG(dir,phi)            ->
	let new_required_states = get_reachable dir m required_states in
	satEG dir m (loop unchecked required new_required_states phi)
	  new_required_states
    | A.AG(dir,phi)            ->
	let new_required_states = get_reachable dir m required_states in
	satAG dir m (loop unchecked required new_required_states phi)
	  new_required_states
    | A.EU(dir,phi1,phi2)      ->
	let new_required_states = get_reachable dir m required_states in
	(match loop unchecked required new_required_states phi2 with
	  [] -> []
	| s2 ->
	    let new_required = extend_required s2 required in
	    let s1 = loop unchecked new_required new_required_states phi1 in
	    satEU dir m s1 s2 new_required_states)
    | A.AW(dir,phi1,phi2) ->
	let new_required_states = get_reachable dir m required_states in
	(match loop unchecked required new_required_states phi2 with
	  [] -> []
	| s2 ->
	    let new_required = extend_required s2 required in
	    satAW dir m
	      (loop unchecked new_required new_required_states phi1)
	      s2 new_required_states)
    | A.AU(dir,phi1,phi2) ->
	if !Flag_ctl.loop_in_src_code
	then
	  let wrap x = A.rewrap phi x in
	  let v = new_let () in
	  let w = new_let () in
	  let phi1ref = wrap(A.Ref v) in
	  let phi2ref = wrap(A.Ref w) in
	  loop unchecked required required_states
	    (wrap
	       (A.LetR
		  (dir,v,phi1,
		   (wrap
		      (A.LetR
			 (dir,w,phi2,
			  wrap
			    (A.AW
			       (dir,
				wrap
				  (A.And
				     (wrap(A.EU(dir,wrap(A.Uncheck(phi1ref)),
						wrap(A.Uncheck(phi2ref)))),
				      phi1ref)),
				phi2ref))))))))
	else
	  let new_required_states = get_reachable dir m required_states in
	  (match loop unchecked required new_required_states phi2 with
	    [] -> []
	  | s2 ->
	      let new_required = extend_required s2 required in
	      satAU dir m
		(loop unchecked new_required new_required_states phi1)
		s2 new_required_states)
    | A.Implies(phi1,phi2) ->
	loop unchecked required required_states
	  (A.rewrap phi (A.Or(A.rewrap phi (A.Not phi1),phi2)))
    | A.Exists (v,phi)     ->
	let new_required = drop_required v required in
	triples_witness v unchecked
	  (loop unchecked new_required required_states phi)
    | A.Let(v,phi1,phi2)   ->
	(* should only be used when the properties unchecked, required,
	   and required_states are known to be the same or at least
	   compatible between all the uses.  this is not checked. *)
	let res = loop unchecked required required_states phi1 in
	satloop unchecked required required_states m phi2 ((v,res) :: env)
	  check_conj
    | A.LetR(dir,v,phi1,phi2)   ->
	(* should only be used when the properties unchecked, required,
	   and required_states are known to be the same or at least
	   compatible between all the uses.  this is not checked. *)
	let new_required_states = get_reachable dir m required_states in
	let res = loop unchecked required new_required_states phi1 in
	satloop unchecked required required_states m phi2 ((v,res) :: env)
	  check_conj
    | A.Ref(v)             ->
	let res = List.assoc v env in
	if unchecked
	then List.map (function (s,th,_) -> (s,th,[])) res
	else res
    | A.Dots _ -> failwith "should not occur"
    | A.PDots _ -> failwith "should not occur" in
    if !Flag_ctl.bench > 0 then triples := !triples + (List.length res);
    drop_wits required_states res phi in
  
  loop unchecked required required_states phi
;;    


(* SAT with tracking *)
let rec sat_verbose_loop unchecked required required_states annot maxlvl lvl
    ((_,label,states) as m) phi env check_conj =
  let anno res children = (annot lvl phi res children,res) in
  let satv unchecked required required_states phi0 env =
    sat_verbose_loop unchecked required required_states annot maxlvl (lvl+1)
      m phi0 env check_conj in
  if (lvl > maxlvl) && (maxlvl > -1) then
    anno (satloop unchecked required required_states m phi env check_conj) []
  else
    let (child,res) =
      match A.unwrap phi with
      A.False              -> anno [] []
    | A.True               -> anno (triples_top states) []
    | A.Pred(p)            ->
	Printf.printf "label\n"; flush stdout;
	anno (satLabel label required p) []
    | A.Uncheck(phi1) ->
	let unchecked = if !pUNCHECK_OPT then true else false in
	let (child1,res1) = satv unchecked required required_states phi1 env in
	Printf.printf "uncheck\n"; flush stdout;
	anno res1 [child1]
    | A.Not(phi1)          -> 
	let (child,res) =
	  satv unchecked required required_states phi1 env in
	Printf.printf "not\n"; flush stdout;
	anno (triples_complement (mkstates states required_states) res) [child]
    | A.Or(phi1,phi2)      -> 
	let (child1,res1) =
	  satv unchecked required required_states phi1 env in
	let (child2,res2) =
	  satv unchecked required required_states phi2 env in
	Printf.printf "or\n"; flush stdout;
	anno (triples_union res1 res2) [child1; child2]
    | A.SeqOr(phi1,phi2)      -> 
	let (child1,res1) =
	  satv unchecked required required_states phi1 env in
	let (child2,res2) =
	  satv unchecked required required_states phi2 env in
	let res1neg =
	  List.map (function (s,th,_) -> (s,th,[])) res1 in
	Printf.printf "seqor\n"; flush stdout;
	anno (triples_union res1
		(triples_conj
		   (triples_complement (mkstates states required_states)
		      res1neg)
		   res2))
	  [child1; child2]
    | A.And(phi1,phi2)     -> 
	(match satv unchecked required required_states phi1 env with
	  (child1,[]) -> Printf.printf "and\n"; flush stdout; anno [] [child1]
	| (child1,res1) ->
	    let new_required = extend_required res1 required in
	    let new_required_states = get_required_states res1 in
	    (match satv unchecked new_required new_required_states phi2
		env with
	      (child2,[]) ->
		Printf.printf "and\n"; flush stdout; anno [] [child1;child2]
	    | (child2,res2) ->
		Printf.printf "and\n"; flush stdout;
		anno (triples_conj res1 res2) [child1; child2]))
    | A.EX(dir,phi1)       -> 
	let new_required_states =
	  get_children_required_states dir m required_states in
	let (child,res) =
	  satv unchecked required new_required_states phi1 env in
	Printf.printf "EX\n"; flush stdout;
	anno (satEX dir m res required_states) [child]
    | A.AX(dir,phi1)       -> 
	let new_required_states =
	  get_children_required_states dir m required_states in
	let (child,res) =
	  satv unchecked required new_required_states phi1 env in
	Printf.printf "AX\n"; flush stdout;
	anno (satAX dir m res required_states) [child]
    | A.EF(dir,phi1)       -> 
	let new_required_states = get_reachable dir m required_states in
	let (child,res) =
	  satv unchecked required new_required_states phi1 env in
	Printf.printf "EF\n"; flush stdout;
	anno (satEF dir m res new_required_states) [child]
    | A.AF(dir,phi1) -> 
	if !Flag_ctl.loop_in_src_code
	then
	  let tr = A.rewrap phi A.True in
	  satv unchecked required required_states
	    (A.rewrap phi (A.AU(dir,tr,phi1)))
	    env
	else
	  (let new_required_states = get_reachable dir m required_states in
	  let (child,res) =
	    satv unchecked required new_required_states phi1 env in
	  Printf.printf "AF\n"; flush stdout;
	  anno (satAF dir m res new_required_states) [child])
    | A.EG(dir,phi1)       -> 
	let new_required_states = get_reachable dir m required_states in
	let (child,res) =
	  satv unchecked required new_required_states phi1 env in
	Printf.printf "EG\n"; flush stdout;
	anno (satEG dir m res new_required_states) [child]
    | A.AG(dir,phi1)       -> 
	let new_required_states = get_reachable dir m required_states in
	let (child,res) =
	  satv unchecked required new_required_states phi1 env in
	Printf.printf "AG\n"; flush stdout;
	anno (satAG dir m res new_required_states) [child]
	  
    | A.EU(dir,phi1,phi2)  -> 
	let new_required_states = get_reachable dir m required_states in
	(match satv unchecked required new_required_states phi2 env with
	  (child2,[]) ->
	    Printf.printf "EU\n"; flush stdout;
	    anno [] [child2]
	| (child2,res2) ->
	    let new_required = extend_required res2 required in
	    let (child1,res1) =
	      satv unchecked new_required new_required_states phi1 env in
	    Printf.printf "EU\n"; flush stdout;
	    anno (satEU dir m res1 res2 new_required_states) [child1; child2])
    | A.AW(dir,phi1,phi2)      -> 
	  let new_required_states = get_reachable dir m required_states in
	  (match satv unchecked required new_required_states phi2 env with
	    (child2,[]) ->
	      Printf.printf "AW %b\n" unchecked; flush stdout; anno [] [child2]
	  | (child2,res2) ->
	      let new_required = extend_required res2 required in
	      let (child1,res1) =
		satv unchecked new_required new_required_states phi1 env in
	      Printf.printf "AW %b\n" unchecked; flush stdout;
	      anno (satAW dir m res1 res2 new_required_states)
		[child1; child2])
    | A.AU(dir,phi1,phi2)      -> 
	if !Flag_ctl.loop_in_src_code
	then
	  let wrap x = A.rewrap phi x in
	  let v = new_let () in
	  let w = new_let () in
	  let phi1ref = wrap(A.Ref v) in
	  let phi2ref = wrap(A.Ref w) in
	  satv unchecked required required_states
	    (wrap
	       (A.LetR
		  (dir,v,phi1,
		   (wrap
		      (A.LetR
			 (dir,w,phi2,
			  wrap
			    (A.AW
			       (dir,
				wrap
				  (A.And
				     (wrap(A.EU(dir,wrap(A.Uncheck(phi1ref)),
						wrap(A.Uncheck(phi2ref)))),
				      phi1ref)),
				phi2ref))))))))
	    env
	else
	  let new_required_states = get_reachable dir m required_states in
	  (match satv unchecked required new_required_states phi2 env with
	    (child2,[]) ->
	      Printf.printf "AU %b\n" unchecked; flush stdout; anno [] [child2]
	  | (child2,res2) ->
	      let new_required = extend_required res2 required in
	      let (child1,res1) =
		satv unchecked new_required new_required_states phi1 env in
	      Printf.printf "AU %b\n" unchecked; flush stdout;
	      anno (satAU dir m res1 res2 new_required_states)
		[child1; child2])
    | A.Implies(phi1,phi2) -> 
	satv unchecked required required_states
	  (A.rewrap phi (A.Or(A.rewrap phi (A.Not phi1),phi2)))
	  env
    | A.Exists (v,phi1)    -> 
	let new_required = drop_required v required in
	let (child,res) =
	  satv unchecked new_required required_states phi1 env in
	Printf.printf "exists\n"; flush stdout;
	anno (triples_witness v unchecked res) [child]
    | A.Let(v,phi1,phi2)   ->
	let (child1,res1) =
	  satv unchecked required required_states phi1 env in
	let (child2,res2) =
	  satv unchecked required required_states phi2 ((v,res1) :: env) in
	anno res2 [child1;child2]
    | A.LetR(dir,v,phi1,phi2)   ->
	let new_required_states = get_reachable dir m required_states in
	let (child1,res1) =
	  satv unchecked required new_required_states phi1 env in
	let (child2,res2) =
	  satv unchecked required required_states phi2 ((v,res1) :: env) in
	anno res2 [child1;child2]
    | A.Ref(v)             ->
	Printf.printf "Ref\n"; flush stdout;
	let res = List.assoc v env in
	let res =
	  if unchecked
	  then List.map (function (s,th,_) -> (s,th,[])) res
	  else res in
	anno res []
    | A.Dots _ -> failwith "should not occur"
    | A.PDots _ -> failwith "should not occur" in
    let res1 = drop_wits required_states res phi in
    if not(res1 = res) then print_state "after drop_wits" res1;
    (child,res1)
	
;;

let sat_verbose annotate maxlvl lvl m phi check_conj =
  sat_verbose_loop false [[]] None annotate maxlvl lvl m phi [] check_conj

(* Type for annotations collected in a tree *)
type ('a) witAnnoTree = WitAnno of ('a * ('a witAnnoTree) list);;

let sat_annotree annotate m phi check_conj =
  let tree_anno l phi res chld = WitAnno(annotate l phi res,chld) in
    sat_verbose_loop false [[]] None tree_anno (-1) 0 m phi [] check_conj
;;

(*
let sat m phi = satloop m phi []
;;
*)

let simpleanno l phi res =
  let pp s = 
    Format.print_string ("\n" ^ s ^ "\n------------------------------\n"); 
    print_generic_algo (List.sort compare res);
    Format.print_string "\n------------------------------\n\n" in
  let pp_dir = function
      A.FORWARD -> ()
    | A.BACKWARD -> pp "^" in
  match A.unwrap phi with
    | A.False              -> pp "False"
    | A.True               -> pp "True"
    | A.Pred(p)            -> pp ("Pred" ^ (Dumper.dump p))
    | A.Not(phi)           -> pp "Not"
    | A.Exists(v,phi)      -> pp ("Exists " ^ (Dumper.dump(v)))
    | A.And(phi1,phi2)     -> pp "And"
    | A.Or(phi1,phi2)      -> pp "Or"
    | A.SeqOr(phi1,phi2)   -> pp "SeqOr"
    | A.Implies(phi1,phi2) -> pp "Implies"
    | A.AF(dir,phi1)       -> pp "AF"; pp_dir dir
    | A.AX(dir,phi1)       -> pp "AX"; pp_dir dir
    | A.AG(dir,phi1)       -> pp "AG"; pp_dir dir
    | A.AW(dir,phi1,phi2)  -> pp "AW"; pp_dir dir
    | A.AU(dir,phi1,phi2)  -> pp "AU"; pp_dir dir
    | A.EF(dir,phi1)       -> pp "EF"; pp_dir dir
    | A.EX(dir,phi1)	   -> pp "EX"; pp_dir dir
    | A.EG(dir,phi1)	   -> pp "EG"; pp_dir dir
    | A.EU(dir,phi1,phi2)  -> pp "EU"; pp_dir dir
    | A.Let (x,phi1,phi2)  -> pp ("Let"^" "^x)
    | A.LetR (dir,x,phi1,phi2) -> pp ("LetR"^" "^x); pp_dir dir
    | A.Ref(s)             -> pp ("Ref("^s^")")
    | A.Uncheck(s)         -> pp "Uncheck"
    | A.Dots _ -> failwith "should not occur"
    | A.PDots _ -> failwith "should not occur"
;;


(* pad: Rene, you can now use the module pretty_print_ctl.ml to
   print a ctl formula more accurately if you want.
   Use the print_xxx provided in the different module to call 
   Pretty_print_ctl.pp_ctl.
 *)

let simpleanno2 l phi res = 
  begin
    Pretty_print_ctl.pp_ctl (P.print_predicate, SUB.print_mvar) false phi;
    Format.print_newline ();
    Format.print_string "----------------------------------------------------";
    Format.print_newline ();
    print_generic_algo (List.sort compare res);
    Format.print_newline ();
    Format.print_string "----------------------------------------------------";
    Format.print_newline ();
    Format.print_newline ();
  end


(* ---------------------------------------------------------------------- *)
(* Benchmarking                                                           *)
(* ---------------------------------------------------------------------- *)

type optentry = bool ref * string
type options = {label : optentry; unch : optentry;
		 conj : optentry; compl1 : optentry; compl2 : optentry;
		 newinfo : optentry;
		 reqenv : optentry; reqstates : optentry}

let options =
  {label = (pSATLABEL_MEMO_OPT,"satlabel_memo_opt");
    unch = (pUNCHECK_OPT,"uncheck_opt");
    conj = (pTRIPLES_CONJ_OPT,"triples_conj_opt");
    compl1 = (pTRIPLES_COMPLEMENT_OPT,"triples_complement_opt");
    compl2 = (pTRIPLES_COMPLEMENT_SIMPLE_OPT,"triples_complement_simple_opt");
    newinfo = (pNEW_INFO_OPT,"new_info_opt");
    reqenv = (pREQUIRED_ENV_OPT,"required_env_opt");
    reqstates = (pREQUIRED_STATES_OPT,"required_states_opt")}

let baseline =
  [("none                    ",[]);
    ("label                   ",[options.label]);
    ("unch                    ",[options.unch]);
    ("unch and label          ",[options.label;options.unch])]

let conjneg =
  [("conj                    ", [options.conj]);
    ("compl1                  ", [options.compl1]);
    ("compl12                 ", [options.compl1;options.compl2]);
    ("conj/compl12            ", [options.conj;options.compl1;options.compl2]);
    ("conj unch satl          ", [options.conj;options.unch;options.label]);
(*
    ("compl1 unch satl        ", [options.compl1;options.unch;options.label]);
    ("compl12 unch satl       ",
     [options.compl1;options.compl2;options.unch;options.label]); *)
    ("conj/compl12 unch satl  ",
     [options.conj;options.compl1;options.compl2;options.unch;options.label])]

let path =
  [("newinfo                 ", [options.newinfo]);
    ("newinfo unch satl       ", [options.newinfo;options.unch;options.label])]

let required =
  [("reqenv                  ", [options.reqenv]);
    ("reqstates               ", [options.reqstates]);
    ("reqenv/states           ", [options.reqenv;options.reqstates]);
(*  ("reqenv unch satl        ", [options.reqenv;options.unch;options.label]);
    ("reqstates unch satl     ",
     [options.reqstates;options.unch;options.label]);*)
    ("reqenv/states unch satl ",
     [options.reqenv;options.reqstates;options.unch;options.label])]

let all_options =
  [options.label;options.unch;options.conj;options.compl1;options.compl2;
    options.newinfo;options.reqenv;options.reqstates]

let all =
  [("all                     ",all_options)]

let all_options_but_path =
  [options.label;options.unch;options.conj;options.compl1;options.compl2;
    options.reqenv;options.reqstates]

let all_but_path = ("all but path            ",all_options_but_path)

let counters =
  [(satAW_calls, "satAW", ref 0);
    (satAU_calls, "satAU", ref 0);
    (satEF_calls, "satEF", ref 0);
    (satAF_calls, "satAF", ref 0);
    (satEG_calls, "satEG", ref 0);
    (satAG_calls, "satAG", ref 0);
  (satEU_calls, "satEU", ref 0)]

let perms =
  map
    (function (opt,x) ->
      (opt,x,ref 0.0,ref 0,
       List.map (function _ -> (ref 0, ref 0, ref 0)) counters))
    [List.hd all;all_but_path]
  (*(all@baseline@conjneg@path@required)*)

let drop_negwits s =
  let rec contains_negwits l =
    List.exists
      (function
	  A.NegWit(_,_,_,_) -> (* print_state "dropping a witness" s;*) true
	| A.Wit(_,_,_,w) -> contains_negwits w)
      l in
  setify (List.filter (function (s,th,wits) -> not(contains_negwits wits)) s)

exception Out

let rec iter fn = function
    1 -> fn()
  | n -> let _ = fn() in
    (Hashtbl.clear reachable_table;
     Hashtbl.clear memo_label;
     triples := 0;
     iter fn (n-1))

let copy_to_stderr fl =
  let i = open_in fl in
  let rec loop _ =
    Printf.fprintf stderr "%s\n" (input_line i);
    loop() in
  try loop() with _ -> ();
  close_in i

let bench_sat (_,_,states) fn =
  List.iter (function (opt,_) -> opt := false) all_options;
  let answers =
    concatmap
      (function (name,options,time,trips,counter_info) ->
	let iterct = !Flag_ctl.bench in
	if !time > float_of_int timeout then time := -100.0;
	if not (!time = -100.0)
	then
	  begin
	    Hashtbl.clear reachable_table;
	    Hashtbl.clear memo_label;
	    List.iter (function (opt,_) -> opt := true) options;
	    List.iter (function (calls,_,save_calls) -> save_calls := !calls)
	      counters;
	    triples := 0;
	    let res =
	      let bef = Sys.time() in
	      try
		Common.timeout_function timeout
		  (fun () ->
		    let bef = Sys.time() in
		    let res = iter fn iterct in
		    let aft = Sys.time() in
		    time := !time +. (aft -. bef);
		    trips := !trips + !triples;
		    List.iter2
		      (function (calls,_,save_calls) ->
			function (current_calls,current_cfg,current_max_cfg) ->
			  current_calls :=
			    !current_calls + (!calls - !save_calls);
			  if (!calls - !save_calls) > 0
			  then
			    (let st = List.length states in
			    current_cfg := !current_cfg + st;
			    if st > !current_max_cfg
			    then current_max_cfg := st))
		      counters counter_info;
		    [res])
	      with
		Common.Timeout ->
		  begin
		    let aft = Sys.time() in
		    time := -100.0;
		    Printf.fprintf stderr "Timeout at %f on: %s\n"
		      (aft -. bef) name;
		    []
		  end in
	    List.iter (function (opt,_) -> opt := false) options;
	    res
	  end
	else [])
      perms in
  Printf.fprintf stderr "\n";
  let answers = map (List.sort compare) (map drop_negwits answers) in
  match answers with
    [] -> []
  | res::rest ->
      (if not(List.for_all (function x -> x = res) rest)
      then
	(List.iter (print_state "a state") answers;
	 Printf.printf "something doesn't work\n");
      res)
      
let print_bench _ =
  let iterct = !Flag_ctl.bench in
  if iterct > 0
  then
    (List.iter
       (function (name,options,time,trips,counter_info) ->
	 Printf.fprintf stderr "%s Numbers: %f %d "
	   name (!time /. (float_of_int iterct)) !trips;
	 List.iter
	   (function (calls,cfg,max_cfg) ->
	     Printf.fprintf stderr "%d %d %d " (!calls / iterct) !cfg !max_cfg)
	   counter_info;
	 Printf.fprintf stderr "\n")
       perms)

(* ---------------------------------------------------------------------- *)
(* preprocssing: ignore irrelevant functions *)

let preprocess label (req,opt) =
  let get_any x =
    try not([] = Hashtbl.find memo_label x)
    with
      Not_found ->
(*
	Printf.printf "failed to find\n";
	P.print_predicate x;
	Format.print_newline();
*)
	let triples = setify(label x) in
	Hashtbl.add memo_label x
	  (List.map (function (st,th,_) -> (st,th)) triples);
	not ([] = triples) in
  match req with
    [] -> List.exists get_any opt
  | _ -> List.for_all get_any req

(* ---------------------------------------------------------------------- *)
(* Main entry point for engine *)
let sat m phi reqopt check_conj = 
  Hashtbl.clear reachable_table;
  Hashtbl.clear memo_label;
  let (x,label,states) = m in
  if (!Flag_ctl.bench > 0) or (preprocess label reqopt)
  then
    let m = (x,label,List.sort compare states) in
    let res =
      if(!Flag_ctl.verbose_ctl_engine)
      then
	let fn _ = snd (sat_annotree simpleanno2 m phi check_conj) in
	if !Flag_ctl.bench > 0
	then bench_sat m fn
	else fn()
      else
	let fn _ = satloop false [[]] None m phi [] check_conj in
	if !Flag_ctl.bench > 0
	then bench_sat m fn
	else fn() in
(* print_state "final result" res;*)
    res
  else (Printf.printf "missing something required\n"; flush stdout; [])
;;

(* ********************************************************************** *)
(* End of Module: CTL_ENGINE                                              *)
(* ********************************************************************** *)
end
;;

