open Fix.Indexing
open Utils
open BitSet
open Misc

open Grammar
open Regexp

(* State indices, used to translate symbols and items *)

module State_indices = struct

  (* Precompute states associated to symbols *)

  let states_of_terminals =
    Vector.make Terminal.n IndexSet.empty

  let states_of_nonterminals =
    Vector.make Nonterminal.n IndexSet.empty

  let () =
    Index.iter Lr1.n (fun lr1 ->
        match Lr1.incoming lr1 with
        | None -> ()
        | Some (Symbol.T t) -> vector_set_add states_of_terminals t lr1
        | Some (Symbol.N n) -> vector_set_add states_of_nonterminals n lr1
      )

  let states_of_symbol = function
    | Symbol.T t -> Vector.get states_of_terminals t
    | Symbol.N n -> Vector.get states_of_nonterminals n

  (* Map symbol names to actual symbols *)

  let linearize_symbol =
    let buffer = Buffer.create 32 in
    function
    | Syntax.Name s -> s
    | sym ->
      Buffer.reset buffer;
      let rec aux = function
        | Syntax.Name s -> Buffer.add_string buffer s
        | Syntax.Apply (s, args) ->
          Buffer.add_string buffer s;
          Buffer.add_char buffer '(';
          List.iteri (fun i sym ->
              if i > 0 then Buffer.add_char buffer ',';
              aux sym
            ) args;
          Buffer.add_char buffer ')'
      in
      aux sym;
      Buffer.contents buffer

  let find_symbol =
    let table = Hashtbl.create 7 in
    let add_symbol s = Hashtbl.add table (Symbol.name ~mangled:false s) s in
    Index.iter Terminal.n (fun t -> add_symbol (Symbol.T t));
    Index.iter Nonterminal.n (fun n -> add_symbol (Symbol.N n));
    fun name -> Hashtbl.find_opt table (linearize_symbol name)
end

module Match_item = struct
  let maybe_has_lhs prod = function
    | None -> true
    | Some lhs -> lhs = Production.lhs prod

  let maybe_match_sym sym = function
    | None -> true
    | Some sym' -> sym = sym'

  let forall_i f l =
    match List.iteri (fun i x -> if not (f i x) then raise Exit) l with
    | () -> true
    | exception Exit -> false

  let item_match lhs (lp, prefix) (ls, suffix) (prod, pos) =
    maybe_has_lhs prod lhs &&
    pos >= lp &&
    let rhs = Production.rhs prod in
    Array.length rhs >= pos + ls &&
    forall_i (fun i sym -> maybe_match_sym rhs.(pos - i - 1) sym) prefix &&
    forall_i (fun i sym -> maybe_match_sym rhs.(pos + i) sym) suffix

  let states_by_items ~lhs ~prefix ~suffix =
    let prefix' = List.length prefix, List.rev prefix in
    let suffix' = List.length suffix, suffix in
    index_fold Lr1.n IndexSet.empty (fun lr1 acc ->
        if List.exists
            (item_match lhs prefix' suffix')
            (Lr1.items lr1)
        then IndexSet.add lr1 acc
        else acc
      )
end

let transl_symbol name =
  match State_indices.find_symbol name with
  | None ->
    prerr_endline
      ("Unknown symbol " ^ State_indices.linearize_symbol name);
    exit 1
  | Some symbol -> symbol

let transl_nonterminal sym =
  match transl_symbol sym with
  | N n -> n
  | T t ->
    Printf.eprintf "Expecting a non-terminal but %s is a terminal\n%!"
      (Symbol.name (T t));
    exit 1

let transl_producers list =
  List.map (Option.map transl_symbol) list

let transl_atom = function
  | Syntax.Symbol name ->
    State_indices.states_of_symbol (transl_symbol name)
  | Syntax.Item {lhs; prefix; suffix} ->
    let lhs = Option.map transl_nonterminal lhs in
    let prefix = transl_producers prefix in
    let suffix = transl_producers suffix in
    Match_item.states_by_items ~lhs ~prefix ~suffix
  | Syntax.Wildcard ->
    Lr1.all

let transl_capture alloc = function
  | None -> None
  | Some name -> Some (alloc name)

let rec transl_desc alloc = function
  | Syntax.Atom (ad, var) -> RE.Set (transl_atom ad, transl_capture alloc var)
  | Syntax.Alternative rs -> RE.Alt (List.map (transl_re alloc) rs)
  | Syntax.Repetition r -> RE.Star (transl_re alloc r)
  | Syntax.Reduce -> RE.Reduce
  | Syntax.Concat rs -> RE.Seq (List.map (transl_re alloc) rs)

and transl_re alloc {Syntax. desc; position} =
  RE.make position (transl_desc alloc desc)

let transl_kre alloc pattern index =
  KRE.More (transl_re alloc pattern, Done {clause=index})
