(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*           Mark Shinwell and Leo White, Jane Street Europe              *)
(*                                                                        *)
(*   Copyright 2015--2020 Jane Street Group LLC                           *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(* The following is a "big endian" implementation. *)

type key = int

external int_clz : int -> (int[@untagged])
  = "caml_int_clz_tagged_to_tagged" "caml_int_clz_tagged_to_untagged"
  [@@noalloc] [@@builtin] [@@no_effects] [@@no_coeffects]

(* A bit [b], represented as a bitmask with only [b] set. This makes testing an
   individual bit very cheap. *)
type bit = int

(* A sequence of bits matched by the beginning (big-endian) of every key in a
   subtree. It has some length, represented as the first [bit] after the entire
   prefix. *)
type prefix = int

let zero_bit i bit = i land bit = 0

(* Most significant 1 bit *)
let highest_bit x = 1 lsl (62 - int_clz x)

(* Highest bit at which [prefix0] and [prefix1] differ *)
let branching_bit prefix0 prefix1 = highest_bit (prefix0 lxor prefix1)

(* Keep only the bits strictly higher than [i] *)
let mask i bit = i land -(bit lsl 1)

(* Does [i] match [prefix], whose length is [bit]? In other words, does [i]
   match [prefix] at every position strictly higher than [bit]? *)
let match_prefix i prefix bit = mask i bit = prefix

let equal_prefix prefix0 bit0 prefix1 bit1 = bit0 = bit1 && prefix0 = prefix1

let higher bit0 bit1 =
  (* Need to do _unsigned_ int comparison *)
  match bit0 < 0, bit1 < 0 with
  | false, false -> bit0 > bit1
  | _, true -> false (* the only bit < 0 is 0x4000..., which is the highest *)
  | true, false -> true

(* Is [prefix0], of length [bit0], a sub-prefix of [prefix1], of length
   [bit1]? *)
let includes_prefix prefix0 bit0 prefix1 bit1 =
  higher bit0 bit1 && match_prefix prefix1 prefix0 bit0

(* Provides a total ordering over [(prefix, bit)] pairs. Not otherwise
   specified. (Only useful for implementing [compare], which is similarly
   loosely specified.) *)
let compare_prefix prefix0 bit0 prefix1 bit1 =
  (* Signed comparison is fine here, so long as it's a total ordering *)
  let c = compare bit0 bit1 in
  if c = 0 then compare prefix0 prefix1 else c

(* A tree structure that will be used to implement a datatype, either sets or
   maps. Many algorithms operate identically on sets and maps, so they are
   implemented in the functor [Tree_operations] over this module type. *)
module type Tree = sig
  (* A Patricia tree. For a prefix P, we write that the tree has prefix P if
     every node in the tree has a key that matches P. (Note that a tree with
     prefix P also has any sub-prefix of P. For instance, if the tree has prefix
     011, it also has prefix 01.) *)
  type 'a t

  (* A witness that ['a] is a valid type for a value stored in the tree. Maps
     will allow ['a] to be any value but sets will only allow [unit]. *)
  type 'a is_value [@@immediate]

  (* Deduce that ['a] is a value type from a pre-existing ['a t]. *)
  val is_value_of : 'a t -> 'a is_value

  (* An empty tree. Since it has no nodes, it is safe to treat it as having any
     prefix. *)
  val empty : 'a is_value -> 'a t

  (* A tree containing a single key-value pair. It has the entire key as a
     prefix. *)
  val leaf : 'a is_value -> key -> 'a -> 'a t

  (* A tree with the given prefix, the length of the prefix, and two subtrees.
     If the prefix is P, we require that [t0] has prefix P0 and [t1] has prefix
     P1 (note that this is big-endian notation). For efficiency, [t0] and [t1]
     are assumed to be non-empty. *)
  val branch : prefix -> bit -> 'a t -> 'a t -> 'a t

  (* A view on a given node, corresponding to which of [empty], [leaf], or
     [branch] constructed it. Passing the fields back in as arguments will
     construct an identical tree. *)
  type 'a descr =
    | Empty
    | Leaf of key * 'a
    | Branch of prefix * bit * 'a t * 'a t

  val descr : 'a t -> 'a descr

  module Binding : sig
    type 'a t

    val create : key -> 'a -> 'a t

    val key : _ t -> key

    val value : 'a is_value -> 'a t -> 'a
  end

  module Callback : sig
    type ('a, 'b) t

    val of_func : 'a is_value -> (key -> 'a -> 'b) -> ('a, 'b) t

    val call : ('a, 'b) t -> key -> 'a -> 'b
  end
end

module Set0 = struct
  type 'a t =
    | Empty : unit t
    | Leaf : key -> unit t
    | Branch : prefix * bit * unit t * unit t -> unit t

  type 'a is_value = Unit : unit is_value

  let[@inline always] is_value_of (type a) (t : a t) : a is_value =
    (* Crucially, this compiles down to just [Unit], making this function cost
       nothing. *)
    match t with Empty -> Unit | Leaf _ -> Unit | Branch _ -> Unit

  let[@inline always] empty (type a) (Unit : a is_value) : a t = Empty

  let[@inline always] leaf (type a) (Unit : a is_value) elt (() : a) : a t =
    Leaf elt

  let[@inline always] branch (type a) prefix bit (t0 : a t) (t1 : a t) : a t =
    let Unit = is_value_of t0 in
    Branch (prefix, bit, t0, t1)

  type 'a descr =
    | Empty
    | Leaf of key * 'a
    | Branch of prefix * bit * 'a t * 'a t

  let descr (type a) : a t -> a descr = function
    | Empty -> Empty
    | Leaf elt -> Leaf (elt, ())
    | Branch (prefix, bit, t0, t1) -> Branch (prefix, bit, t0, t1)

  module Binding = struct
    type _ t = key

    let[@inline always] create i _ = i

    let[@inline always] key i = i

    let[@inline always] value (type a) (Unit : a is_value) (_i : a t) : a = ()
  end

  module Callback = struct
    type (_, 'b) t = key -> 'b

    let[@inline always] of_func (type a) (Unit : a is_value)
        (f : key -> a -> 'b) key =
      (f [@inlined hint]) key ()

    let[@inline always] call f key _ = f key
  end
end

module _ : Tree = Set0

module Map0 = struct
  type 'a t =
    | Empty
    | Leaf of key * 'a
    | Branch of prefix * bit * 'a t * 'a t

  type _ is_value = Any : 'a is_value

  let[@inline always] is_value_of _ = Any

  let[@inline always] empty Any = Empty

  let[@inline always] leaf Any i d = Leaf (i, d)

  let[@inline always] branch prefix bit t0 t1 = Branch (prefix, bit, t0, t1)

  type 'a descr = 'a t =
    | Empty
    | Leaf of key * 'a
    | Branch of prefix * bit * 'a t * 'a t

  let descr = Fun.id

  module Binding = struct
    type 'a t = key * 'a

    let[@inline always] create i d = i, d

    let[@inline always] key (i, _d) = i

    let[@inline always] value Any (_i, d) = d
  end

  module Callback = struct
    type ('a, 'b) t = key -> 'a -> 'b

    let[@inline always] call f i d = f i d

    let[@inline always] of_func Any f = f
  end
end

module _ : Tree = Map0

module Tree_operations (Tree : Tree) : sig
  open! Tree

  val is_empty : 'a t -> bool

  val singleton : 'a is_value -> key -> 'a -> 'a t

  val mem : key -> 'a t -> bool

  val add : key -> 'a -> 'a t -> 'a t

  val replace : key -> ('a -> 'a) -> 'a t -> 'a t

  val update : key -> ('a option -> 'a option) -> 'a t -> 'a t

  val remove : key -> 'a t -> 'a t

  val union : (key -> 'a -> 'a -> 'a option) -> 'a t -> 'a t -> 'a t

  val subset : 'a t -> 'a t -> bool

  val find : key -> 'a t -> 'a

  val inter : 'c is_value -> (key -> 'a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t

  val inter_domain_is_non_empty : 'a t -> 'b t -> bool

  val diff : 'a t -> 'b t -> 'a t

  val cardinal : _ t -> int

  val iter : ('a, unit) Callback.t -> 'a t -> unit

  val fold : ('a, 'b -> 'b) Callback.t -> 'a t -> 'b -> 'b

  val for_all : ('a, bool) Callback.t -> 'a t -> bool

  val exists : ('a, bool) Callback.t -> 'a t -> bool

  val filter : ('a, bool) Callback.t -> 'a t -> 'a t

  val partition : ('a, bool) Callback.t -> 'a t -> 'a t * 'a t

  val choose : 'a t -> 'a Binding.t

  val choose_opt : 'a t -> 'a Binding.t option

  val min_binding : 'a t -> 'a Binding.t

  val min_binding_opt : 'a t -> 'a Binding.t option

  val max_binding : 'a t -> 'a Binding.t

  val max_binding_opt : 'a t -> 'a Binding.t option

  val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool

  val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int

  val split :
    found:('a -> 'b) -> not_found:'b -> key -> 'a t -> 'a t * 'b * 'a t

  val to_list : 'a t -> 'a Binding.t list

  val merge :
    'c is_value ->
    (key -> 'a option -> 'b option -> 'c option) ->
    'a t ->
    'b t ->
    'c t

  val find_opt : key -> 'a t -> 'a option

  val get_singleton : 'a t -> 'a Binding.t option

  val map : 'b is_value -> ('a -> 'b) -> 'a t -> 'b t

  val map_sharing : ('a -> 'a) -> 'a t -> 'a t

  val mapi : 'b is_value -> ('a, 'b) Callback.t -> 'a t -> 'b t

  val filter_map : 'b is_value -> (key -> 'a -> 'b option) -> 'a t -> 'b t

  val filter_map_sharing : (key -> 'a -> 'a option) -> 'a t -> 'a t

  type 'a iterator

  val iterator : 'a t -> 'a iterator

  val current : 'a iterator -> 'a Binding.t option

  val advance : 'a iterator -> 'a iterator

  val seek : 'a iterator -> key -> 'a iterator

  val to_seq : 'a t -> 'a Binding.t Seq.t

  val of_list : 'a is_value -> 'a Binding.t list -> 'a t

  val disjoint_union :
    ?eq:('a -> 'a -> bool) ->
    print:(Format.formatter -> key -> unit) ->
    'a t ->
    'a t ->
    'a t

  val map_keys : (key -> key) -> 'a t -> 'a t

  val valid : 'a t -> bool
end = struct
  include Tree

  (* A relaxed version of [Tree.branch], allowing [t0] and/or [t1] to be empty.
     It still requires that [t0] and [t1] have prefix [P0] and [P1],
     respectively, where [P] is the bits in [prefix] lower than [bit]. *)
  let branch prefix bit t0 t1 =
    match (descr [@inlined hint]) t0, (descr [@inlined hint]) t1 with
    | Empty, _ -> t1
    | _, Empty -> t0
    | (Leaf _ | Branch _), (Leaf _ | Branch _) -> Tree.branch prefix bit t0 t1
    [@@inline always]

  let branch_non_empty prefix bit t0 t1 =
    (Tree.branch [@inlined hint]) prefix bit t0 t1
    [@@inline always]

  let is_empty t =
    match descr t with Empty -> true | Leaf _ -> false | Branch _ -> false

  let singleton iv i d = leaf iv i d

  let rec mem i t =
    match descr t with
    | Empty -> false
    | Leaf (j, _) -> j = i
    | Branch (prefix, bit, t0, t1) ->
      if not (match_prefix i prefix bit)
      then false
      else if zero_bit i bit
      then mem i t0
      else mem i t1

  (* Join two subtrees whose prefixes are disjoint (neither includes the other)
     but otherwise arbitrary. Assumes that [t0] has prefix [prefix0] and [t1]
     has prefix [prefix1]. (Most functions that take a prefix also take a bit
     representing the length of the prefix, but in this case, the lengths don't
     matter: the prefixes must differ at some shorter length anyway.) *)
  let join prefix0 t0 prefix1 t1 =
    let bit = branching_bit prefix0 prefix1 in
    if zero_bit prefix0 bit
    then branch (mask prefix0 bit) bit t0 t1
    else branch (mask prefix0 bit) bit t1 t0

  (* CR mshinwell: This is now [add_or_replace], like [Map] *)
  let rec add i d t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> leaf iv i d
    | Leaf (j, _) -> if i = j then leaf iv i d else join i (leaf iv i d) j t
    | Branch (prefix, bit, t0, t1) ->
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then branch_non_empty prefix bit (add i d t0) t1
        else branch_non_empty prefix bit t0 (add i d t1)
      else join i (leaf iv i d) prefix t

  let rec replace key f t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> empty iv
    | Leaf (key', datum) ->
      if key = key'
      then
        let datum = f datum in
        leaf iv key datum
      else t
    | Branch (prefix, bit, t0, t1) ->
      if match_prefix key prefix bit
      then
        if zero_bit key bit
        then branch_non_empty prefix bit (replace key f t0) t1
        else branch_non_empty prefix bit t0 (replace key f t1)
      else t

  let rec update key f t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> (
      match f None with None -> empty iv | Some datum -> leaf iv key datum)
    | Leaf (key', datum) -> (
      if key = key'
      then
        match f (Some datum) with
        | None -> empty iv
        | Some datum -> leaf iv key datum
      else
        match f None with
        | None -> t
        | Some datum -> join key (leaf iv key datum) key' t)
    | Branch (prefix, bit, t0, t1) -> (
      if match_prefix key prefix bit
      then
        if zero_bit key bit
        then branch prefix bit (update key f t0) t1
        else branch prefix bit t0 (update key f t1)
      else
        match f None with
        | None -> t
        | Some datum -> join key (leaf iv key datum) prefix t)

  let rec remove i t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> empty iv
    | Leaf (j, _) -> if i = j then empty iv else t
    | Branch (prefix, bit, t0, t1) ->
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then branch prefix bit (remove i t0) t1
        else branch prefix bit t0 (remove i t1)
      else t

  (* CR pchambart: union x x is expensive, while it could be O(1). This would
     require that we demand f x x = x *)
  (* CR-someday lmaurer: Generalize [merge] so that we can implement this in
     terms of it. Rather than one callback, it should take three, along the
     lines of Haskell's implementation; this would let us preserve sharing (see
     Haskell's [Data.IntMap] for details). *)
  let rec union f t0 t1 =
    let iv = is_value_of t0 in
    match descr t0, descr t1 with
    | Empty, _ -> t1
    | _, Empty -> t0
    | Leaf (i, d0), Leaf (j, d1) when i = j -> (
      match f i d0 d1 with None -> empty iv | Some datum -> leaf iv i datum)
    | Leaf (i, _), Leaf (j, _) -> join i t0 j t1
    | Leaf (i, d), Branch (prefix, bit, t10, t11) ->
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then branch prefix bit (union f t0 t10) t11
        else branch prefix bit t10 (union f t0 t11)
      else join i (leaf iv i d) prefix t1
    | Branch (prefix, bit, t00, t01), Leaf (i, d) ->
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then branch prefix bit (union f t00 t1) t01
        else branch prefix bit t00 (union f t01 t1)
      else join i (leaf iv i d) prefix t0
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then branch prefix0 bit0 (union f t00 t10) (union f t01 t11)
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0
        then branch prefix0 bit0 (union f t00 t1) t01
        else branch prefix0 bit0 t00 (union f t01 t1)
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then
        if zero_bit prefix0 bit1
        then branch prefix1 bit1 (union f t0 t10) t11
        else branch prefix1 bit1 t10 (union f t0 t11)
      else join prefix0 t0 prefix1 t1

  (* CR mshinwell: rename to subset_domain and inter_domain? *)

  let rec subset t0 t1 =
    match descr t0, descr t1 with
    | Empty, _ -> true
    | _, Empty -> false
    | Branch _, Leaf _ -> false
    | Leaf (i, _), _ -> mem i t1
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then subset t00 t10 && subset t01 t11
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then if zero_bit prefix0 bit1 then subset t0 t10 else subset t0 t11
      else false

  (* CR lmaurer: Should use [raise_notrace] internally *)
  let rec find i t =
    match descr t with
    | Empty -> raise Not_found
    | Leaf (j, d) -> if j = i then d else raise Not_found
    | Branch (prefix, bit, t0, t1) ->
      if not (match_prefix i prefix bit)
      then raise Not_found
      else if zero_bit i bit
      then find i t0
      else find i t1

  let rec inter iv f t0 t1 =
    match descr t0, descr t1 with
    | Empty, _ -> empty iv
    | _, Empty -> empty iv
    | Leaf (i, d0), _ -> (
      match find i t1 with
      | exception Not_found -> empty iv
      | d1 -> leaf iv i (f i d0 d1))
    | _, Leaf (i, d1) -> (
      match find i t0 with
      | exception Not_found -> empty iv
      | d0 -> leaf iv i (f i d0 d1))
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then branch prefix0 bit0 (inter iv f t00 t10) (inter iv f t01 t11)
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0 then inter iv f t00 t1 else inter iv f t01 t1
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then
        if zero_bit prefix0 bit1 then inter iv f t0 t10 else inter iv f t0 t11
      else empty iv

  let rec inter_domain_is_non_empty t0 t1 =
    match descr t0, descr t1 with
    | Empty, _ | _, Empty -> false
    | Leaf (i, _), _ -> mem i t1
    | _, Leaf (i, _) -> mem i t0
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then
        inter_domain_is_non_empty t00 t10 || inter_domain_is_non_empty t01 t11
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0
        then inter_domain_is_non_empty t00 t1
        else inter_domain_is_non_empty t01 t1
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then
        if zero_bit prefix0 bit1
        then inter_domain_is_non_empty t0 t10
        else inter_domain_is_non_empty t0 t11
      else false

  let rec diff t0 t1 =
    let iv = is_value_of t0 in
    match descr t0, descr t1 with
    | Empty, _ -> empty iv
    | _, Empty -> t0
    | Leaf (i, _), _ -> if mem i t1 then empty iv else t0
    | _, Leaf (i, _) -> remove i t0
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then branch prefix0 bit0 (diff t00 t10) (diff t01 t11)
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0
        then branch prefix0 bit0 (diff t00 t1) t01
        else branch prefix0 bit0 t00 (diff t01 t1)
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then if zero_bit prefix0 bit1 then diff t0 t10 else diff t0 t11
      else t0

  let rec cardinal t =
    match descr t with
    | Empty -> 0
    | Leaf _ -> 1
    | Branch (_, _, t0, t1) -> cardinal t0 + cardinal t1

  let[@inline always] order_branches bit t0 t1 =
    if bit < 0 then t1, t0 else t0, t1

  let rec unsigned_iter f t =
    match descr t with
    | Empty -> ()
    | Leaf (key, d) -> Callback.call f key d
    | Branch (_, _, t0, t1) ->
      unsigned_iter f t0;
      unsigned_iter f t1

  let iter f t =
    match descr t with
    | Empty -> ()
    | Leaf (key, d) -> Callback.call f key d
    | Branch (_, bit, t0, t1) ->
      let t0, t1 = order_branches bit t0 t1 in
      unsigned_iter f t0;
      unsigned_iter f t1

  let rec unsigned_fold f t acc =
    match descr t with
    | Empty -> acc
    | Leaf (key, d) -> Callback.call f key d acc
    | Branch (_, _, t0, t1) -> unsigned_fold f t1 (unsigned_fold f t0 acc)

  let fold f t acc =
    match descr t with
    | Empty -> acc
    | Leaf (key, d) -> Callback.call f key d acc
    | Branch (_, bit, t0, t1) ->
      let t0, t1 = order_branches bit t0 t1 in
      unsigned_fold f t1 (unsigned_fold f t0 acc)

  let rec unsigned_for_all p t =
    match descr t with
    | Empty -> true
    | Leaf (key, d) -> Callback.call p key d
    | Branch (_, _, t0, t1) -> unsigned_for_all p t0 && unsigned_for_all p t1

  let for_all p t =
    match descr t with
    | Empty -> true
    | Leaf (key, d) -> Callback.call p key d
    | Branch (_, bit, t0, t1) ->
      let t0, t1 = order_branches bit t0 t1 in
      unsigned_for_all p t0 && unsigned_for_all p t1

  let rec unsigned_exists p t =
    match descr t with
    | Empty -> false
    | Leaf (key, d) -> Callback.call p key d
    | Branch (_, _, t0, t1) -> unsigned_exists p t0 || unsigned_exists p t1

  let exists p t =
    match descr t with
    | Empty -> false
    | Leaf (key, d) -> Callback.call p key d
    | Branch (_, bit, t0, t1) ->
      let t0, t1 = order_branches bit t0 t1 in
      unsigned_exists p t0 || unsigned_exists p t1

  let filter p t =
    let rec loop t =
      let iv = is_value_of t in
      match descr t with
      | Empty -> t
      | Leaf (i, d) -> if Callback.call p i d then t else empty iv
      | Branch (prefix, bit, t0, t1) -> branch prefix bit (loop t0) (loop t1)
    in
    loop t

  (* CR-someday lmaurer: Make this O(n) rather than O(n log n). *)
  let partition p t =
    let rec loop ((true_, false_) as acc) t =
      match descr t with
      | Empty -> acc
      | Leaf (i, d) ->
        if Callback.call p i d
        then add i d true_, false_
        else true_, add i d false_
      | Branch (_, _, t0, t1) -> loop (loop acc t0) t1
    in
    let empty = empty (is_value_of t) in
    loop (empty, empty) t

  let rec choose t =
    match descr t with
    | Empty -> raise Not_found
    | Leaf (key, d) -> Binding.create key d
    | Branch (_, _, t0, _) -> choose t0

  let choose_opt t =
    match choose t with exception Not_found -> None | choice -> Some choice

  let rec unsigned_min_binding t =
    match descr t with
    | Empty -> raise Not_found
    | Leaf (key, d) -> Binding.create key d
    | Branch (_, _, t0, _) -> unsigned_min_binding t0

  let min_binding t =
    match descr t with
    | Empty -> raise Not_found
    | Leaf (key, d) -> Binding.create key d
    | Branch (_, bit, t0, t1) ->
      unsigned_min_binding (if bit < 0 then t1 else t0)

  let min_binding_opt t =
    match min_binding t with exception Not_found -> None | min -> Some min

  let rec unsigned_max_binding t =
    match descr t with
    | Empty -> raise Not_found
    | Leaf (key, d) -> Binding.create key d
    | Branch (_, _, _, t1) -> unsigned_max_binding t1

  let max_binding t =
    match descr t with
    | Empty -> raise Not_found
    | Leaf (key, d) -> Binding.create key d
    | Branch (_, bit, t0, t1) ->
      unsigned_max_binding (if bit < 0 then t0 else t1)

  let max_binding_opt t =
    match max_binding t with exception Not_found -> None | max -> Some max

  let rec equal f t0 t1 =
    if t0 == t1
    then true
    else
      match descr t0, descr t1 with
      | Empty, Empty -> assert false (* already covered *)
      | Leaf (i, d0), Leaf (j, d1) -> i = j && f d0 d1
      | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
        if equal_prefix prefix0 bit0 prefix1 bit1
        then equal f t00 t10 && equal f t01 t11
        else false
      | (Empty | Leaf _ | Branch _), _ -> false

  let rec compare f t0 t1 =
    if t0 == t1
    then 0
    else
      match descr t0, descr t1 with
      | Empty, Empty -> assert false (* already covered *)
      | Leaf (i, d0), Leaf (j, d1) ->
        let c = if i = j then 0 else if i < j then -1 else 1 in
        if c <> 0 then c else f d0 d1
      | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
        let c = compare_prefix prefix0 bit0 prefix1 bit1 in
        if c = 0
        then
          let c = compare f t00 t10 in
          if c = 0 then compare f t01 t11 else c
        else c
      | Empty, Leaf _ -> 1
      | Empty, Branch _ -> 1
      | Leaf _, Branch _ -> 1
      | Leaf _, Empty -> -1
      | Branch _, Empty -> -1
      | Branch _, Leaf _ -> -1

  (* All entries in [t] have the same sign -- either all are non-negative or all
     are negative.

     [i] might be any value. *)
  let same_sign_split ~found ~not_found i t =
    let rec loop t =
      match descr t with
      | Empty ->
        let iv = is_value_of t in
        empty iv, not_found, empty iv
      | Leaf (j, d) ->
        let iv = is_value_of t in
        if i = j
        then empty iv, found d, empty iv
        else if j < i
        then singleton iv j d, not_found, empty iv
        else empty iv, not_found, singleton iv j d
      | Branch (prefix, bit, t0, t1) ->
        if match_prefix i prefix bit
        then
          if zero_bit i bit
          then
            let lt, mem, gt = loop t0 in
            lt, mem, branch prefix bit gt t1
          else
            let lt, mem, gt = loop t1 in
            branch prefix bit t0 lt, mem, gt
        else if i < prefix
        then empty (is_value_of t), not_found, t
        else t, not_found, empty (is_value_of t)
    in
    loop t

  let split ~found ~not_found i t =
    match descr t with
    | Branch (_, bit, t0, t1) when bit < 0 ->
      (* prefix is necessarily empty *)
      if i < 0
      then
        let lt, mem, gt = same_sign_split ~found ~not_found i t1 in
        lt, mem, branch 0 bit t0 gt
      else
        let lt, mem, gt = same_sign_split ~found ~not_found i t0 in
        branch 0 bit lt t1, mem, gt
    | Empty | Leaf _ | Branch _ ->
      (same_sign_split [@inlined hint]) ~found ~not_found i t

  let to_list t =
    let rec loop acc t =
      match descr t with
      | Empty -> acc
      | Leaf (i, d) -> Binding.create i d :: acc
      | Branch (_, _, t0, t1) -> loop (loop acc t1) t0
    in
    match descr t with
    | Empty -> []
    | Leaf (i, d) -> [Binding.create i d]
    | Branch (_, bit, t0, t1) ->
      let t0, t1 = order_branches bit t0 t1 in
      loop (loop [] t1) t0

  (* CR-someday lmaurer: We could borrow Haskell's trick and generalize this
     function quite a bit, giving us a single implementation of [union],
     [inter], etc. without sacrificing sharing. It also avoids passing or
     returning options. We could even turn it into a functor over three [Tree]
     instances and get arbitrary combinations of taking and returning sets and
     maps. *)
  let rec merge' :
      type a b c.
      c Tree.is_value ->
      (key -> a option -> b option -> c option) ->
      a t ->
      b t ->
      c t =
   fun iv f t0 t1 ->
    let iv0 = is_value_of t0 in
    let iv1 = is_value_of t1 in
    match descr t0, descr t1 with
    (* Empty cases, just recurse and be sure to call f on all leaf cases
       recursively *)
    | Empty, Empty -> empty iv
    | Empty, Leaf (i, d) -> (
      match f i None (Some d) with None -> empty iv | Some d' -> leaf iv i d')
    | Leaf (i, d), Empty -> (
      match f i (Some d) None with None -> empty iv | Some d' -> leaf iv i d')
    | Empty, Branch (prefix, bit, t10, t11) ->
      branch prefix bit (merge' iv f t0 t10) (merge' iv f t0 t11)
    | Branch (prefix, bit, t00, t01), Empty ->
      branch prefix bit (merge' iv f t00 t1) (merge' iv f t01 t1)
    (* Leaf cases *)
    | Leaf (i, d0), Leaf (j, d1) when i = j -> (
      match f i (Some d0) (Some d1) with
      | None -> empty iv
      | Some datum -> leaf iv i datum)
    | Leaf (i, d0), Leaf (j, d1) -> (
      match f i (Some d0) None, f j None (Some d1) with
      | None, None -> empty iv
      | Some d0, None -> leaf iv i d0
      | None, Some d1 -> leaf iv j d1
      | Some d0, Some d1 -> join i (leaf iv i d0) j (leaf iv j d1))
    (* leaf <-> Branch cases *)
    | Leaf (i, d), Branch (prefix, bit, t10, t11) -> (
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then
          branch prefix bit (merge' iv f t0 t10) (merge' iv f (empty iv0) t11)
        else
          branch prefix bit (merge' iv f (empty iv0) t10) (merge' iv f t0 t11)
      else
        match f i (Some d) None with
        | None -> merge' iv f (empty iv0) t1
        | Some d -> join i (leaf iv i d) prefix (merge' iv f (empty iv0) t1))
    | Branch (prefix, bit, t00, t01), Leaf (i, d) -> (
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then
          branch prefix bit (merge' iv f t00 t1) (merge' iv f t01 (empty iv1))
        else
          branch prefix bit (merge' iv f t00 (empty iv1)) (merge' iv f t01 t1)
      else
        match f i None (Some d) with
        | None -> merge' iv f t0 (empty iv1)
        | Some d -> join i (leaf iv i d) prefix (merge' iv f t0 (empty iv1)))
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then branch prefix0 bit0 (merge' iv f t00 t10) (merge' iv f t01 t11)
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0
        then
          branch prefix0 bit0 (merge' iv f t00 t1) (merge' iv f t01 (empty iv1))
        else
          branch prefix0 bit0 (merge' iv f t00 (empty iv1)) (merge' iv f t01 t1)
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then
        if zero_bit prefix0 bit1
        then
          branch prefix1 bit1 (merge' iv f t0 t10) (merge' iv f (empty iv0) t11)
        else
          branch prefix1 bit1 (merge' iv f (empty iv0) t10) (merge' iv f t0 t11)
      else
        join prefix0
          (merge' iv f t0 (empty iv1))
          prefix1
          (merge' iv f (empty iv0) t1)

  let find_opt t key =
    match find t key with exception Not_found -> None | datum -> Some datum

  let get_singleton t =
    match descr t with
    | Empty | Branch _ -> None
    | Leaf (key, datum) -> Some (Binding.create key datum)

  let rec map iv f t =
    match descr t with
    | Empty -> empty iv
    | Leaf (k, datum) -> leaf iv k (f datum)
    | Branch (prefix, bit, t0, t1) ->
      branch_non_empty prefix bit (map iv f t0) (map iv f t1)

  let rec map_sharing f t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> t
    | Leaf (k, v) ->
      let v' = f v in
      if v == v' then t else leaf iv k v'
    | Branch (prefix, bit, t0, t1) ->
      let t0' = map_sharing f t0 in
      let t1' = map_sharing f t1 in
      if t0' == t0 && t1' == t1 then t else branch_non_empty prefix bit t0' t1'

  let rec mapi iv f t =
    match descr t with
    | Empty -> empty iv
    | Leaf (key, datum) -> leaf iv key (Callback.call f key datum)
    | Branch (prefix, bit, t0, t1) ->
      branch_non_empty prefix bit (mapi iv f t0) (mapi iv f t1)

  let rec filter_map iv f t =
    match descr t with
    | Empty -> empty iv
    | Leaf (k, d) -> (
      match f k d with None -> empty iv | Some d' -> leaf iv k d')
    | Branch (prefix, bit, t0, t1) ->
      branch prefix bit (filter_map iv f t0) (filter_map iv f t1)

  let rec filter_map_sharing f t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> t
    | Leaf (k, d) -> (
      match f k d with
      | None -> empty iv
      | Some d' when d == d' -> t
      | Some d' -> leaf iv k d')
    | Branch (prefix, bit, t0, t1) ->
      let t0' = filter_map_sharing f t0 in
      let t1' = filter_map_sharing f t1 in
      if t0' == t0 && t1' == t1 then t else branch prefix bit t0' t1'

  (* NB: an iterator [Next (binding, rest)] is positioned on the binding
     [binding] and then will iterate on the trees in [rest] in order.

     The trees in ['a t] are {b never} at top-level; in particular, they never
     contain branches with a negative bit and we can safely use signed
     comparison in all the functions below (except for [iterator], which is
     called on a top-level tree). *)

  type 'a iterator =
    | Done
    | Next of 'a Binding.t * 'a t list

  (* NB: We rely on [rest] not containing a top-level patricia tree to use
     signed comparison. *)
  let rec iterator0 t rest =
    match descr t with
    | Empty -> Done
    | Leaf (k, d) -> Next (Binding.create k d, rest)
    | Branch (_, _, t0, t1) -> iterator0 t0 (t1 :: rest)

  let iterator t =
    match descr t with
    | Empty -> Done
    | Leaf (k, d) -> Next (Binding.create k d, [])
    | Branch (_prefix, bit, t0, t1) ->
      if bit < 0 then iterator0 t1 [t0] else iterator0 t0 [t1]

  let current it = match it with Done -> None | Next (b, _) -> Some b

  let advance it =
    match it with
    | Done | Next (_, []) -> Done
    | Next (_, t :: rest) -> iterator0 t rest

  (* NB: We rely on [rest] not containing a top-level patricia tree to use
     signed comparison. *)
  let rec seek0 k t rest =
    match descr t, rest with
    | Leaf (i, d), _ when k <= i -> Next (Binding.create i d, rest)
    | Branch (prefix, bit, t0, t1), _ when match_prefix k prefix bit ->
      if zero_bit k bit then seek0 k t0 (t1 :: rest) else seek0 k t1 rest
    | Branch (prefix, _, t0, t1), _ when k <= prefix -> iterator0 t0 (t1 :: rest)
    | (Empty | Leaf _ | Branch _), [] -> Done
    | (Empty | Leaf _ | Branch _), t' :: rest' -> seek0 k t' rest'

  let seek it k =
    match it with
    | Done -> Done
    | Next (b, rest) -> (
      if k <= Binding.key b
      then it
      else match rest with [] -> Done | t' :: rest' -> seek0 k t' rest')

  let to_seq t =
    let rec aux acc () =
      match acc with
      | [] -> Seq.Nil
      | t0 :: r -> (
        match descr t0 with
        | Empty -> aux r ()
        | Leaf (key, value) -> Seq.Cons (Binding.create key value, aux r)
        | Branch (_, _, t1, t2) -> aux (t1 :: t2 :: r) ())
    in
    fun () ->
      match descr t with
      | Empty -> Seq.Nil
      | Leaf (key, value) -> Seq.Cons (Binding.create key value, aux [])
      | Branch (_, bit, t0, t1) ->
        let t0, t1 = order_branches bit t0 t1 in
        aux [t0; t1] ()

  let[@inline always] of_list iv l =
    List.fold_left
      (fun map b -> add (Binding.key b) (Binding.value iv b) map)
      (empty iv) l

  let merge f t0 t1 = merge' f t0 t1

  let[@inline always] disjoint_union ?eq ~print t1 t2 =
    if t1 == t2
    then t1
    else
      let fail key =
        Misc.fatal_errorf
          "Patricia_tree.disjoint_union: key %a is in intersection" print key
      in
      union
        (fun key datum1 datum2 ->
          match eq with
          | None -> fail key
          | Some eq -> if eq datum1 datum2 then Some datum1 else fail key)
        t1 t2

  let map_keys f t =
    let iv = is_value_of t in
    fold (Callback.of_func iv (fun i d acc -> add (f i) d acc)) t (empty iv)

  let valid t =
    let rec check_deep prefix bit t =
      match descr t with
      | Empty -> false (* [Empty] should only occur at top level *)
      | Leaf (i, _) -> (bit = 0 && prefix = i) || match_prefix i prefix bit
      | Branch (prefix', bit', t0, t1) ->
        (* CR-someday lmaurer: Should check that [bit'] has a POPCOUNT of 1 *)
        let prefix0 =
          (* This should be a no-op, since [prefix'] should already have a zero
             here *)
          prefix' land lnot bit'
        in
        let prefix1 = prefix' lor bit' in
        let bit0 = bit' lsr 1 in
        let bit1 = bit0 in
        prefix0 = prefix'
        && (bit = bit' || higher bit bit')
        && bit <> 0
        && match_prefix prefix' prefix bit
        && check_deep prefix0 bit0 t0 && check_deep prefix1 bit1 t1
    in
    is_empty t || check_deep 0 min_int t
end
[@@inline always]

module Set = struct
  type elt = key

  type t = unit t0

  and 'a t0 = 'a Set0.t =
    | Empty : unit t0
    | Leaf : elt -> unit t0
    | Branch : elt * elt * unit t0 * unit t0 -> unit t0

  module Ops = Tree_operations (Set0)
  include Ops

  let empty = Empty

  let singleton i = Ops.singleton Unit i ()

  let add i t = Ops.add i () t

  let union t0 t1 = Ops.union (fun _ () () -> Some ()) t0 t1

  let disjoint t0 t1 = not (Ops.inter_domain_is_non_empty t0 t1)

  let inter t0 t1 = Ops.inter Unit (fun _ () () -> ()) t0 t1

  let rec union_list ts =
    match ts with [] -> empty | t :: ts -> union t (union_list ts)

  let filter_map f t =
    let rec loop f acc = function
      | Empty -> acc
      | Leaf i -> ( match f i with None -> acc | Some j -> add j acc)
      | Branch (_, _, t0, t1) -> loop f (loop f acc t0) t1
    in
    loop f Empty t

  let elements = Ops.to_list

  let min_elt = Ops.min_binding

  let min_elt_opt = Ops.min_binding_opt

  let max_elt = Ops.max_binding

  let max_elt_opt = Ops.max_binding_opt

  let equal t0 t1 = Ops.equal (fun () () -> true) t0 t1

  let compare t0 t1 = Ops.compare (fun () () -> 0) t0 t1

  let split i t = Ops.split ~found:(fun () -> true) ~not_found:false i t

  let find elt t = if mem elt t then elt else raise Not_found

  let of_list l = Ops.of_list Unit l

  let map f t = Ops.map_keys f t
end

module Map = struct
  include Map0
  module Ops = Tree_operations (Map0)
  include Ops

  let empty = Empty

  let singleton i d = Ops.singleton Any i d

  let inter f t0 t1 = Ops.inter Any f t0 t1

  let split i t = Ops.split ~found:(fun a -> Some a) ~not_found:None i t

  let bindings s = Ops.to_list s

  let map f t = Ops.map Any f t

  let mapi f t = Ops.mapi Any f t

  let filter_map f t = Ops.filter_map Any f t

  let of_list l = Ops.of_list Any l

  let merge f t0 t1 = Ops.merge Any f t0 t1

  (* CR-someday lmaurer: This should be doable as a fast map operation if we
     generalize [Ops.map] by letting the returned tree be built by a different
     [Tree] module *)
  let keys map = fold (fun k _ set -> Set.add k set) map Set.empty

  let data t = List.map snd (bindings t)

  (* CR-someday lmaurer: See comment on [keys] *)
  let of_set f set = Set.fold (fun e map -> add e (f e) map) set empty

  let diff_domains = diff
end

type set = Set.t

type +!'a map = 'a Map.t

module Make (X : sig
  val print : Format.formatter -> key -> unit
end) =
struct
  module Set = struct
    include Set
    module Elt = X

    let [@ocamlformat "disable"] print ppf s =
      let elts ppf s = iter (fun e -> Format.fprintf ppf "@ %a" Elt.print e) s in
      Format.fprintf ppf "@[<1>{@[<1>%a@ @]}@]" elts s

    let to_string s = Format.asprintf "%a" print s
  end

  module Map = struct
    include Map
    module Key = X

    type nonrec key = key

    module Set = Set

    let [@ocamlformat "disable"] print_debug print_datum ppf t =
      let rec pp ppf t =
        match t with
        | Empty -> Format.pp_print_string ppf "()"
        | Leaf (k, v) -> Format.fprintf ppf "@[<hv 1>(%x@ %a)@]" k print_datum v
        | Branch (k1, k2, l, r) ->
          Format.fprintf ppf "@[<hv 1>(branch@ %x@ %x@ %a@ %a)@]" k1 k2 pp l
            pp r
      in
      pp ppf t

    let disjoint_union ?eq ?print t1 t2 =
      ignore print;
      Ops.disjoint_union ~print:Key.print ?eq t1 t2

    let [@ocamlformat "disable"] print print_datum ppf t =
      if is_empty t then
        Format.fprintf ppf "{}"
      else
        Format.fprintf ppf "@[<hov 1>{%a}@]"
          (Format.pp_print_list ~pp_sep:Format.pp_print_space
             (fun ppf (key, datum) ->
                Format.fprintf ppf "@[<hov 1>(%a@ %a)@]"
                  Key.print key print_datum datum))
          (bindings t)
  end
end
[@@inline always]
