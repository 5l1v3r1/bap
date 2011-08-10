open OUnit
open Pcre
open Ast
open TestCommon

let test_file = "C/test";;
let il_file = "C/test.il";;


(* i represents the change on the stack to the "wrong" value for function g *)
let i = 
  let a = Parser.exp_from_string "R_ESP_1:u32" in
  let e = Parser.exp_from_string "43:u32" in
  let t = Typecheck.infer_ast e in
  let m = match Parser.exp_from_string "mem_45:?u32" with
    | Var(v) -> v
    | _ -> assert false
  in
  let s = Move(m, Store(Var(m), a, e, exp_false, t), []) in
  [s];;


(** Lift C/test and convert it to bap.  Then inject "halt true" after the return
    in the main function. Print this out to the file test.il. *)
let concrete_eval_setup _ =
  let out = open_out il_file in
  let pp = new Pp.pp_oc out in
  let prog = Asmir.open_program ~loud:false test_file in
  let ranges = Asmir.get_function_ranges prog in
  let (start_addr,_) = find_fun ranges "main" in
  (* Silence floating point warnings for tests *)
  let _ = if (Asmir.get_print_warning()) then Asmir.set_print_warning(false) in
  let log s = Printf.printf "%s" s in
  let ir = Asmir.asmprogram_to_bap ~log prog in
  let outir = inject_stmt ir start_addr "ret" halt_stmt in 
  pp#ast_program outir;
  pp#close;
  (ranges, start_addr);;


(** Open the file test.il and run two concrete executions.  The first verifies
    running from main results in the desired value (42 = 0x2aL).  The second
    concrete execution changes the value on the stack to 43 (i), starts
    the execution at the "call <g>" assembly instruction in main, and verifies
	that the result is -1. *)
let concrete_eval_test (ranges, s) = 
  let prog = Parser.program_from_file il_file in
  let ctx1 = Symbeval.concretely_execute ~s ~loud:false prog in
  let eax1 = 0x2aL in
  let (start_addr,end_addr) = find_fun ranges "main" in
  let main_prog = Ast_convenience.find_prog_chunk prog start_addr end_addr in
  let s = find_call main_prog in 
  let ctx2 = Symbeval.concretely_execute ~s ~loud:false ~i prog in
  let eax2 = Arithmetic.to64(-1L,Type.Reg(32)) in
  let msg = " from check_functions" in
  check_functions msg ranges ["main"; "g"];
  check_eax ctx1 eax1;
  check_eax ctx2 eax2;;


let concrete_eval_tear_down _ = Sys.remove il_file;;


let suite = "Traces" >:::
  [
	"concrete_eval_test" >::
	  (bracket concrete_eval_setup concrete_eval_test concrete_eval_tear_down);
  ]
