(* TEST
 include systhreads;
 flags = "-alert -unsafe_multidomain";
 readonly_files = "sigint.c";
 hassysthreads;
 libunix; (* excludes mingw32/64 and msvc32/64 *)
 {
   program = "${test_build_directory}/signal.byte";
   setup-ocamlc.byte-build-env;
   program = "sigint";
   all_modules = "sigint.c";
   ocamlc.byte;
   program = "${test_build_directory}/signal.byte";
   all_modules = "signal.ml";
   ocamlc.byte;
   check-ocamlc.byte-output;
   run;
   check-program-output;
 }{
   program = "${test_build_directory}/signal.opt";
   setup-ocamlopt.byte-build-env;
   program = "sigint";
   all_modules = "sigint.c";
   ocamlopt.byte;
   program = "${test_build_directory}/signal.opt";
   all_modules = "signal.ml";
   ocamlopt.byte;
   check-ocamlopt.byte-output;
   run;
   check-program-output;
 }
*)

let signaled = ref false

let counter = ref 0

let sighandler _ =
  signaled := true

let print_message delay c =
  while (not !signaled) && (!counter <= 20) do
    incr counter;
    print_char c; flush stdout; Thread.delay delay
  done

let _ =
  ignore (Sys.signal Sys.sigint (Sys.Signal_handle sighandler));
  let th1 = Thread.create (print_message 0.06666666666) 'a' in
  print_message 0.1 'b';
  Thread.join th1;
  if !signaled then begin
    print_string "Got ctrl-C, exiting"; print_newline();
    exit 0
  end else begin
    print_string "not signaled???"; print_newline();
    exit 2
  end
