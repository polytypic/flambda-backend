(* TEST
   modules = "stubs.c";
 {
   runtime4;
   skip;
 }{
   include runtime_events;
   runtime5;
   { bytecode; }
   { native; }
 }
*)

external start_runtime_events : unit -> unit = "start_runtime_events"
external get_event_counts : unit -> (int * int) = "get_event_counts"

let () =
    Gc.full_major ();
    start_runtime_events ();
    for a = 0 to 2 do
        ignore(Sys.opaque_identity(ref 42));
        Gc.compact ()
    done;
    let (minors, majors) = get_event_counts () in
    Printf.printf "minors: %d, majors: %d\n" minors majors;
    (* Now test we can pause/resume while we're doing things *)
    for a = 0 to 2 do
        ignore(Sys.opaque_identity(ref 42));
        Runtime_events.resume ();
        Gc.compact ();
        Runtime_events.pause ()
    done;
    let (minors, majors) = get_event_counts () in
    Printf.printf "minors: %d, majors: %d\n" minors majors
