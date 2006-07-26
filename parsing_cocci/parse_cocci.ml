(* splits the entire file into minus and plus fragments, and parses each
separately (thus duplicating work for the parsing of the context elements) *)

module D = Data
module PC = Parser_cocci_menhir
let pr = Printf.sprintf
(*let pr2 s = prerr_string s; prerr_string "\n"; flush stderr*)
let pr2 s = Printf.printf "%s\n" s

(* ----------------------------------------------------------------------- *)
(* Debugging... *)

let line_type2c (d,_,_,_) =
  match d with
    D.MINUS | D.OPTMINUS | D.UNIQUEMINUS | D.MULTIMINUS -> ":-"
  | D.PLUS -> ":+"
  | D.CONTEXT | D.UNIQUE | D.OPT | D.MULTI -> ""

let token2c (tok,_) =
  match tok with
    PC.TIdentifier -> "identifier"
  | PC.TType -> "type"
  | PC.TParameter -> "parameter"
  | PC.TConstant -> "constant"
  | PC.TExpression -> "expression"
  | PC.TStatement -> "statement"
  | PC.TFunction -> "function"
  | PC.TLocal -> "local"
  | PC.Tlist -> "list"
  | PC.TFresh -> "fresh"
  | PC.TError -> "error"
  | PC.TWords -> "words"

  | PC.Tchar(clt) -> "char"^(line_type2c clt)
  | PC.Tshort(clt) -> "short"^(line_type2c clt)
  | PC.Tint(clt) -> "int"^(line_type2c clt)
  | PC.Tdouble(clt) -> "double"^(line_type2c clt)
  | PC.Tfloat(clt) -> "float"^(line_type2c clt)
  | PC.Tlong(clt) -> "long"^(line_type2c clt)
  | PC.Tvoid(clt) -> "void"^(line_type2c clt)
  | PC.Tstruct(clt) -> "struct"^(line_type2c clt)
  | PC.Tunion(clt) -> "union"^(line_type2c clt)
  | PC.Tunsigned(clt) -> "unsigned"^(line_type2c clt)
  | PC.Tsigned(clt) -> "signed"^(line_type2c clt)
  | PC.Tstatic(clt) -> "static"^(line_type2c clt)
  | PC.Tconst(clt) -> "const"^(line_type2c clt)
  | PC.Tvolatile(clt) -> "volatile"^(line_type2c clt)

  | PC.TInclude(s,clt) -> (pr "#include %s" s)^(line_type2c clt)
  | PC.TMinusFile(s,clt) -> (pr "--- %s" s)^(line_type2c clt)
  | PC.TPlusFile(s,clt) -> (pr "+++ %s" s)^(line_type2c clt)

  | PC.TInc(clt) -> "++"^(line_type2c clt)
  | PC.TDec(clt) -> "--"^(line_type2c clt)
	
  | PC.TIf(clt) -> "if"^(line_type2c clt)
  | PC.TElse(clt) -> "else"^(line_type2c clt)
  | PC.TWhile(clt) -> "while"^(line_type2c clt)
  | PC.TFor(clt) -> "for"^(line_type2c clt)
  | PC.TDo(clt) -> "do"^(line_type2c clt)
  | PC.TReturn(clt) -> "return"^(line_type2c clt)
  | PC.TIdent(s,clt) -> (pr "ident-%s" s)^(line_type2c clt)

  | PC.TSizeof(clt) -> "sizeof"^(line_type2c clt)

  | PC.TString(x,clt) -> x^(line_type2c clt)
  | PC.TChar(x,clt) -> x^(line_type2c clt)
  | PC.TFloat(x,clt) -> x^(line_type2c clt)
  | PC.TInt(x,clt) -> x^(line_type2c clt)

  | PC.TOrLog(clt) -> "||"^(line_type2c clt)
  | PC.TAndLog(clt) -> "&&"^(line_type2c clt)
  | PC.TOr(clt) -> "|"^(line_type2c clt)
  | PC.TXor(clt) -> "^"^(line_type2c clt)
  | PC.TAnd (clt) -> "&"^(line_type2c clt)
  | PC.TEqEq(clt) -> "=="^(line_type2c clt)
  | PC.TNotEq(clt) -> "!="^(line_type2c clt)
  | PC.TInf(clt) -> "<"^(line_type2c clt)
  | PC.TSup(clt) -> ">"^(line_type2c clt)
  | PC.TInfEq(clt) -> "<="^(line_type2c clt)
  | PC.TSupEq (clt) -> ">="^(line_type2c clt)
  | PC.TShl(clt) -> "<<"^(line_type2c clt)
  | PC.TShr(clt) -> ">>"^(line_type2c clt)
  | PC.TPlus(clt) -> "+"^(line_type2c clt)
  | PC.TMinus(clt) -> "-"^(line_type2c clt)
  | PC.TMul(clt) -> "*"^(line_type2c clt)
  | PC.TDiv(clt) -> "/"^(line_type2c clt)
  | PC.TMod (clt) -> "%"^(line_type2c clt)

  | PC.TMetaParam(_,clt) -> "parammeta"^(line_type2c clt)
  | PC.TMetaParamList(_,clt) -> "paramlistmeta"^(line_type2c clt)
  | PC.TMetaConst(_,_,clt) -> "constmeta"^(line_type2c clt)
  | PC.TMetaErr(_,clt) -> "errmeta"^(line_type2c clt)
  | PC.TMetaExp(_,_,clt) -> "expmeta"^(line_type2c clt)
  | PC.TMetaExpList(_,clt) -> "explistmeta"^(line_type2c clt)
  | PC.TMetaId(_,clt)    -> "idmeta"^(line_type2c clt)
  | PC.TMetaType(_,clt)    -> "typemeta"^(line_type2c clt)
  | PC.TMetaStm(_,clt)   -> "stmmeta"^(line_type2c clt)
  | PC.TMetaStmList(_,clt)   -> "stmlistmeta"^(line_type2c clt)
  | PC.TMetaFunc(_,clt)  -> "funcmeta"^(line_type2c clt)
  | PC.TMetaLocalFunc(_,clt) -> "funcmeta"^(line_type2c clt)
  | PC.TArobArob -> "@@"

  | PC.TWhen(clt) -> "WHEN"^(line_type2c clt)
  | PC.TEllipsis(clt) -> "..."^(line_type2c clt)
  | PC.TCircles(clt)  -> "ooo"^(line_type2c clt)
  | PC.TStars(clt)    -> "***"^(line_type2c clt)

  | PC.TOEllipsis(clt) -> "<..."^(line_type2c clt)
  | PC.TCEllipsis(clt) -> "...>"^(line_type2c clt)
  | PC.TOCircles(clt)  -> "<ooo"^(line_type2c clt)
  | PC.TCCircles(clt)  -> "ooo>"^(line_type2c clt)
  | PC.TOStars(clt)    -> "<***"^(line_type2c clt)
  | PC.TCStars(clt)    -> "***>"^(line_type2c clt)
  | PC.TBang0 -> "!"
  | PC.TPlus0 -> "+"
  | PC.TWhy0  -> "?"

  | PC.TWhy(clt)   -> "?"^(line_type2c clt)
  | PC.TDotDot(clt)   -> ":"^(line_type2c clt)
  | PC.TBang(clt)  -> "!"^(line_type2c clt)
  | PC.TOPar(clt)  -> "("^(line_type2c clt)
  | PC.TOPar0(clt) -> "("^(line_type2c clt)
  | PC.TMid(clt)   -> "|"^(line_type2c clt)
  | PC.TMid0(clt)  -> "|"^(line_type2c clt)
  | PC.TCPar(clt)  -> ")"^(line_type2c clt)
  | PC.TCPar0(clt) -> ")"^(line_type2c clt)

  | PC.TOBrace(clt) -> "{"^(line_type2c clt)
  | PC.TCBrace(clt) -> "}"^(line_type2c clt)
  | PC.TOCro(clt) -> "["^(line_type2c clt)
  | PC.TCCro(clt) -> "]"^(line_type2c clt)

  | PC.TPtrOp(clt) -> "->"^(line_type2c clt)

  | PC.TEq(clt) -> "="^(line_type2c clt)
  | PC.TAssign(_,clt) -> "=op"^(line_type2c clt)
  | PC.TDot(clt) -> "."^(line_type2c clt)
  | PC.TComma(clt) -> ","^(line_type2c clt)
  | PC.TPtVirg(clt) -> ";"^(line_type2c clt)

  | PC.EOF -> "eof"
  | PC.TLineEnd(clt) -> "line end"
  | PC.TInvalid -> "invalid"
  | PC.TFunDecl(clt) -> "fundecl"

  | PC.TIso -> "<=>"
  | PC.TIsoExpression -> "Expression"
  | PC.TIsoStatement -> "Statement"
  | PC.TIsoDeclaration -> "Declaration"

(* ----------------------------------------------------------------------- *)
(* Read tokens *)

let wrap_lexbuf_info lexbuf =
  (Lexing.lexeme lexbuf, Lexing.lexeme_start lexbuf)    

let tokens_all table file get_ats lexbuf end_markers :
    (bool * ((PC.token * (string * (int * int) * (int * int))) list)) =
  try 
    let rec aux () = 
      let result = Lexer_cocci.token lexbuf in
      let info = (Lexing.lexeme lexbuf, 
                  (table.(Lexing.lexeme_start lexbuf)),
                  (Lexing.lexeme_start lexbuf, Lexing.lexeme_end lexbuf)) in
      if result = PC.EOF 
      then
	if get_ats
	then failwith "unexpected end of file in a metavariable declaration"
	else (false,[(result,info)])
      else if List.mem result end_markers
      then (true,[(result,info)])
      else
	let (more,rest) = aux() in
	(more,(result, info)::rest)
    in aux () 
  with
    e -> pr2 (Common.error_message file (wrap_lexbuf_info lexbuf) ); raise e

(* ----------------------------------------------------------------------- *)
(* Split tokens into minus and plus fragments *)

let split t = function
    (D.MINUS,_,_,_) | (D.OPTMINUS,_,_,_) | (D.UNIQUEMINUS,_,_,_)
  | (D.MULTIMINUS,_,_,_) -> ([t],[])
  | (D.PLUS,_,_,_) -> ([],[t])
  | (D.CONTEXT,_,_,_) | (D.UNIQUE,_,_,_)
  | (D.OPT,_,_,_) | (D.MULTI,_,_,_) -> ([t],[t])

let split_token ((tok,_) as t) =
  match tok with
    PC.TIdentifier | PC.TConstant | PC.TExpression | PC.TStatement
  | PC.TFunction
  | PC.TType | PC.TParameter | PC.TLocal | PC.Tlist | PC.TFresh
  | PC.TError | PC.TWords -> ([t],[t])

  | PC.Tchar(clt) | PC.Tshort(clt) | PC.Tint(clt) | PC.Tdouble(clt)
  | PC.Tfloat(clt) | PC.Tlong(clt) | PC.Tvoid(clt) | PC.Tstruct(clt)
  | PC.Tunion(clt) | PC.Tunsigned(clt) | PC.Tsigned(clt)
  | PC.Tstatic(clt) | PC.Tconst(clt) | PC.Tvolatile(clt) -> split t clt

  | PC.TPlusFile(s,clt) | PC.TMinusFile(s,clt) | PC.TInclude(s,clt) ->
      split t clt

  | PC.TIf(clt) | PC.TElse(clt)  | PC.TWhile(clt) | PC.TFor(clt) | PC.TDo(clt)
  | PC.TSizeof(clt)
  | PC.TReturn(clt) | PC.TIdent(_,clt)
  | PC.TMetaConst(_,_,clt) | PC.TMetaExp(_,_,clt) | PC.TMetaExpList(_,clt)
  | PC.TMetaParam(_,clt) | PC.TMetaParamList(_,clt)
  | PC.TMetaId(_,clt) | PC.TMetaType(_,clt)
  | PC.TMetaStm(_,clt) | PC.TMetaStmList(_,clt) | PC.TMetaErr(_,clt)
  | PC.TMetaFunc(_,clt) | PC.TMetaLocalFunc(_,clt) -> split t clt
  | PC.TArobArob -> ([t],[t])

  | PC.TFunDecl(clt)
  | PC.TWhen(clt) | PC.TLineEnd(clt)
  | PC.TEllipsis(clt) | PC.TCircles(clt) | PC.TStars(clt) -> split t clt

  | PC.TOEllipsis(_) | PC.TCEllipsis(_) (* clt must be context *)
  | PC.TOCircles(_) | PC.TCCircles(_)   (* clt must be context *)
  | PC.TOStars(_) | PC.TCStars(_)       (* clt must be context *)
  | PC.TBang0 | PC.TPlus0 | PC.TWhy0 ->
      ([t],[t])

  | PC.TWhy(clt)  | PC.TDotDot(clt)
  | PC.TBang(clt) | PC.TOPar(clt) | PC.TOPar0(clt) | PC.TMid(clt)
  | PC.TMid0(clt) | PC.TCPar(clt) | PC.TCPar0(clt) -> split t clt

  | PC.TInc(clt) | PC.TDec(clt) -> split t clt

  | PC.TString(_,clt) | PC.TChar(_,clt) | PC.TFloat(_,clt) | PC.TInt(_,clt) ->
      split t clt

  | PC.TOrLog(clt) | PC.TAndLog(clt) | PC.TOr(clt) | PC.TXor(clt)
  | PC.TAnd (clt) | PC.TEqEq(clt) | PC.TNotEq(clt) | PC.TInf(clt)
  | PC.TSup(clt) | PC.TInfEq(clt) | PC.TSupEq (clt) | PC.TShl(clt)
  | PC.TShr(clt) | PC.TPlus(clt) | PC.TMinus(clt) | PC.TMul(clt)
  | PC.TDiv(clt) | PC.TMod (clt) -> split t clt

  | PC.TOBrace(clt) | PC.TCBrace(clt) -> split t clt
  | PC.TOCro(clt) | PC.TCCro(clt) -> split t clt

  | PC.TPtrOp(clt) -> split t clt

  | PC.TEq(clt) | PC.TAssign(_,clt) | PC.TDot(clt) | PC.TComma(clt)
  | PC.TPtVirg(clt) -> split t clt

  | PC.EOF | PC.TInvalid -> ([t],[t])

  | PC.TIso | PC.TIsoExpression | PC.TIsoStatement | PC.TIsoDeclaration ->
      failwith "unexpected tokens"

let split_token_stream tokens =
  let rec loop = function
      [] -> ([],[])
    | token::tokens ->
	let (minus,plus) = split_token token in
	let (minus_stream,plus_stream) = loop tokens in
	(minus@minus_stream,plus@plus_stream) in
  loop tokens

(* ----------------------------------------------------------------------- *)
(* Find function names *)
(* This addresses a shift-reduce problem in the parser, allowing us to
distinguish a function declaration from a function call even if the latter
has no return typed.  Undoubtedly, this is not very nice, but it doesn't
seem very convenient to refactor the grammar to get around the problem. *)

let rec find_function_names = function
    [] -> []
  | ((PC.TIdent(s,clt),info) as t1) :: ((PC.TOPar(_),_) as t2) :: rest
  | ((PC.TMetaId(s,clt),info) as t1) :: ((PC.TOPar(_),_) as t2) :: rest
  | ((PC.TMetaFunc(s,clt),info) as t1) :: ((PC.TOPar(_),_) as t2) :: rest
  | ((PC.TMetaLocalFunc(s,clt),info) as t1) :: ((PC.TOPar(_),_) as t2) :: rest
    ->
      let rec skip = function
	  [] -> ([],false,[])
	| ((PC.TCPar(_),_) as t)::rest -> ([t],true,rest)
	| ((PC.TArobArob,_) as t)::rest -> ([t],false,rest)
	| ((PC.EOF,_) as t)::rest -> ([t],false,rest)
	| t::rest ->
      	    let (pre,found,post) = skip rest in (t::pre,found,post) in
      let (pre,found,post) = skip rest in
      (match (found,post) with
	(true,((PC.TOBrace(_),_) as t3)::rest) ->
	  (PC.TFunDecl(clt),info) :: t1 :: t2 :: pre @
	  t3 :: (find_function_names rest)
      |	_ -> t1 :: t2 :: pre @ find_function_names post)
  | t :: rest -> t :: find_function_names rest

(* ----------------------------------------------------------------------- *)
(* Insert TLineEnd tokens at the end of a line that contains a WHEN.
   WHEN is restricted to a single line, to avoid ambiguity in eg:
   ... WHEN != x
   +3 *)

let token2line (tok,_) =
  match tok with
    PC.Tchar(clt) | PC.Tshort(clt) | PC.Tint(clt) | PC.Tdouble(clt) 
  | PC.Tfloat(clt) | PC.Tlong(clt) | PC.Tvoid(clt) | PC.Tstruct(clt) 
  | PC.Tunion(clt) | PC.Tunsigned(clt) | PC.Tsigned(clt) | PC.Tstatic(clt) 
  | PC.Tconst(clt) | PC.Tvolatile(clt) 

  | PC.TInc(clt) | PC.TDec(clt) 
	
  | PC.TIf(clt) | PC.TElse(clt) | PC.TWhile(clt) | PC.TFor(clt) | PC.TDo(clt) 
  | PC.TSizeof (clt)
  | PC.TReturn(clt) | PC.TIdent(_,clt)

  | PC.TString(_,clt) | PC.TChar(_,clt) | PC.TFloat(_,clt) | PC.TInt(_,clt) 

  | PC.TOrLog(clt) | PC.TAndLog(clt) | PC.TOr(clt) | PC.TXor(clt)
  | PC.TAnd (clt) | PC.TEqEq(clt) | PC.TNotEq(clt) | PC.TInf(clt) 
  | PC.TSup(clt) | PC.TInfEq(clt) | PC.TSupEq (clt) | PC.TShl(clt) 
  | PC.TShr(clt) | PC.TPlus(clt) | PC.TMinus(clt) | PC.TMul(clt) 
  | PC.TDiv(clt) | PC.TMod (clt) 

  | PC.TMetaParam(_,clt) | PC.TMetaParamList(_,clt) 
  | PC.TMetaConst(_,_,clt) | PC.TMetaExp(_,_,clt) | PC.TMetaExpList(_,clt) 
  | PC.TMetaId(_,clt) | PC.TMetaType(_,clt)  | PC.TMetaStm(_,clt)   
  | PC.TMetaStmList(_,clt) | PC.TMetaFunc(_,clt) | PC.TMetaLocalFunc(_,clt) 

  | PC.TFunDecl(clt)
  | PC.TWhen(clt) | PC.TEllipsis(clt) | PC.TCircles(clt) | PC.TStars(clt)    

  | PC.TOEllipsis(clt) | PC.TCEllipsis(clt) | PC.TOCircles(clt)
  | PC.TCCircles(clt) | PC.TOStars(clt) | PC.TCStars(clt)    

  | PC.TWhy(clt) | PC.TDotDot(clt) | PC.TBang(clt) | PC.TOPar(clt)
  | PC.TOPar0(clt) | PC.TMid(clt) | PC.TMid0(clt) | PC.TCPar(clt)  
  | PC.TCPar0(clt) 

  | PC.TOBrace(clt) | PC.TCBrace(clt) | PC.TOCro(clt) | PC.TCCro(clt) 

  | PC.TPtrOp(clt) 

  | PC.TEq(clt) | PC.TAssign(_,clt) | PC.TDot(clt) | PC.TComma(clt) 
  | PC.TPtVirg(clt) ->
      let (_,line,_,_) = clt in Some line

  | _ -> None

let rec insert_line_end = function
    [] -> []
  | (((PC.TWhen(clt),q) as x)::xs) ->
      x::(find_line_end (token2line x) clt q xs)
  | x::xs -> x::(insert_line_end xs)

and find_line_end line clt q = function
    (* don't know what 2nd component should be so just use the info of
       the When.  Also inherit - of when, if any *)
    [] -> [(PC.TLineEnd(clt),q)]
  | x::xs when token2line x = line -> x :: (find_line_end line clt q xs)
  | xs -> (PC.TLineEnd(clt),q)::(insert_line_end xs)

(* ----------------------------------------------------------------------- *)
(* Drop ... ... .  This is only allowed in + code, and arises when there is
some - code between the ... *)
(* drop whens as well - they serve no purpose in + code and they cause
problems for drop_double_dots *)

let rec drop_when = function
    [] -> []
  | (PC.TWhen(clt),info)::xs ->
      let rec loop = function
	  [] -> []
	| (PC.TLineEnd(_),info)::xs -> drop_when xs
	| x::xs -> loop xs in
      loop xs
  | x::xs -> x::drop_when xs

let rec drop_double_dots l =
  let start = function
      (PC.TOEllipsis(_),_) | (PC.TOCircles(_),_) | (PC.TOStars(_),_) -> true
    | _ -> false in
  let middle = function
      (PC.TEllipsis(_),_) | (PC.TCircles(_),_) | (PC.TStars(_),_) -> true
    | _ -> false in
  let final = function
      (PC.TCEllipsis(_),_) | (PC.TCCircles(_),_) | (PC.TCStars(_),_) -> true
    | _ -> false in
  let rec loop = function
      [] -> []
    | x::y::rest when middle x && middle y -> loop (x::rest)
    | x::y::rest when start x && middle y -> loop (x::rest)
    | x::y::rest when start x && final y -> loop rest
    | x::y::rest when middle x && final y -> y::(loop rest)
    | x::rest -> x :: (loop rest) in
  loop l

let rec fix f l =
  let cur = f l in
  if l = cur then l else fix f cur

(* ( | ... | ) also causes parsing problems *)

exception Not_empty

let rec drop_empty_thing starter middle ender = function
    [] -> []
  | hd::rest when starter hd ->
      let rec loop = function
	  x::rest when middle x -> loop rest
	| x::rest when ender x -> rest
	| _ -> raise Not_empty in
      (match try Some(loop rest) with Not_empty -> None with
	Some x -> drop_empty_thing starter middle ender x
      |	None -> hd :: drop_empty_thing starter middle ender rest)
  | x::rest -> x :: drop_empty_thing starter middle ender rest

let drop_empty_or =
  drop_empty_thing
    (function (PC.TOPar0(_),_) -> true | _ -> false)
    (function (PC.TMid0(_),_) -> true | _ -> false)
    (function (PC.TCPar0(_),_) -> true | _ -> false)

let drop_empty_nest =
  drop_empty_thing

(* ----------------------------------------------------------------------- *)
(* Read tokens *)

let get_s_starts (_, (s,_,(starts, ends))) = (s, starts)

let pop2 l = 
  let v = List.hd !l in
  l := List.tl !l;
  v

let parse_one parsefn file toks =
  let all_tokens = ref toks in
  let cur_tok    = ref (List.hd !all_tokens) in

  let lexer_function _ =
      let (v, info) = pop2 all_tokens in
      cur_tok := (v, info);
      v in

  let lexbuf_fake =
    Lexing.from_function (function buf -> function n -> raise Common.Impossible)
  in

  try parsefn lexer_function lexbuf_fake 
  with 
    Lexer_cocci.Lexical s ->
      pr2
	(pr "lexical error %s\n =%s\n" s
	   (Common.error_message file (get_s_starts !cur_tok) ));
      failwith ""
  | Parser_cocci_menhir.Error ->
      pr2
	(pr "parse error \n = %s\n" 
	   (Common.error_message file (get_s_starts !cur_tok) ));
      failwith ""
  | Semantic_cocci.Semantic s ->
      pr2
	(pr "semantic error %s\n =%s\n" s
	   (Common.error_message file (get_s_starts !cur_tok) ));
      failwith ""

  | e -> raise e

let prepare_tokens tokens = insert_line_end (find_function_names tokens)

let parse file =
  Lexer_cocci.init ();
  let table = Common.full_charpos_to_pos file in
  let lexbuf = Lexing.from_channel (open_in file) in
  match tokens_all table file false lexbuf [PC.TArobArob] with 
    (true,[(PC.TArobArob,_)]) -> (* read over initial @@ *)
      let rec loop _ =
	(* get metavariable declarations *)
	let (more,tokens) =
	  tokens_all table file true lexbuf [PC.TArobArob] in
	let metavars = parse_one PC.meta_main file tokens in
	(* get transformation rules *)
	let (more,tokens) =
	  tokens_all table file false lexbuf [PC.TArobArob] in
	let tokens = prepare_tokens tokens in
	let (minus_tokens,plus_tokens) = split_token_stream tokens in 
	(*
	List.iter (function x -> Printf.printf "%s " (token2c x)) minus_tokens;
	Printf.printf "\n\n";
	List.iter (function x -> Printf.printf "%s " (token2c x)) plus_tokens;
	Printf.printf "\n\n";
	*)
	let plus_tokens =
	  fix (function x -> drop_double_dots (drop_empty_or x))
	    (drop_when plus_tokens) in
	(*
	Printf.printf "plus tokens\n";
	List.iter (function x -> Printf.printf "%s " (token2c x)) plus_tokens;
	Printf.printf "\n\n";
	Printf.printf "before minus parse\n";
	*)
	let minus_res = parse_one PC.minus_main file minus_tokens in
	Unparse_ast0.unparse minus_res;
	(*
	Printf.printf "before plus parse\n";
	*)
	let plus_res = parse_one PC.plus_main file plus_tokens in
	(*
	Printf.printf "after plus parse\n";
	*)
	Check_meta.check_meta metavars minus_res plus_res;
	if more
	then
	  let (minus_ress,plus_ress) = loop () in
	  ((minus_res, metavars)::minus_ress,(plus_res, metavars)::plus_ress)
	else ([minus_res, metavars],[plus_res, metavars]) in
      loop ()
  | (false,[(PC.TArobArob,_)]) -> ([],[])
  | _ -> failwith "unexpected code before the first rule\n"

let drop_last extra l = List.rev(extra@(List.tl(List.rev l)))

let parse_iso = function
    None -> []
  | Some file ->
      Lexer_cocci.init ();
      let table = Common.full_charpos_to_pos file in
      let lexbuf = Lexing.from_channel (open_in file) in
      (match tokens_all table file false lexbuf [PC.TArobArob] with
	(true,start) ->
	  let rec loop start =
	    (* get metavariable declarations - have to be read before the
	       rest *)
	    let (more,tokens) =
	      tokens_all table file true lexbuf [PC.TArobArob] in
	    let _ = parse_one PC.meta_main file tokens in
	    (* get the rule *)
	    let (more,tokens) =
	      tokens_all table file false lexbuf
		[PC.TIsoStatement;PC.TIsoExpression;PC.TIsoDeclaration] in
	    let next_start = List.hd(List.rev tokens) in
	    let dummy_info = ("",(-1,-1),(-1,-1)) in
	    let tokens = drop_last [(PC.EOF,dummy_info)] tokens in
	    let tokens = prepare_tokens ((drop_last [] start)@tokens) in
	    let entry = parse_one PC.iso_main file tokens in
	    if more
	    then (* The code below allows a header like Statement list,
		    which is more than one word.  We don't have that any more,
		    but the code is left here in case it is put back. *)
	      match tokens_all table file true lexbuf [PC.TArobArob] with
		(true,start) -> entry :: (loop (next_start::start))
	      |	_ -> failwith "isomorphism ends early"
	    else [entry] in
	  loop start
      | (false,_) -> [])

(* parse to ast0 and then convert to ast *)
let process file isofile verbose =
  try
    let (minus,plus) = parse file in
    (!Data.clear_meta)();
    let isos = parse_iso isofile in
    (!Data.clear_meta)();
    let parsed =
      List.map2
	(function (minus, metavars) ->
	  function (plus, metavars) ->
	    let minus = Compute_lines.compute_lines minus in
	    let plus = Compute_lines.compute_lines plus in
	    let minus = Arity.minus_arity minus in
	    let (m,p) = List.split(Context_neg.context_neg minus plus) in
	    Insert_plus.insert_plus m p;
	    let minus = Iso_pattern.apply_isos isos minus in
	    let minus_ast = Ast0toast.ast0toast minus in
	    if verbose then Pretty_print_cocci.unparse minus_ast;
	    (metavars, minus_ast))
	minus plus in
    let (free_tables,used_after_lists,extenders) =
      Free_vars.free_vars parsed in
    let (_,ast_list) = List.split parsed in
    (ast_list,free_tables,used_after_lists,extenders)
  with Failure s -> Printf.printf "%s" s; ([],[],[],[])
