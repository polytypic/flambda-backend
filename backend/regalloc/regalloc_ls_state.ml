[@@@ocaml.warning "+a-30-40-41-42"]

open! Int_replace_polymorphic_compare
open! Regalloc_utils
open! Regalloc_ls_utils

type t =
  { mutable intervals : Interval.t list;
    active : ClassIntervals.t array;
    stack_slots : Regalloc_stack_slots.t;
    instruction_id : InstructionId.sequence
  }

let for_fatal t =
  ( List.map t.intervals ~f:Interval.copy,
    Array.map t.active ~f:ClassIntervals.copy )

let[@inline] make ~stack_slots ~last_used =
  let intervals = [] in
  let active =
    Array.init Proc.num_register_classes ~f:(fun _ -> ClassIntervals.make ())
  in
  let instruction_id = InstructionId.make_sequence ~last_used () in
  { intervals; active; stack_slots; instruction_id }

let[@inline] update_intervals state map =
  let active = state.active in
  Array.iter active ~f:ClassIntervals.clear;
  state.intervals
    <- Reg.Tbl.fold
         (fun reg interval acc ->
           match reg.loc with
           | Reg _ ->
             let reg_class = Proc.register_class reg in
             active.(reg_class).fixed <- interval :: active.(reg_class).fixed;
             acc
           | Stack _ | Unknown -> interval :: acc)
         map []
       |> List.sort ~cmp:(fun (left : Interval.t) (right : Interval.t) ->
              Int.compare left.begin_ right.begin_);
  if debug then log_intervals ~kind:"regular" state.intervals;
  Array.iter active ~f:(fun (intervals : ClassIntervals.t) ->
      intervals.fixed
        <- List.sort
             ~cmp:(fun (left : Interval.t) (right : Interval.t) ->
               Int.compare right.end_ left.end_)
             intervals.fixed;
      if debug then log_intervals ~kind:"fixed" intervals.fixed)

let[@inline] iter_intervals state ~f = List.iter state.intervals ~f

let[@inline] fold_intervals state ~f ~init =
  List.fold_left state.intervals ~f ~init

let[@inline] release_expired_intervals state ~pos =
  Array.iter state.active ~f:(fun x ->
      ClassIntervals.release_expired_intervals x ~pos)

let[@inline] active state ~reg_class = state.active.(reg_class)

let[@inline] active_classes state = state.active

let[@inline] stack_slots state = state.stack_slots

let[@inline] get_and_incr_instruction_id state =
  InstructionId.get_next state.instruction_id

let rec check_ranges (prev : Range.t) (cell : Range.t DLL.cell option) : int =
  if prev.begin_ > prev.end_
  then fatal "Regalloc_ls_state.check_ranges: prev.begin_ > prev.end_";
  match cell with
  | None -> prev.end_
  | Some cell ->
    let value = DLL.value cell in
    if prev.end_ >= value.begin_
    then fatal "Regalloc_ls_state.check_ranges: prev.end_ >= hd.begin_";
    check_ranges value (DLL.next cell)

let rec check_intervals (prev : Interval.t) (l : Interval.t list) : unit =
  if prev.begin_ > prev.end_
  then fatal "Regalloc_ls_state.check_intervals: prev.begin_ > prev.end_";
  (match DLL.hd_cell prev.ranges with
  | None -> fatal "Regalloc_ls_state.check_intervals: no ranges"
  | Some cell ->
    let value = DLL.value cell in
    if value.begin_ <> prev.begin_
    then fatal "Regalloc_ls_state.check_intervals: hd.begin_ <> prev.begin_";
    let end_ = check_ranges value (DLL.next cell) in
    if end_ <> prev.end_
    then fatal "Regalloc_ls_state.check_intervals: end_ <> prev.end_");
  match l with
  | [] -> ()
  | hd :: tl ->
    if prev.begin_ > hd.begin_
    then fatal "Regalloc_ls_state.check_intervals: prev.begin_ > hd.begin_";
    check_intervals hd tl

let rec is_in_a_range ls_order (cell : Range.t DLL.cell option) : bool =
  match cell with
  | None -> false
  | Some cell ->
    let value = DLL.value cell in
    (ls_order >= value.begin_ && ls_order <= value.end_)
    || is_in_a_range ls_order (DLL.next cell)

let[@inline] invariant_intervals state cfg_with_infos =
  if debug && Lazy.force invariants
  then (
    (match state.intervals with [] -> () | hd :: tl -> check_intervals hd tl);
    let interval_map : Interval.t Reg.Map.t =
      fold_intervals state ~init:Reg.Map.empty ~f:(fun acc interval ->
          Reg.Map.update interval.reg
            (function
              | None -> Some interval
              | Some _reg ->
                fatal
                  "Regalloc_ls_state.invariant_intervals: state.intervals \
                   duplicate register %a"
                  Printreg.reg interval.reg)
            acc)
    in
    let check_instr : type a. a Cfg.instruction -> unit =
     fun instr ->
      Reg.Set.iter
        (fun reg ->
          match Reg.Map.find_opt reg interval_map with
          | None ->
            fatal
              "Regalloc_ls_state.invariant_intervals: register %a is not in \
               interval_map"
              Printreg.reg reg
          | Some interval ->
            if instr.ls_order < interval.begin_
            then
              fatal
                "Regalloc_ls_state.invariant_intervals: instr.ls_order < \
                 interval.begin_";
            if instr.ls_order > interval.end_
            then
              fatal
                "Regalloc_ls_state.invariant_intervals: instr.ls_order > \
                 interval.end_";
            if not (is_in_a_range instr.ls_order (DLL.hd_cell interval.ranges))
            then
              fatal
                "Regalloc_ls_state.invariant_intervals: not (is_in_a_range \
                 instr.ls_order interval.ranges)")
        instr.live
    in
    Cfg_with_layout.iter_instructions
      (Cfg_with_infos.cfg_with_layout cfg_with_infos)
      ~instruction:check_instr ~terminator:check_instr)

let invariant_active_field (reg_class : int) (field_name : string)
    (l : Interval.t list) =
  let rec is prev l =
    match l with
    | [] -> ()
    | hd :: tl ->
      if hd.Interval.end_ > prev.Interval.end_
      then
        fatal
          "Regalloc_ls_state.invariant_active_field: active.(%d).%s is not \
           sorted"
          reg_class field_name
      else is hd tl
  in
  match l with [] -> () | hd :: tl -> is hd tl

let[@inline] invariant_active state =
  if debug && Lazy.force invariants
  then
    Array.iteri state.active ~f:(fun reg_class intervals ->
        invariant_active_field reg_class "fixed " intervals.ClassIntervals.fixed;
        invariant_active_field reg_class "active "
          intervals.ClassIntervals.active;
        invariant_active_field reg_class "inactive "
          intervals.ClassIntervals.inactive)
