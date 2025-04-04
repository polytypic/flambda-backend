/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*            Xavier Leroy, projet Cristal, INRIA Rocquencourt            */
/*                                                                        */
/*   Copyright 2001 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#define CAML_INTERNALS

/* Registration of global memory roots */

#include "caml/mlvalues.h"
#include "caml/memory.h"
#include "caml/platform.h"
#include "caml/roots.h"
#include "caml/globroots.h"
#include "caml/skiplist.h"
#include "caml/stack.h"
#include "caml/callback.h"
#include "caml/fail.h"

/* This mutex must be locked with [caml_plat_lock_blocking] from the
   mutator, because caml_{register,remove}_{generational_}roots can be
   called in places where the domain lock is not safe to be
   released. */
static caml_plat_mutex roots_mutex = CAML_PLAT_MUTEX_INITIALIZER;

/* Greater than zero when the current thread is scanning the roots */
static CAMLthread_local int iterating_roots = 0;

enum { ROOT_PRESENT = 0, ROOT_DELETED = 1 };

/* The three global root lists.
   Each is represented by a skip list with the key being the address
   of the root.
   The associated data is usually ROOT_PRESENT, but is changed to
   ROOT_DELETED if a root is deleted while iteration in progress.
   Such entries are removed during the current or next iteration */

struct skiplist caml_global_roots = SKIPLIST_STATIC_INITIALIZER;
                  /* mutable roots, don't know whether old or young */
struct skiplist caml_global_roots_young = SKIPLIST_STATIC_INITIALIZER;
                  /* generational roots pointing to minor or major heap */
struct skiplist caml_global_roots_old = SKIPLIST_STATIC_INITIALIZER;
                  /* generational roots pointing to major heap */

/* The invariant of the generational roots is the following:
   - If the global root contains a pointer to the minor heap, then the root is
     in [caml_global_roots_young];
   - If the global root contains a pointer to the major heap, then the root is
     in [caml_global_roots_old] or in [caml_global_roots_young];
   - Otherwise (the root contains a pointer outside of the heap or an integer),
     then neither [caml_global_roots_young] nor [caml_global_roots_old] contain
     it. */

/* Insertion and deletion */

Caml_inline void caml_insert_global_root(struct skiplist * list, value * r)
{
  caml_plat_lock_blocking(&roots_mutex);
  caml_skiplist_insert(list, (uintnat) r, ROOT_PRESENT);
  caml_plat_unlock(&roots_mutex);
}

Caml_inline void caml_delete_global_root(struct skiplist * list, value * r)
{
  if (iterating_roots > 0) {
    /* We hold the roots_mutex because we are iterating */
    uintnat* p = caml_skiplist_find_ptr(list, (uintnat) r);
    if (p != NULL) {
      *p = ROOT_DELETED;
    }
  } else {
    caml_plat_lock_blocking(&roots_mutex);
    caml_skiplist_remove(list, (uintnat) r);
    caml_plat_unlock(&roots_mutex);
  }
}

/* Register a global C root of the mutable kind */

CAMLexport void caml_register_global_root(value *r)
{
  CAMLassert (((intnat) r & 3) == 0);  /* compact.c demands this (for now) */
  caml_insert_global_root(&caml_global_roots, r);
}

/* Un-register a global C root of the mutable kind */

CAMLexport void caml_remove_global_root(value *r)
{
  caml_delete_global_root(&caml_global_roots, r);
}

enum gc_root_class {
  YOUNG,
  OLD,
  UNTRACKED
};

static enum gc_root_class classify_gc_root(value v)
{
  if(!Is_block(v)) return UNTRACKED;
  if(Is_young(v)) return YOUNG;
  return OLD;
}

/* Register a global C root of the generational kind */

CAMLexport void caml_register_generational_global_root(value *r)
{
  Caml_check_caml_state();
  CAMLassert (((intnat) r & 3) == 0);  /* compact.c demands this (for now) */

  switch(classify_gc_root(*r)) {
    case YOUNG:
      caml_insert_global_root(&caml_global_roots_young, r);
      break;
    case OLD:
      caml_insert_global_root(&caml_global_roots_old, r);
      break;
    case UNTRACKED: break;
  }
}

/* Un-register a global C root of the generational kind */

CAMLexport void caml_remove_generational_global_root(value *r)
{
  switch(classify_gc_root(*r)) {
    case OLD:
      caml_delete_global_root(&caml_global_roots_old, r);
      /* Fallthrough: the root can be in the young list while actually
         being in the major heap. */
    case YOUNG:
      caml_delete_global_root(&caml_global_roots_young, r);
      break;
    case UNTRACKED: break;
  }
}

/* Modify the value of a global C root of the generational kind */

CAMLexport void caml_modify_generational_global_root(value *r, value newval)
{
  enum gc_root_class c;
  /* See PRs #4704, #607 and #8656 */
  switch(classify_gc_root(newval)) {
    case YOUNG:
      c = classify_gc_root(*r);
      if(c == OLD)
        caml_delete_global_root(&caml_global_roots_old, r);
      if(c != YOUNG)
        caml_insert_global_root(&caml_global_roots_young, r);
      break;

    case OLD:
      /* If the old class is YOUNG, then we do not need to do
         anything: It is OK to have a root in roots_young that
         suddenly points to the old generation -- the next minor GC
         will take care of that. */
      if(classify_gc_root(*r) == UNTRACKED)
        caml_insert_global_root(&caml_global_roots_old, r);
      break;

    case UNTRACKED:
      caml_remove_generational_global_root(r);
      break;
  }

  *r = newval;
}

#ifdef NATIVE_CODE

/* Linked-list of natdynlink'd globals */

typedef struct link {
  void *data;
  struct link *next;
} link;

static link *cons(void *data, link *tl) {
  link *lnk = caml_stat_alloc(sizeof(link));
  lnk->data = data;
  lnk->next = tl;
  return lnk;
}

#define iter_list(list,lnk) \
  for (lnk = list; lnk != NULL; lnk = lnk->next)


/* protected by roots_mutex */
static link * caml_dyn_globals = NULL;

static void caml_register_dyn_global(void *v) {
  link *link = caml_dyn_globals;
  while (link) {
    if (link->data == v) {
      const value *exn = caml_named_value("Register_dyn_global_duplicate");
      if (exn == NULL) {
        fprintf(stderr,
          "[ocaml] attempt to add duplicate in caml_dyn_globals: %p\n", v);
        abort();
      }
      caml_plat_unlock(&roots_mutex);
      caml_raise(*exn);
    }
    link = link->next;
  }
  caml_dyn_globals = cons((void*) v,caml_dyn_globals);
}

void caml_register_dyn_globals(void **globals, int nglobals) {
  int i;
  caml_plat_lock_blocking(&roots_mutex);
  for (i = 0; i < nglobals; i++)
    caml_register_dyn_global(globals[i]);
  caml_plat_unlock(&roots_mutex);
}

/* Logic to determine at which index within a global root to start and stop
   scanning.  [*glob_block], [*start], and [*stop] may be updated by this
   function. */
static void compute_index_for_global_root_scan(value* glob_block, int* start,
                                               int* stop)
{
  *start = 0;

  CAMLassert (Is_block(*glob_block));

  if (Tag_val(*glob_block) < No_scan_tag) {
    /* Note: if a [Closure_tag] block is registered as a global root
       (possibly containing one or more [Infix_tag] blocks), then only one
       out of the combined set of the [Closure_tag] and [Infix_tag] blocks
       may be registered as a global root.  Multiple registrations can cause
       the compactor to traverse the same fields of a block twice, which can
       cause a failure. */
    // CR mshinwell: This comment may not apply to runtime5, where the
    // compactor has different behaviour.  (However we still need to cope
    // with closures being registered as global roots, which flambda2 does
    // but none of the upstream middle ends.)
    if (Tag_val(*glob_block) == Infix_tag)
      *glob_block -= Infix_offset_val(*glob_block);

    if (Tag_val(*glob_block) == Closure_tag) {
      *start = Start_env_closinfo(Closinfo_val(*glob_block));
      *stop = Wosize_val(*glob_block);
    }
    else {
      *stop = Scannable_wosize_val(*glob_block);
    }
  }
  else {
    /* Set the index such that none of the block's fields will be scanned. */
    *stop = 0;
  }
}

static void scan_native_globals(scanning_action f, void* fdata)
{
  int i, j;
  link* dyn_globals;
  value* glob;
  value glob_block;
  int start, stop;
  link* lnk;

  caml_plat_lock_blocking(&roots_mutex);
  dyn_globals = caml_dyn_globals;
  caml_plat_unlock(&roots_mutex);

  /* The global roots */
  for (i = 0; caml_globals[i] != 0; i++) {
    for(glob = caml_globals[i]; *glob != 0; glob++) {
      glob_block = *glob;
      compute_index_for_global_root_scan(&glob_block, &start, &stop);
      for (j = start; j < stop; j++) {
        f(fdata, Field(glob_block, j), &Field(glob_block, j));
      }
    }
  }

  /* Dynamic (natdynlink) global roots */
  iter_list(dyn_globals, lnk) {
    for(glob = (value *) lnk->data; *glob != 0; glob++) {
      glob_block = *glob;
      compute_index_for_global_root_scan(&glob_block, &start, &stop);
      for (j = start; j < stop; j++) {
        f(fdata, Field(glob_block, j), &Field(glob_block, j));
      }
    }
  }
}

#endif

/* Iterate a GC scanning action over a global root list */
Caml_inline void caml_iterate_global_roots(scanning_action f,
                                      struct skiplist * rootlist, void* fdata)
{
  CAMLassert(iterating_roots > 0);
  FOREACH_SKIPLIST_ELEMENT(e, rootlist, {
      if (e->data == ROOT_DELETED) {
        caml_skiplist_remove(rootlist, e->key);
      } else {
        value * r = (value *) (e->key);
        f(fdata, *r, r);
      }
    })
}

/* Scan all global roots */
void caml_scan_global_roots(scanning_action f, void* fdata) {
  caml_plat_lock_blocking(&roots_mutex);
  iterating_roots ++;
  caml_iterate_global_roots(f, &caml_global_roots, fdata);
  caml_iterate_global_roots(f, &caml_global_roots_young, fdata);
  caml_iterate_global_roots(f, &caml_global_roots_old, fdata);
  iterating_roots --;
  caml_plat_unlock(&roots_mutex);

  #ifdef NATIVE_CODE
  scan_native_globals(f, fdata);
  #endif
}

/* Scan global roots for a minor collection */
void caml_scan_global_young_roots(scanning_action f, void* fdata)
{
  caml_plat_lock_blocking(&roots_mutex);
  iterating_roots ++;

  caml_iterate_global_roots(f, &caml_global_roots, fdata);
  caml_iterate_global_roots(f, &caml_global_roots_young, fdata);

  /* Move young roots to old roots */
  FOREACH_SKIPLIST_ELEMENT(e, &caml_global_roots_young, {
      value * r = (value *) (e->key);
      caml_skiplist_insert(&caml_global_roots_old, (uintnat) r, 0);
    });
  caml_skiplist_empty(&caml_global_roots_young);

  iterating_roots --;
  caml_plat_unlock(&roots_mutex);
}
