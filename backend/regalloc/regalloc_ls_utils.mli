[@@@ocaml.warning "+a-30-40-41-42"]

open Regalloc_utils
module DLL = Flambda_backend_utils.Doubly_linked_list

val log : ?no_eol:unit -> ('a, Format.formatter, unit) format -> 'a

val indent : unit -> unit

val dedent : unit -> unit

val reset_indentation : unit -> unit

val log_body_and_terminator :
  Cfg.basic_instruction_list ->
  Cfg.terminator Cfg.instruction ->
  liveness ->
  unit

val log_cfg_with_infos : Cfg_with_infos.t -> unit

val iter_cfg_dfs : Cfg.t -> f:(Cfg.basic_block -> unit) -> unit

(* The [trap_handler] parameter to the [instruction] and [terminator] functions
   is set to [true] iff the instruction is the first one of a block which is a
   trap handler. *)
val iter_instructions_dfs :
  Cfg_with_layout.t ->
  instruction:(trap_handler:bool -> Cfg.basic Cfg.instruction -> unit) ->
  terminator:(trap_handler:bool -> Cfg.terminator Cfg.instruction -> unit) ->
  unit

module Range : sig
  (* Similar to [Interval.range] (in "backend/interval.mli"). *)
  type t =
    { mutable begin_ : int;
      mutable end_ : int
    }

  val copy : t -> t

  val print : Format.formatter -> t -> unit

  val overlap : t DLL.t -> t DLL.t -> bool

  val is_live : t DLL.t -> pos:int -> bool

  val remove_expired : t DLL.t -> pos:int -> unit
end

module Interval : sig
  (* Similar to [Interval.t] (in "backend/interval.mli"). *)
  type t =
    { reg : Reg.t;
      mutable begin_ : int;
      mutable end_ : int;
      ranges : Range.t DLL.t
    }

  val copy : t -> t

  val print : Format.formatter -> t -> unit

  val overlap : t -> t -> bool

  val is_live : t -> pos:int -> bool

  val remove_expired : t -> pos:int -> unit

  module List : sig
    val release_expired_fixed : t list -> pos:int -> t list

    val insert_sorted : t list -> t -> t list
  end
end

module ClassIntervals : sig
  (* Similar to [Linscan.class_intervals] (in "backend/linscan.mln"). *)
  type t =
    { mutable fixed : Interval.t list;
      mutable active : Interval.t list;
      mutable inactive : Interval.t list
    }

  val make : unit -> t

  val copy : t -> t

  val print : Format.formatter -> t -> unit

  val clear : t -> unit

  val release_expired_intervals : t -> pos:int -> unit
end

val log_interval : kind:string -> Interval.t -> unit

val log_intervals : kind:string -> Interval.t list -> unit
