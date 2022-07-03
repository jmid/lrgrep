(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open Utils
let filename_of_position _ = failwith "TODO"

(* The lexer generator. Command-line parsing. *)

let run_test = false
let verbose = true

let source_name = ref None
let output_name = ref None
let grammar_file = ref None

let usage =
  Printf.sprintf
    "lrgrep, a menhir lexer\n\
     usage: %s [options] <source>"
    Sys.argv.(0)

let print_version_num () =
  print_endline "0.1";
  exit 0

let print_version_string () =
  print_string "The Menhir parser lexer generator :-], version ";
  print_version_num ()

let specs = [
  "-o", Arg.String (fun x -> output_name := Some x),
  " <file.ml>  Set output file name to <file> (defaults to <source>.ml)";
  "-g", Arg.String (fun x -> grammar_file := Some x),
  " <file.cmly>  Path of the Menhir compiled grammar to analyse (*.cmly)";
  "-q", Arg.Set Common.quiet_mode,
  " Do not display informational messages";
  "-n", Arg.Set Common.dry_run,
  " Process input but do not generate any file";
  "-d", Arg.Set Common.dump_parsetree,
  " Dump parsetree";
  "-v",  Arg.Unit print_version_string,
  " Print version and exit";
  "-version",  Arg.Unit print_version_string,
  " Print version and exit";
  "-vnum",  Arg.Unit print_version_num,
  " Print version number and exit";
]

let () = Arg.parse specs (fun name -> source_name := Some name) usage

let source_file = match !source_name with
  | None ->
    Format.eprintf "No source provided, stopping now.\n";
    Arg.usage specs usage;
    exit 1
  | Some name -> name

let print_parse_error_and_exit lexbuf exn =
  let bt = Printexc.get_raw_backtrace () in
  begin match exn with
    | Parser.Error ->
      let p = Lexing.lexeme_start_p lexbuf in
      Printf.fprintf stderr
        "File \"%s\", line %d, character %d: syntax error.\n"
        p.Lexing.pos_fname p.Lexing.pos_lnum
        (p.Lexing.pos_cnum - p.Lexing.pos_bol)
    | Lexer.Lexical_error {msg; file; line; col} ->
      Printf.fprintf stderr
        "File \"%s\", line %d, character %d: %s.\n"
        file line col msg
    | _ -> Printexc.raise_with_backtrace exn bt
  end;
  exit 3

let lexer_definition =
  let ic = open_in_bin source_file in
  Lexer.ic := Some ic;
  let lexbuf = Lexing.from_channel ~with_positions:true ic in
  Lexing.set_filename lexbuf source_file;
  let result =
    try Parser.lexer_definition Lexer.main lexbuf
    with exn -> print_parse_error_and_exit lexbuf exn
  in
  Lexer.ic := None;
  result

(* General purpose definitions *)

open Fix.Indexing

module IndexSet = BitSet.IndexSet

let (@) l1 l2 =
  match l1, l2 with
  | [], l | l, [] -> l
  | l1, l2 -> l1 @ l2

type 'a indexset = 'a IndexSet.t
type ('n, 'a) indexmap = ('n, 'a) IndexMap.t

let array_cons arr index value =
  arr.(index) <- value :: arr.(index)

let option_cons x xs =
  match x with
  | None -> xs
  | Some x -> x :: xs

let index_fold v a f =
  let a = ref a in
  Index.iter v (fun i -> a := f i !a);
  !a

let indexset_bind : 'a indexset -> ('a index -> 'b indexset) -> 'b indexset =
  fun s f ->
  IndexSet.fold (fun lr1 acc -> IndexSet.union acc (f lr1)) s IndexSet.empty

let vector_set_add vec index value =
  Vector.set vec index (IndexSet.add value (Vector.get vec index))

let vector_iter v f =
  Index.iter (Vector.length v) (fun i -> f (Vector.get v i ))

let vector_tabulate n f =
  Vector.get (Vector.init n f)

let compare_index =
  (Int.compare : int -> int -> int :> _ index -> _ index -> int)

let string_of_index =
  (string_of_int : int -> string :> _ index -> string)

let cmon_index =
  (Cmon.int : int -> Cmon.t :> _ index -> Cmon.t)

let cmon_indexset xs =
  Cmon.constant (
    "[" ^ String.concat ";" (List.map string_of_index (IndexSet.elements xs)) ^ "]"
  )

let push xs x = xs := x :: !xs

let pushs xs = function
  | [] -> ()
  | x -> xs := x @ !xs

let rec hash_list f = function
  | [] -> 7
  | x :: xs -> Hashtbl.seeded_hash (hash_list f xs) (f x)

let rec merge_uniq cmp l1 l2 =
  match l1, l2 with
  | [], l2 -> l2
  | l1, [] -> l1
  | h1 :: t1, h2 :: t2 ->
    let c = cmp h1 h2 in
    if c = 0
    then h1 :: merge_uniq cmp t1 t2
    else if c < 0
    then h1 :: merge_uniq cmp t1 l2
    else h2 :: merge_uniq cmp l1 t2

(* Grammar representation *)

module Grammar = MenhirSdk.Cmly_read.Read (struct
    let filename = match !grammar_file with
      | Some filename -> filename
      | None ->
        Format.eprintf "No grammar provided (-g), stopping now.\n";
        Arg.usage specs usage;
        exit 1
  end)

module Terminal = struct
  include Grammar.Terminal
  type raw = t

  include (val const count)
  type t = n index
  type set = n indexset
  let of_g x = Index.of_int n (to_int x)
  let to_g x = of_int (Index.to_int x)

  let all =
    let acc = ref IndexSet.empty in
    for i = cardinal n - 1 downto 0
    do acc := IndexSet.add (Index.of_int n i) !acc done;
    !acc
  let name t = name (to_g t)
end

module Nonterminal = struct
  include Grammar.Nonterminal
  type raw = t

  include (val const count)
  type t = n index
  type set = n indexset
  let of_g x = Index.of_int n (to_int x)
  let to_g x = of_int (Index.to_int x)

  let all =
    let acc = ref IndexSet.empty in
    for i = cardinal n - 1 downto 0
    do acc := IndexSet.add (Index.of_int n i) !acc done;
    !acc
end

module Symbol = struct
  type t =
    | T of Terminal.t
    | N of Nonterminal.t

  let of_g = function
    | Grammar.T t -> T (Terminal.of_g t)
    | Grammar.N n -> N (Nonterminal.of_g n)

  let to_g = function
    | T t -> Grammar.T (Terminal.to_g t)
    | N n -> Grammar.N (Nonterminal.to_g n)

  let name ?mangled = function
    | T t -> Grammar.symbol_name ?mangled (T (Terminal.to_g t))
    | N n -> Grammar.symbol_name ?mangled (N (Nonterminal.to_g n))
end

module Production = struct
  include Grammar.Production
  type raw = t

  include (val const count)
  type t = n index
  type set = n indexset
  let of_g x = Index.of_int n (to_int x)
  let to_g x = of_int (Index.to_int x)

  let lhs p = Nonterminal.of_g (lhs (to_g p))
  let rhs =
    let import prod =
      Array.map (fun (sym,_,_) -> Symbol.of_g sym) (rhs (to_g prod))
    in
    Vector.get (Vector.init n import)
  let kind p = kind (to_g p)
end

module Lr1 = struct
  include Grammar.Lr1
  type raw = t

  include (val const count)
  type t = n index
  type set = n indexset
  type 'a map = (n, 'a) indexmap
  let of_g lr1 = Index.of_int n (to_int lr1)
  let to_g lr1 = of_int (Index.to_int lr1)

  let all =
    let acc = ref IndexSet.empty in
    for i = cardinal n - 1 downto 0
    do acc := IndexSet.add (Index.of_int n i) !acc done;
    !acc

  let to_lr0 lr1 = lr0 (to_g lr1)

  let incoming lr1 =
    Option.map Symbol.of_g (Grammar.Lr0.incoming (to_lr0 lr1))

  let items lr1 =
    List.map
      (fun (p,pos) -> (Production.of_g p, pos))
      (Grammar.Lr0.items (to_lr0 lr1))

  let reductions =
    let import_red reds =
      reds
      |> List.map
        (fun (t, ps) -> (Production.of_g (List.hd ps), Terminal.of_g t))
      |> Misc.group_by
        ~compare:(fun (p1,_) (p2,_) -> compare_index p1 p2)
        ~group:(fun (p,t) ps -> p, IndexSet.of_list (t :: List.map snd ps))
    in
    let import_lr1 lr1 = import_red (reductions (to_g lr1)) in
    Vector.get (Vector.init n import_lr1)
end

(* ---------------------------------------------------------------------- *)

(* Transitions are represented as finite sets with auxiliary functions
   to get the predecessors, successors and labels. *)
module Transition : sig
  (* Abstract types used as index to represent the different sets of
     transitions.
     For instance, [goto] represents the finite set of goto transition:
     - the value [goto : goto cardinal] is the cardinal of this set
     - any value of type [goto index] is a member of this set
       (representing a goto transition)
  *)
  type goto and shift and any

  (* The set of goto transitions *)
  val goto : goto cardinal
  (* The set of all transitions = goto U shift *)
  val any : any cardinal
  (* The set of shift transitions *)
  val shift : shift cardinal

  (* Building the isomorphism between any and goto U shift *)

  (* Inject goto into any *)
  val of_goto : goto index -> any index

  (* Inject shift into any *)
  val of_shift : shift index -> any index

  (* Project a transition into a goto or a shift transition *)
  val split : any index -> (goto index, shift index) either

  (* [find_goto s nt] finds the goto transition originating from [s] and
     labelled by [nt], or raise [Not_found].  *)
  val find_goto : Lr1.t -> Nonterminal.t -> goto index
  val find_goto_target : Lr1.t -> Nonterminal.t -> Lr1.t

  (* Get the source state of a transition *)
  val source : any index -> Lr1.t

  (* Get the target state of a transition *)
  val target : any index -> Lr1.t

  (* Symbol that labels a transition *)
  val symbol : any index -> Symbol.t

  (* Symbol that labels a goto transition *)
  val goto_symbol : goto index -> Nonterminal.t

  (* Symbol that labels a shift transition *)
  val shift_symbol : shift index -> Terminal.t

  (* [successors s] returns all the transitions [tr] such that
     [source tr = s] *)
  val successors : Lr1.t -> any index list

  (* [predecessors s] returns all the transitions [tr] such that
     [target tr = s] *)
  val predecessors : Lr1.t -> any index list
end =
struct

  (* Pre-compute all information, such that functions of this module
     always operate in O(1) *)

  (* Create two fresh finite sets that will be populated with goto and shift
     transitions *)
  module Goto = Gensym()
  module Shift = Gensym()

  let () =
    (* Count goto and shift transitions by iterating on all states and
       transitions *)
    Lr1.iter begin fun lr1 ->
      List.iter begin fun (sym, _) ->
        match sym with
        | Grammar.T _t ->
          (*if Terminal.real t then*)
          ignore (Shift.fresh ())
        | Grammar.N _ ->
          ignore (Goto.fresh ())
      end (Lr1.transitions lr1)
    end

  type goto = Goto.n
  let goto = Goto.n

  type shift = Shift.n
  let shift = Shift.n

  (* Any is the disjoint sum of goto and shift transitions *)
  module Any = (val sum goto shift)
  type any = Any.n
  let any = Any.n

  let of_goto = Any.inj_l
  let of_shift = Any.inj_r
  let split = Any.prj

  (* Vectors to store information on states and transitions.

     We allocate a bunch of data structures (sources, targets, t_symbols,
     nt_symbols and predecessors vectors, t_table and nt_table hash tables),
     and then populate them by iterating over all transitions.
  *)

  let sources = Vector.make' any (fun () -> Index.of_int Lr1.n 0)
  let targets = Vector.make' any (fun () -> Index.of_int Lr1.n 0)

  let t_symbols = Vector.make' shift (fun () -> Index.of_int Terminal.n 0)
  let nt_symbols = Vector.make' goto (fun () -> Index.of_int Nonterminal.n 0)

  (* Hash tables to associate information to the pair of
     a transition and a symbol.
  *)

  let nt_table = Hashtbl.create 7

  let nt_pack lr1 goto =
    (* Custom function to key into nt_table: compute a unique integer from
       an lr1 state and a non-terminal. *)
    Index.to_int lr1 * Nonterminal.count + Index.to_int goto

  let t_table = Hashtbl.create 7

  let t_pack lr1 t =
    (* Custom function to key into t_table: compute a unique integer from
       an lr1 state and a terminal. *)
    Index.to_int lr1 * Terminal.count + Index.to_int t

  (* A vector to store the predecessors of an lr1 state.
     We cannot compute them directly, we discover them by exploring the
     successor relation below. *)
  let predecessors = Vector.make Lr1.n []

  let successors =
    (* We populate all the data structures allocated above, i.e.
       the vectors t_sources, t_symbols, t_targets, nt_sources, nt_symbols,
       nt_targets and predecessors, as well as the tables t_table and
       nt_table, by iterating over all successors. *)
    let next_goto = Index.enumerate goto in
    let next_shift = Index.enumerate shift in
    Vector.init Lr1.n begin fun source ->
      List.fold_left begin fun acc (sym, target) ->
        let target = Lr1.of_g target in
        let index = match sym with
          | Grammar.T t ->
            let t = Terminal.of_g t in
            let index = next_shift () in
            Vector.set t_symbols index t;
            Hashtbl.add t_table (t_pack source t) index;
            of_shift index
          | Grammar.N nt ->
            let nt = Nonterminal.of_g nt in
            let index = next_goto () in
            Vector.set nt_symbols index nt;
            Hashtbl.add nt_table (nt_pack source nt) index;
            of_goto index
        in
        Vector.set sources index source;
        Vector.set targets index target;
        Vector.set_cons predecessors target index;
        index :: acc
      end [] (Lr1.transitions (Lr1.to_g source))
    end

  let successors lr1 = Vector.get successors lr1
  let predecessors lr1 = Vector.get predecessors lr1

  let find_goto source nt = Hashtbl.find nt_table (nt_pack source nt)

  let source i = Vector.get sources i

  let symbol i =
    match split i with
    | L i -> Symbol.N (Vector.get nt_symbols i)
    | R i -> Symbol.T (Vector.get t_symbols i)

  let goto_symbol i = Vector.get nt_symbols i
  let shift_symbol i = Vector.get t_symbols i

  let target i = Vector.get targets i

  let find_goto_target source nt =
    target (of_goto (find_goto source nt))
end

let lr1_predecessors = Vector.init Lr1.n (fun lr1 ->
    List.fold_left
      (fun acc tr -> IndexSet.add (Transition.source tr) acc)
      IndexSet.empty
      (Transition.predecessors lr1)
  )

let lr1set_predecessors lr1s =
  indexset_bind lr1s (Vector.get lr1_predecessors)

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

(* Implementation of simulation reduction *)

module Redgraph : sig
  module AbstractExtra : CARDINAL
  module AbstractState : sig
    include CARDINAL
    val of_lr1 : Lr1.t -> n index
  end
  type abstract_frame = {
    states : Lr1.set;
    mutable goto_nt : Nonterminal.set;
    mutable parent : AbstractState.n index option;
  }

  type derivation
  val derivation_root : derivation

  val abstract_frames : (AbstractState.n, abstract_frame) vector
  val goto_closure :
    (AbstractState.n, (Lr1.set * Lr1.set) list) vector

  val reachable_goto : AbstractState.n index -> Lr1.set

  val derive :
    root:'a ->
    step:('a -> Lr1.n index -> 'a option) ->
    join:('a list -> 'b) ->
    'b Lr1.map
end = struct
  let reductions = Vector.init Lr1.n (fun lr1 ->
      let prepare_goto p =
        (Array.length (Production.rhs p), Production.lhs p)
      in
      let order (d1, n1) (d2, n2) =
        match Int.compare d1 d2 with
        | 0 -> compare_index n1 n2
        | c -> c
      in
      let productions =
        Lr1.reductions lr1
        |> List.filter_map (fun (p, _) ->
            match Production.kind p with
            | `REGULAR -> Some (prepare_goto p)
            | `START -> None
          )
        |> List.sort_uniq order
      in
      let depth = List.fold_left (fun x (d, _) -> max x d) (-1) productions in
      let vector = Array.make (depth + 1) [] in
      List.iter (fun (d,n) -> array_cons vector d n) productions;
      assert (depth = -1 || vector.(depth) <> []);
      vector
    )

  (* Representation of concrete stack suffix *)

  type concrete_frame = {
    state: Lr1.t;
    mutable goto: concrete_frame Lr1.map;
    parent: concrete_frame option;
  }

  (* Representation of abstract stack suffix *)

  module AbstractExtra = Gensym()
  module AbstractState = struct
    include Sum(Lr1)(AbstractExtra)
    let of_lr1 = inj_l
    let fresh () = inj_r (AbstractExtra.fresh ())
  end

  type abstract_frame = {
    states: Lr1.set;
    mutable goto_nt: Nonterminal.set;
    mutable parent: AbstractState.n index option;
  }

  let abstract_frames : (AbstractState.n, abstract_frame) IndexBuffer.t =
    IndexBuffer.make {
      states = IndexSet.empty;
      goto_nt = IndexSet.empty;
      parent = None;
    }

  let make_abstract_frame states =
    { states; goto_nt = IndexSet.empty; parent = None }

  (* Initialize abstract frames associated to each lr1 state *)
  let () = Index.iter Lr1.n (fun lr1 ->
      IndexBuffer.set abstract_frames (AbstractState.inj_l lr1)
        (make_abstract_frame (Vector.get lr1_predecessors lr1))
    )

  let fresh_abstract_frame states =
    let index = AbstractState.fresh () in
    let frame = make_abstract_frame states in
    IndexBuffer.set abstract_frames index frame;
    index

  type stack =
    | Concrete of concrete_frame
    | Abstract of AbstractState.n index

  (* Tabulate the roots, populating all concrete and abstract stacks *)
  let concrete_frames =
    let pop = function
      | Concrete t ->
        begin match t.parent with
          | None -> Abstract (AbstractState.of_lr1 t.state)
          | Some t' -> Concrete t'
        end
      | Abstract t ->
        let frame = IndexBuffer.get abstract_frames t in
        match frame.parent with
        | Some t' -> Abstract t'
        | None ->
          let t' = fresh_abstract_frame (lr1set_predecessors frame.states) in
          frame.parent <- Some t';
          Abstract t'
    in
    let rec goto parent nt =
      match parent with
      | Abstract t ->
        let frame = IndexBuffer.get abstract_frames t in
        frame.goto_nt <- IndexSet.add nt frame.goto_nt
      | Concrete t ->
        let state = Transition.find_goto_target t.state nt in
        if not (IndexMap.mem state t.goto) then (
          let target = {state; goto = IndexMap.empty; parent = Some t} in
          t.goto <- IndexMap.add state target t.goto;
          populate target
        )
    and populate state =
      let frame = ref (Concrete state) in
      let reductions = Vector.get reductions state.state in
      for i = 0 to Array.length reductions - 1 do
        if i <> 0 then frame := pop !frame;
        List.iter (goto !frame) reductions.(i);
      done
    in
    vector_tabulate Lr1.n (fun state ->
        let frame = {state; goto = IndexMap.empty; parent = None} in
        populate frame;
        frame
      )

  (* Compute the trie of derivations *)

  type derivation = {
    mutable children: derivation Lr1.map;
    mutable children_domain: Lr1.set;
    mutable goto_targets: Lr1.set;
  }

  let fresh_derivation () = {
    children = IndexMap.empty;
    children_domain = IndexSet.empty;
    goto_targets = IndexSet.empty;
  }

  let derivation_root = fresh_derivation ()

  let () =
    (* let count = ref 0 in *)
    let delta lr1 d =
      match IndexMap.find_opt lr1 d.children with
      | Some d' -> d'
      | None ->
        let d' = fresh_derivation () in
        d.children <- IndexMap.add lr1 d' d.children;
        d.children_domain <- IndexSet.add lr1 d.children_domain;
        d'
    in
    let rec visit frame =
      List.map
        (delta frame.state)
        (derivation_root :: visit_children frame)
    and visit_children frame =
      IndexMap.fold
        (fun _ frame' acc -> visit frame' @ acc)
        frame.goto
        []
    in
    Index.iter Lr1.n (fun lr1 ->
        let derivations = visit (concrete_frames lr1) in
        List.iter (fun d ->
            (*if not (IndexSet.mem lr1 d.goto_targets) then incr count;*)
            d.goto_targets <- IndexSet.add lr1 d.goto_targets
          ) derivations;
      )
    (* Printf.eprintf "CLOSED DERIVATIONS: %d\n%!" !count *)

  (* Goto closure *)

  (* Force the AbstractFrames set, no new frames should be added from now on *)
  let abstract_frames = IndexBuffer.contents abstract_frames AbstractState.n

  let abstract_root lr1 =
    Vector.get abstract_frames (AbstractState.of_lr1 lr1)

  let goto_closure =
    let table = Vector.make AbstractState.n [] in
    let close i =
      let frame = Vector.get abstract_frames i in
      let close_st st =
        let visited = ref IndexSet.empty in
        let rec visit_nt nt =
          let st' =
            try Transition.find_goto_target st nt
            with Not_found -> assert false
          in
          if not (IndexSet.mem st' !visited) then (
            visited := IndexSet.add st' !visited;
            visit_nts (abstract_root st').goto_nt
          )
        and visit_nts nts =
          IndexSet.iter visit_nt nts
        in
        visit_nts frame.goto_nt;
        !visited
      in
      let add_st st acc = (close_st st, st) :: acc in
      if not (IndexSet.is_empty frame.goto_nt) then
        Vector.set table i (
          IndexSet.fold add_st frame.states []
          |> IndexRefine.annotated_partition
          |> List.map (fun (tgts, srcs) -> IndexSet.of_list srcs, tgts)
        )
    in
    let rec close_all i =
      close i;
      Option.iter close_all (Vector.get abstract_frames i).parent
    in
    Index.iter Lr1.n (fun lr1 -> close_all (AbstractState.of_lr1 lr1));
    table

  let () =
    let count = ref 0 in
    vector_iter goto_closure (fun trs ->
        count := List.fold_left
            (fun acc (_, tgts) -> IndexSet.cardinal tgts + acc)
            !count trs
      );
    Printf.eprintf "GOTO CLOSURE: %d\n" !count

  let reachable_goto =
    (* Compute reachable goto closure *)
    let module X =
      Fix.Fix.ForType
        (struct type t = AbstractState.n index end)
        (struct
          type property = Lr1.set
          let bottom = IndexSet.empty
          let equal = IndexSet.equal
          let is_maximal _ = false
        end)
    in
    let equations index =
      let all_goto =
        List.fold_left
          (fun acc (_srcs, tgts) -> IndexSet.union tgts acc)
          IndexSet.empty
          (Vector.get goto_closure index)
      in
      let targets =
        IndexSet.fold
          (fun lr1 acc -> IndexSet.add (AbstractState.of_lr1 lr1) acc)
          all_goto IndexSet.empty
      in
      fun valuation ->
        let frame = Vector.get abstract_frames index in
        let acc = all_goto in
        let acc = match frame.parent with
          | None -> acc
          | Some parent -> IndexSet.union acc (valuation parent)
        in
        IndexSet.fold
          (fun target acc -> IndexSet.union (valuation target) acc)
          targets acc
    in
    vector_tabulate AbstractState.n (X.lfp equations)

  let derive ~root ~step ~join =
    let map = ref IndexMap.empty in
    let rec visit acc d =
      IndexSet.iter (fun lr1 ->
          match IndexMap.find_opt lr1 !map with
          | None -> map := IndexMap.add lr1 (ref [acc]) !map
          | Some cell -> push cell acc
        ) d.goto_targets;
      IndexMap.iter (fun lr1 d' ->
          match step acc lr1 with
          | None -> ()
          | Some acc -> visit acc d'
        ) d.children
    in
    visit root derivation_root;
    IndexMap.map (fun cell -> join !cell) !map

  let () =
    let string_of_state lr1 =
      (match Lr1.incoming lr1 with
       | None -> "<entrypoint>"
       | Some s -> Symbol.name s) ^
      " (" ^ string_of_index lr1 ^ ")"
    in
    let rec visit path node =
      IndexSet.iter (fun lr1 ->
          Printf.eprintf "%s <- %s\n"
            (String.concat " -> " (List.rev_map string_of_state path))
            (string_of_state lr1)
        )
        node.goto_targets;
      IndexMap.iter (fun lr1 tgt -> visit (lr1 :: path) tgt) node.children
    in
    visit [] derivation_root
end

type 'a transition = Lr1.set * 'a

let normalize_transitions
    cmp (tr : 'a transition list) : 'a list transition list
  =
  IndexRefine.annotated_partition tr
  |> List.map (fun (sg, a) -> sg, List.sort_uniq cmp a)
  |> Misc.group_by
    ~compare:(fun (_, a1) (_, a2) -> List.compare cmp a1 a2)
    ~group:(fun (sg0, a) sgs ->
        (List.fold_left
           (fun sg (sg', _) -> IndexSet.union sg sg')
           sg0 sgs, a)
        )

let normalize_and_merge ~compare ~merge ts =
  normalize_transitions compare ts |> List.map (fun (k, v) -> (k, merge v))

module type DERIVABLE = sig
  type t
  val derive : t -> t transition list
  val merge : t list -> t
  val compare : t -> t -> int
end

module Cache (D : DERIVABLE) : sig
  include DERIVABLE
  val lift : D.t -> t
  val unlift : t -> D.t
end = struct
  type t = {
    d: D.t;
    mutable tr: t transition list option;
  }

  let lift d = { d; tr=None }
  let unlift t = t.d

  let derive t =
    match t.tr with
    | Some tr -> tr
    | None ->
      let tr = List.map (fun (sg, d) -> (sg, lift d)) (D.derive t.d) in
      t.tr <- Some tr;
      tr

  let merge = function
    | [x] -> x
    | xs -> lift (D.merge (List.map unlift xs))

  let compare t1 t2 =
    D.compare t1.d t2.d
end

module Reduce_op (D : DERIVABLE) :
sig
  type t
  type transitions = D.t transition list * t transition list

  val initial : D.t -> transitions
  val derive : t -> transitions
  val compare : t -> t -> int
end =
struct
  type derivations = {
    source: D.t;
    continuations: D.t Lr1.map;
    domain: Lr1.set;
  }

  let initial_derivations d =
    let find_tr lr1 (lr1s, x) =
      if IndexSet.mem lr1 lr1s then Some x else None
    in
    let continuations = Redgraph.derive
        ~root:d
        ~step:(fun d lr1 -> List.find_map (find_tr lr1) (D.derive d))
        ~join:D.merge
    in
    { source = d; continuations; domain = IndexMap.domain continuations }

  type t = {
    derivations: derivations;
    state: Redgraph.AbstractState.n index;
  }

  type transitions = D.t transition list * t transition list

  let compare t1 t2 =
    let c = compare_index t1.state t2.state in
    if c <> 0 then c else
      D.compare t1.derivations.source t2.derivations.source

  let add_abstract_state sg state derivations xs =
    let reachable = Redgraph.reachable_goto state in
    if IndexSet.disjoint reachable derivations.domain
    then xs
    else (sg, {derivations; state}) :: xs

  let initial d =
    let derivations = initial_derivations d in
    let add_direct lr1 d xs = (IndexSet.singleton lr1, d) :: xs in
    let add_reducible lr1 xs =
      add_abstract_state
        (IndexSet.singleton lr1)
        (Redgraph.AbstractState.of_lr1 lr1)
        derivations xs
    in
    let direct = IndexMap.fold add_direct derivations.continuations [] in
    let reducible = index_fold Lr1.n [] add_reducible in
    (direct, reducible)

  let filter_tr sg1 (sg2, v) =
    let sg' = IndexSet.inter sg1 sg2 in
    if IndexSet.is_empty sg' then
      None
    else
      Some (sg', v)

  let derive t =
    let frame = Vector.get Redgraph.abstract_frames t.state in
    let visited = ref IndexSet.empty in
    let direct = ref [] in
    let reducible = ref [] in
    begin match frame.parent with
      | None -> ()
      | Some state ->
        reducible := add_abstract_state Lr1.all state t.derivations !reducible
    end;
    let rec visit_nt (nt : Nonterminal.t) =
      if not (IndexSet.mem nt !visited) then (
        visited := IndexSet.add nt !visited;
        let register_src src acc =
          let tgt = Transition.find_goto_target src nt in
          let srcs = match IndexMap.find_opt tgt acc with
            | None -> IndexSet.singleton src
            | Some srcs -> IndexSet.add src srcs
          in
          IndexMap.add tgt srcs acc
        in
        let tgts = IndexSet.fold register_src frame.states IndexMap.empty in
        IndexMap.iter visit_st tgts
      )
    and visit_st (tgt : Lr1.t) (srcs: Lr1.set) =
      begin match IndexMap.find_opt tgt t.derivations.continuations with
        | None -> ()
        | Some d ->
          List.iter
            (fun tr -> Option.iter (push direct) (filter_tr srcs tr))
            (D.derive d)
      end;
      let state = Redgraph.AbstractState.of_lr1 tgt in
      reducible := add_abstract_state srcs state t.derivations !reducible
    in
    IndexSet.iter visit_nt frame.goto_nt;
    (!direct, !reducible)
end

module RE = struct
  module Uid : sig
    type t = private int
    val t : unit -> t
    val compare : t -> t -> int
  end = struct
    type t = int
    let t = let k = ref 0 in fun () -> incr k; !k
    let compare = Int.compare
  end

  type t = {
    uid: Uid.t;
    desc: desc;
    position: Syntax.position;
  }
  and desc =
    | Set of Lr1.set * string option
    | Alt of t list
    | Seq of t list
    | Star of t
    | Reduce

  let compare t1 t2 =
    Uid.compare t1.uid t2.uid

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
        (Terminal.name t);
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

  let rec transl_desc = function
    | Syntax.Atom (ad, var) -> Set (transl_atom ad, var)
    | Syntax.Alternative rs -> Alt (List.map transl rs)
    | Syntax.Repetition r -> Star (transl r)
    | Syntax.Reduce -> Reduce
    | Syntax.Concat rs -> Seq (List.map transl rs)

  and transl {Syntax. desc; position} =
    {uid = Uid.t (); desc = transl_desc desc; position}
end

module KRE = struct
  type t =
    | Done of {clause: int}
    | More of RE.t * t

  let more re t = More (re, t)

  let rec compare k1 k2 =
    match k1, k2 with
    | Done _, More _ -> -1
    | More _, Done _ -> 1
    | Done c1, Done c2 -> Int.compare c1.clause c2.clause
    | More (t1, k1'), More (t2, k2') ->
      let c = RE.compare t1 t2 in
      if c <> 0 then c else
        compare k1' k2'

  let transl pattern index =
    More (RE.transl pattern, Done {clause=index})
end

module KRESet = struct
  include Set.Make(KRE)

  let prederive ~visited ~reached ~direct ~reduce k =
    let rec loop k =
      if not (mem k !visited) then (
        visited := add k !visited;
        match k with
        | Done {clause} -> push reached clause
        | More (re, k') ->
          match re.desc with
          | Set (s, _) ->
            push direct (s, k')
          | Alt es ->
            List.iter (fun e -> loop (KRE.more e k')) es
          | Star r ->
            loop k';
            loop (More (r, k))
          | Seq es ->
            loop (List.fold_right KRE.more es k')
          | Reduce ->
            push reduce k';
            loop k'
      )
    in
    loop k

  let derive_reduce t : t transition list =
    let visited = ref empty in
    let direct = ref [] in
    let loop k =
      match k with
      | KRE.Done _ -> push direct (Lr1.all, k)
      | k ->
        let reached = ref [] in
        prederive ~visited ~direct ~reached ~reduce:(ref []) k;
        let push_clause clause = push direct (Lr1.all, KRE.Done {clause}) in
        List.iter push_clause !reached
    in
    iter loop t;
    normalize_and_merge ~compare:KRE.compare ~merge:of_list !direct
end

module KRESetMap = Map.Make(KRESet)

module CachedKRESet = Cache(struct
    type t = KRESet.t
    let compare = KRESet.compare
    let derive = KRESet.derive_reduce
    let merge ts = List.fold_left KRESet.union KRESet.empty ts
  end)

module Red = Reduce_op(CachedKRESet)

module RedSet = Set.Make(Red)

module ST = struct
  type t = {
    direct: KRESet.t;
    reduce: RedSet.t;
  }

  let compare t1 t2 =
    let c = KRESet.compare t1.direct t2.direct in
    if c <> 0 then c else
      RedSet.compare t1.reduce t2.reduce

  let lift_direct (k, v) =
    (k, {direct = KRESet.singleton v; reduce = RedSet.empty})

  let lift_cached (k, v) =
    (k, {direct = CachedKRESet.unlift v; reduce = RedSet.empty})

  let lift_reduce (k, v) =
    (k, {direct = KRESet.empty; reduce = RedSet.singleton v})

  let lift_red (d, r) =
    List.map lift_cached d @ List.map lift_reduce r

  let add_redset red tr = lift_red (Red.derive red) @ tr

  let empty = {
    direct = KRESet.empty;
    reduce = RedSet.empty;
  }

  let union t1 t2 = {
    direct = KRESet.union t1.direct t2.direct;
    reduce = RedSet.union t1.reduce t2.reduce;
  }

  let derive ~reduction_cache t =
    let visited = ref KRESet.empty in
    let reached = ref [] in
    let direct = ref [] in
    let reduce = ref [] in
    let loop k = KRESet.prederive ~visited ~reached ~reduce ~direct k in
    KRESet.iter loop t.direct;
    let reduce = KRESet.of_list !reduce in
    let tr =
      match KRESetMap.find_opt reduce !reduction_cache with
      | Some tr -> tr
      | None ->
        let tr = lift_red (Red.initial (CachedKRESet.lift reduce)) in
        reduction_cache := KRESetMap.add reduce tr !reduction_cache;
        tr
    in
    let tr = RedSet.fold add_redset t.reduce tr in
    let tr =
      normalize_and_merge
        ~compare:compare
        ~merge:(List.fold_left union empty)
        (List.map lift_direct !direct @ tr)
    in
    (BitSet.IntSet.of_list !reached, tr)
end

module DFA = Map.Make(ST)

let () = (
  let entry = List.hd lexer_definition.entrypoints in
  let cases =
    entry.Syntax.clauses
    |> List.mapi (fun i case -> KRE.transl case.Syntax.pattern i)
    |> KRESet.of_list
  in
  let reduction_cache = ref KRESetMap.empty in
  let dfa = ref DFA.empty in
  let rec process_st = function
    | [] -> ()
    | st :: todo ->
      match DFA.find_opt st !dfa with
      | Some _ -> process_st todo
      | None ->
        let _, tgts as tr = ST.derive ~reduction_cache st in
        dfa := DFA.add st tr !dfa;
        process_st (List.map snd tgts @ todo)
  in
  process_st [{ST. direct = cases; reduce = RedSet.empty}];
  (*let doc = Cmon.list_map (KRE.cmon ()) kst.direct in
  if verbose then (
    Format.eprintf "%a\n%!" Cmon.format (Syntax.print_entrypoints entry);
    Format.eprintf "%a\n%!" Cmon.format doc;
  );*)
  Format.eprintf "(* %d states *)\n%!" (DFA.cardinal !dfa);
  begin match !output_name with
    | None ->
      prerr_endline "No output file provided (option -o). Giving up.";
      exit 1
    | Some path ->
      let oc = open_out_bin path in
      output_string oc (snd lexer_definition.header);
      output_char oc '\n';
      (*let gen_table = DFA.minimize dfa in
        Clause.gencode oc clauses;*)
      output_char oc '\n';
      output_string oc (snd lexer_definition.trailer);
      output_char oc '\n';
      (*gen_table oc;*)
      close_out oc
  end
)
