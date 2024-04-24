/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*          Xavier Leroy and Damien Doligez, INRIA Rocquencourt           */
/*                                                                        */
/*   Copyright 1996 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#define CAML_INTERNALS

/* 1. Allocation functions doing the same work as the macros in the
      case where [Setup_for_gc] and [Restore_after_gc] are no-ops.
   2. Convenience functions related to allocation.
*/

#include <string.h>
#include <stdarg.h>
#include "caml/alloc.h"
#include "caml/custom.h"
#include "caml/major_gc.h"
#include "caml/memory.h"
#include "caml/mlvalues.h"
#include "caml/fiber.h"
#include "caml/domain.h"

CAMLexport value caml_alloc_with_reserved (mlsize_t wosize, tag_t tag,
                                           reserved_t reserved)
{
  value result;
  mlsize_t i;

  // Optimization: for mixed blocks, don't fill in non-scannable fields
  mlsize_t scannable_wosize = Scannable_wosize_reserved(reserved, wosize);

  CAMLassert (tag < Num_tags);
  CAMLassert (tag != Infix_tag);
  if (wosize <= Max_young_wosize){
    if (wosize == 0){
      result = Atom (tag);
    }else{
      Caml_check_caml_state();
      Alloc_small_with_reserved (result, wosize, tag, Alloc_small_enter_GC,
                                 reserved);
      if (tag < No_scan_tag){
        for (i = 0; i < scannable_wosize; i++) Field (result, i) = Val_unit;
      }
    }
  } else {
    result = caml_alloc_shr_reserved (wosize, tag, reserved);
    if (tag < No_scan_tag) {
      for (i = 0; i < scannable_wosize; i++) Field (result, i) = Val_unit;
    }
    result = caml_check_urgent_gc (result);
  }
  return result;
}

CAMLexport value caml_alloc (mlsize_t wosize, tag_t tag) {
  return caml_alloc_with_reserved (wosize, tag, 0);
}

/* This is used by the native compiler for large block allocations.
   The resulting block can be filled with [caml_modify], or [caml_initialize],
   or direct writes for integer values and code pointers.
   If [tag == Closure_tag], no GC must take place until field 1
   of the block has been set to the correct "arity & start of environment"
   information (issue #11482). */

#ifdef NATIVE_CODE

value caml_alloc_shr_reserved_check_gc (mlsize_t wosize, tag_t tag,
                                        reserved_t reserved)
{
  CAMLassert (tag < Num_tags);
  CAMLassert (tag != Infix_tag);
  caml_check_urgent_gc (Val_unit);
  value result = caml_alloc_shr_reserved (wosize, tag, reserved);
  if (tag < No_scan_tag) {
    mlsize_t scannable_wosize = Scannable_wosize_val(result);
    for (mlsize_t i = 0; i < scannable_wosize; i++) {
      Field (result, i) = Val_unit;
    }
  }
  return result;
}

CAMLexport value caml_alloc_shr_check_gc (mlsize_t wosize, tag_t tag)
{
  return caml_alloc_shr_reserved_check_gc(wosize, tag, 0);
}

CAMLexport value caml_alloc_mixed_shr_check_gc (mlsize_t wosize, tag_t tag,
                                                mlsize_t scannable_prefix_len)
{
  reserved_t reserved =
    Reserved_mixed_block_scannable_wosize(scannable_prefix_len);
  return caml_alloc_shr_reserved_check_gc(wosize, tag, reserved);
}
#endif

/* Copy the values to be preserved to a different array.
   The original vals array never escapes, generating better code in
   the fast path. */
#define Enter_gc_preserve_vals(dom_st, wosize) do {         \
    CAMLparam0();                                           \
    CAMLlocalN(vals_copy, (wosize));                        \
    for (i = 0; i < (wosize); i++) vals_copy[i] = vals[i];  \
    Alloc_small_enter_GC(dom_st, wosize);                   \
    for (i = 0; i < (wosize); i++) vals[i] = vals_copy[i];  \
    CAMLdrop;                                               \
  } while (0)

/* This has to be done with a macro, rather than an inline function, since
   otherwise the wosize parameter to CAMLlocalN expands to be a VLA, which
   breaks MSVC. */
#define Do_alloc_small(wosize, tag, ...)                \
{                                                       \
  Caml_check_caml_state();                              \
  value v;                                              \
  value vals[wosize] = {__VA_ARGS__};                   \
  mlsize_t i;                                           \
  CAMLassert ((tag) < 256);                             \
                                                        \
  Alloc_small(v, wosize, tag, Enter_gc_preserve_vals);  \
  for (i = 0; i < (wosize); i++) {                      \
    Field(v, i) = vals[i];                              \
  }                                                     \
  return v;                                             \
}

CAMLexport value caml_alloc_1 (tag_t tag, value a)
{
  Do_alloc_small(1, tag, a);
}

CAMLexport value caml_alloc_2 (tag_t tag, value a, value b)
{
  Do_alloc_small(2, tag, a, b);
}

CAMLexport value caml_alloc_3 (tag_t tag, value a, value b, value c)
{
  Do_alloc_small(3, tag, a, b, c);
}

CAMLexport value caml_alloc_4 (tag_t tag, value a, value b, value c, value d)
{
  Do_alloc_small(4, tag, a, b, c, d);
}

CAMLexport value caml_alloc_5 (tag_t tag, value a, value b, value c, value d,
                               value e)
{
  Do_alloc_small(5, tag, a, b, c, d, e);
}

CAMLexport value caml_alloc_6 (tag_t tag, value a, value b, value c, value d,
                               value e, value f)
{
  Do_alloc_small(6, tag, a, b, c, d, e, f);
}

CAMLexport value caml_alloc_7 (tag_t tag, value a, value b, value c, value d,
                               value e, value f, value g)
{
  Do_alloc_small(7, tag, a, b, c, d, e, f, g);
}

CAMLexport value caml_alloc_8 (tag_t tag, value a, value b, value c, value d,
                               value e, value f, value g, value h)
{
  Do_alloc_small(8, tag, a, b, c, d, e, f, g, h);
}

CAMLexport value caml_alloc_9 (tag_t tag, value a, value b, value c, value d,
                               value e, value f, value g, value h, value i)
{
  Do_alloc_small(9, tag, a, b, c, d, e, f, g, h, i);
}

CAMLexport value caml_alloc_small_with_reserved (mlsize_t wosize, tag_t tag,
                                            reserved_t reserved)
{
  value result;

  CAMLassert (wosize > 0);
  CAMLassert (wosize <= Max_young_wosize);
  CAMLassert (tag < 256);
  CAMLassert (tag != Infix_tag);
  Alloc_small_with_reserved (result, wosize, tag, Alloc_small_enter_GC,
                             reserved);
  return result;
}

CAMLexport value caml_alloc_small (mlsize_t wosize, tag_t tag)
{
  return caml_alloc_small_with_reserved(wosize, tag, 0);
}

/* [n] is a number of words (fields) */
CAMLexport value caml_alloc_tuple(mlsize_t n)
{
  return caml_alloc(n, 0);
}

/* [len] is a number of bytes (chars) */
CAMLexport value caml_alloc_string (mlsize_t len)
{
  value result;
  mlsize_t offset_index;
  mlsize_t wosize = (len + sizeof (value)) / sizeof (value);

  if (wosize <= Max_young_wosize) {
    Caml_check_caml_state();
    Alloc_small (result, wosize, String_tag, Alloc_small_enter_GC);
  }else{
    result = caml_alloc_shr (wosize, String_tag);
    result = caml_check_urgent_gc (result);
  }
  Field (result, wosize - 1) = 0;
  offset_index = Bsize_wsize (wosize) - 1;
  Byte (result, offset_index) = offset_index - len;
  return result;
}

/* [len] is a number of bytes (chars) */
CAMLexport value caml_alloc_local_string (mlsize_t len)
{
  mlsize_t offset_index;
  mlsize_t wosize = (len + sizeof (value)) / sizeof (value);
  value result;

  result = caml_alloc_local(wosize, String_tag);
  Field (result, wosize - 1) = 0;
  offset_index = Bsize_wsize (wosize) - 1;
  Byte (result, offset_index) = offset_index - len;
  return result;
}

/* [len] is a number of bytes (chars) */
CAMLexport value caml_alloc_initialized_string (mlsize_t len, const char *p)
{
  value result = caml_alloc_string (len);
  memcpy((char *)String_val(result), p, len);
  return result;
}

/* [len] is a number of words.
   [mem] and [max] are relative (without unit).
*/
CAMLexport value caml_alloc_final (mlsize_t len, final_fun fun,
                                   mlsize_t mem, mlsize_t max)
{
  return caml_alloc_custom(caml_final_custom_operations(fun),
                           len * sizeof(value), mem, max);
}

CAMLexport value caml_copy_string(char const *s)
{
  mlsize_t len;
  value res;

  len = strlen(s);
  res = caml_alloc_initialized_string(len, s);
  return res;
}

CAMLexport value caml_alloc_array(value (*funct)(char const *),
                                  char const * const* arr)
{
  CAMLparam0 ();
  mlsize_t nbr, n;
  CAMLlocal2 (v, result);

  nbr = 0;
  while (arr[nbr] != 0) nbr++;
  result = caml_alloc (nbr, 0);
  for (n = 0; n < nbr; n++) {
    /* The two statements below must be separate because of evaluation
       order (don't take the address &Field(result, n) before
       calling funct, which may cause a GC and move result). */
    v = funct(arr[n]);
    caml_modify(&Field(result, n), v);
  }
  CAMLreturn (result);
}

/* [len] is a number of floats */
value caml_alloc_float_array(mlsize_t len)
{
#ifdef FLAT_FLOAT_ARRAY
  Caml_check_caml_state();
  mlsize_t wosize = len * Double_wosize;
  value result;
  /* For consistency with [caml_make_vect], which can't tell whether it should
     create a float array or not when the size is zero, the tag is set to
     zero when the size is zero. */
  if (wosize <= Max_young_wosize){
    if (wosize == 0)
      return Atom(0);
    else
      Alloc_small (result, wosize, Double_array_tag, Alloc_small_enter_GC);
  } else {
    result = caml_alloc_shr (wosize, Double_array_tag);
    result = caml_check_urgent_gc (result);
  }
  return result;
#else
  return caml_alloc (len, 0);
#endif
}


CAMLexport value caml_copy_string_array(char const * const * arr)
{
  return caml_alloc_array(caml_copy_string, arr);
}

CAMLexport int caml_convert_flag_list(value list, const int *flags)
{
  int res = 0;
  for (/*nothing*/; list != Val_emptylist; list = Field(list, 1))
    res |= flags[Int_val(Field(list, 0))];
  return res;
}

/* For compiling let rec over values */

/* [size] is a [value] representing number of words (fields) */
CAMLprim value caml_alloc_dummy(value size)
{
  mlsize_t wosize = Long_val(size);
  return caml_alloc (wosize, 0);
}

/* [size] is a [value] representing number of words (fields) */
CAMLprim value caml_alloc_dummy_function(value size,value arity)
{
  /* the arity argument is used by the js_of_ocaml runtime */
  return caml_alloc_dummy(size);
}

/* [size] is a [value] representing number of floats. */
CAMLprim value caml_alloc_dummy_float (value size)
{
  mlsize_t wosize = Long_val(size) * Double_wosize;
  return caml_alloc (wosize, 0);
}

/* [size] is a [value] representing the number of fields.
   [scannable_size] is a [value] representing the length of the prefix of
   fields that contains pointer values.
*/
CAMLprim value caml_alloc_dummy_mixed (value size, value scannable_size)
{
  mlsize_t wosize = Long_val(size);
#ifdef NATIVE_CODE
  mlsize_t scannable_wosize = Long_val(scannable_size);
  /* The below code runs for bytecode and native code, and critically assumes
     that a double record field can be stored in one word. That's true both for
     32-bit and 64-bit bytecode (as a double record field in a mixed record is
     always boxed), and for 64-bit native code (as the double record field is
     stored flat, taking up 1 word).
  */
  CAML_STATIC_ASSERT(Double_wosize == 1);
  reserved_t reserved =
    Reserved_mixed_block_scannable_wosize(scannable_wosize);
#else
  /* [scannable_size] can't be used meaningfully in bytecode */
  (void)scannable_size;
  CAMLassert(scannable_size == Val_int(-1));
  reserved_t reserved = Faux_mixed_block_sentinel;
#endif // NATIVE_CODE
  return caml_alloc_with_reserved (wosize, 0, reserved);
}

CAMLprim value caml_alloc_dummy_infix(value vsize, value voffset)
{
  mlsize_t wosize = Long_val(vsize), offset = Long_val(voffset);
  value v = caml_alloc(wosize, Closure_tag);
  /* The following choice of closure info causes the GC to skip
     the whole block contents.  This is correct since the dummy
     block contains no pointers into the heap.  However, the block
     cannot be marshaled or hashed, because not all closinfo fields
     and infix header fields are correctly initialized. */
  Closinfo_val(v) = Make_closinfo(0, wosize, 1);
  if (offset > 0) {
    v += Bsize_wsize(offset);
    (((header_t *) (v)) [-1]) = Make_header(offset, Infix_tag, 0);
  }
  return v;
}

CAMLprim value caml_update_dummy(value dummy, value newval)
{
  mlsize_t size, i;
  tag_t tag;

  tag = Tag_val (newval);

  if (Wosize_val(dummy) == 0) {
      /* Size-0 blocks are statically-allocated atoms. We cannot
         mutate them, but there is no need:
         - All atoms used in the runtime to represent OCaml values
           have tag 0 --- including empty flat float arrays, or other
           types that use a non-0 tag for non-atom blocks.
         - The dummy was already created with tag 0.
         So doing nothing suffices. */
      CAMLassert(Wosize_val(newval) == 0);
      CAMLassert(Tag_val(dummy) == Tag_val(newval));
  } else if (tag == Double_array_tag){
    CAMLassert (Wosize_val(newval) == Wosize_val(dummy));
    CAMLassert (Tag_val(dummy) != Infix_tag);
    Unsafe_store_tag_val(dummy, Double_array_tag);
    size = Wosize_val (newval) / Double_wosize;
    for (i = 0; i < size; i++) {
      Store_double_flat_field (dummy, i, Double_flat_field (newval, i));
    }
  } else if (tag == Infix_tag) {
    value clos = newval - Infix_offset_hd(Hd_val(newval));
    CAMLassert (Tag_val(clos) == Closure_tag);
    CAMLassert (Tag_val(dummy) == Infix_tag);
    CAMLassert (Infix_offset_val(dummy) == Infix_offset_val(newval));
    dummy = dummy - Infix_offset_val(dummy);
    size = Wosize_val(clos);
    CAMLassert (size == Wosize_val(dummy));
    /* It is safe to use [caml_modify] to copy code pointers
       from [clos] to [dummy], because the value being overwritten is
       an integer, and the new "value" is a pointer outside the minor
       heap. */
    for (i = 0; i < size; i++) {
      caml_modify (&Field(dummy, i), Field(clos, i));
    }
  } else {
    CAMLassert (tag < No_scan_tag);
    CAMLassert (Tag_val(dummy) != Infix_tag);
    CAMLassert (Reserved_val(dummy) == Reserved_val(newval));
    Unsafe_store_tag_val(dummy, tag);
    size = Wosize_val(newval);
    CAMLassert (size == Wosize_val(dummy));
    mlsize_t scannable_size = Scannable_wosize_val(newval);
    CAMLassert (scannable_size == Scannable_wosize_val(dummy));
    /* See comment above why this is safe even if [tag == Closure_tag]
       and some of the "values" being copied are actually code pointers.

       This reasoning does not apply to arbitrary flat fields, which might have
       the same shape as pointers into the minor heap, so we need to handle the
       non-scannable suffix of mixed blocks specially.
    */
    for (i = 0; i < scannable_size; i++){
      caml_modify (&Field(dummy, i), Field(newval, i));
    }
    for (i = scannable_size; i < size; i++) {
      Field(dummy, i) = Field(newval, i);
    }
  }
  return Val_unit;
}

CAMLexport value caml_alloc_some(value v)
{
  CAMLparam1(v);
  value some = caml_alloc_small(1, Tag_some);
  Field(some, 0) = v;
  CAMLreturn(some);
}

CAMLprim value caml_atomic_make_contended(value v)
{
  CAMLparam1(v);
  const mlsize_t sz = Wosize_bhsize(Cache_line_bsize);
  value res = caml_alloc_shr(sz, 0);
  caml_initialize(&Field(res, 0), v);
  for (mlsize_t i = 1; i < sz; i++) Field(res, i) = Val_unit;
  CAMLreturn(res);
}
