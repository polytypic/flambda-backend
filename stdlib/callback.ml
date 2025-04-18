# 2 "callback.ml"
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

open! Stdlib

[@@@ocaml.flambda_o3]

(* Registering OCaml values with the C runtime for later callbacks *)

module Safe = struct
  external register_named_value : string -> Obj.t -> unit @@ portable
    = "caml_register_named_value"

  let register name v =
    register_named_value name (Obj.repr v)

  let register_exception name (exn : exn) =
    let exn = Obj.repr exn in
    let slot = if Obj.tag exn = Obj.object_tag then exn else Obj.field exn 0 in
    register_named_value name slot
end

let register name v = Safe.register name (Obj.magic_portable v)
let register_exception name exn = Safe.register_exception name (Obj.magic_portable exn)
