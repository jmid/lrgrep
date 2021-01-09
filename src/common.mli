(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*          Damien Doligez, projet Moscova, INRIA Rocquencourt            *)
(*                                                                        *)
(*   Copyright 2002 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

type line_tracker
val open_tracker : string -> out_channel -> line_tracker
val close_tracker : line_tracker -> unit
val copy_chunk :
  in_channel -> out_channel -> line_tracker -> Syntax.location -> bool -> unit

val quiet_mode : bool ref
val dry_run : bool ref
val dump_parsetree : bool ref
