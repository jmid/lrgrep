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

(* General purpose definitions *)

open Cmdline
open Utils.Misc

(*let rec interp_kre kres reds stack =
  let visited = ref KRESet.empty in
  let reached = ref [] and direct = ref [] and reduce = ref [] in
  let kderive kre = KRESet.prederive ~visited ~reached ~direct ~reduce kre in
  KRESet.iter kderive kres;
  let reduce = KRESet.of_list !reduce in
  eprintf "------------------------\n";
  eprintf "Matcher definition:\n%a\n" print_cmon (KRESet.cmon kres);
  eprintf "Ongoing reductions: [%s]\n"
    (string_concat_map ";" string_of_index (IndexSet.elements reds));
  eprintf "Matching actions: [%s]\n"
    (string_concat_map ";" string_of_int !reached);
  eprintf "New reductions:\n%a\n" print_cmon (KRESet.cmon reduce);
  match stack with
  | [] -> eprintf "End of stack\n"
  | x :: xs -> (
    let lr1 = Index.of_int Lr1.n x in
    eprintf "Parser in state %d - %s\n" x (Lr1.to_string lr1);
    let reds =
      if KRESet.is_empty reduce
      then reds
      else redmap_add reds (Redgraph.State.of_lr1 lr1) reduce
    in
    let step_kre acc (sg, kre') =
      if IndexSet.mem lr1 sg
      then KRESet.add kre' acc
      else acc
    in
    let kres = List.fold_left step_kre KRESet.empty !direct in
    interp_kre kres reds xs
  )*)

let gen_code entry oc vars clauses =
  let print fmt = Printf.fprintf oc fmt in
  print
    "let execute_%s %s : int * %s.MenhirInterpreter.element option array -> _ option = function\n"
    entry.Syntax.name
    (String.concat " " entry.Syntax.args)
    (String.capitalize_ascii (Filename.basename Grammar_raw.Grammar.basename));
  List.iteri (fun index (vars, clause) ->
      print "  | %d, [|%s|] -> begin\n%s\n    end\n"
        index
        (String.concat ";" vars)
        (match clause.Syntax.action with
         | Unreachable -> "failwith \"Should be unreachable\""
         | Partial (_, str) -> str
         | Total (_, str) -> "Some (" ^ str ^ ")")
    ) (List.combine vars clauses);
  print "  | _ -> failwith \"Invalid action\"\n\n"

let output_table oc entry vars (initial : Dfa.Repr.t) (program, table, remap) =
  let print fmt = Printf.fprintf oc fmt in
  print "module Table_%s : Lrgrep_runtime.Parse_errors = struct\n"
    entry.Syntax.name;
  print "  let arities = [|%s|]\n"
    (string_concat_map ";" (fun a -> string_of_int (List.length a)) vars);
  print "  let initial = %d\n" remap.(initial.id);
  print "  let table = %S\n" table;
  print "  let program = %S\n" program;
  print "end\n"

let process_entry oc entry =
  let cases, vars =
    let transl_case i case =
      let var_count = ref 0 in
      let vars = ref [] in
      let alloc name =
        let id = !var_count in
        Utils.Misc.push vars name;
        incr var_count;
        (i, id)
      in
      let kre = Transl.transl_kre alloc case.Syntax.pattern i in
      let vars = List.rev !vars in
      (kre, vars)
    in
    List.split (List.mapi transl_case entry.Syntax.clauses)
  in
  let cases = Regexp.KRESet.of_list cases in
  let dfa, initial = Dfa.Repr.gen (Dfa.State.make cases) in
  Format.eprintf "(* %d states *)\n%!" (Dfa.StateMap.cardinal dfa);
  output_char oc '\n';
  gen_code entry oc vars entry.Syntax.clauses;
  output_char oc '\n';
  output_table oc entry vars initial (Dfa.gen_table dfa)

let () = (
  (*let doc = Cmon.list_map (KRE.cmon ()) kst.direct in
  if verbose then (
    Format.eprintf "%a\n%!" Cmon.format (Syntax.print_entrypoints entry);
    Format.eprintf "%a\n%!" Cmon.format doc;
  );*)
  begin match !output_name with
    | None ->
      prerr_endline "No output file provided (option -o). Giving up.";
      exit 1
    | Some path ->
      let oc = open_out_bin path in
      output_string oc (snd lexer_definition.header);
      List.iter (process_entry oc) lexer_definition.entrypoints;
      output_char oc '\n';
      output_string oc (snd lexer_definition.trailer);
      close_out oc
  end;
  (*Array.iter (fun (name, stack) ->
      eprintf "Evaluating case %s\n" name;
      (*eval_dfa dfa initial stack;*)
      interp_st {ST.direct=cases; reduce=RedSet.empty} stack;
      (*interp_kre cases IndexSet.empty stack;*)
      eprintf "------------------------\n\n";
    ) Sample.tests*)
  (* Print matching functions *)
)
