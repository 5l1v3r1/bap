open Ast
open Type
open Utils_common

let usage = "Usage: "^Sys.argv.(0)^" <binary> [function list]\n\
             Test program to resolve indirect jumps"

let arg = ref 0;;
let binname = ref None;;
let fnames = ref None;;
let timeout = ref 30;;
let total = ref 0;;
let succ = ref 0;;

type result =
  | Vsa of (Cfg.AST.G.t * Asmir_disasm.vsaresult option)
  | Rd of Cfg.AST.G.t

let vsa a b = Vsa(Asmir_disasm.vsa_at_full a b)
let rd a b = Rd(Asmir_disasm.recursive_descent_at a b)

let recoverf = ref vsa

let speclist =
  ("-vsa", Arg.Unit (fun () -> recoverf := vsa),
   "Use VSA based CFG recovery (default).")
  :: ("-rdescent", Arg.Unit (fun () -> recoverf := rd),
      "Use recursive descent based CFG recovery.")
  :: ("-timeout", Arg.Set_int timeout,
      "<seconds> Set the per-function timeout.")
  :: []

let anon x =
  (match !arg, !fnames with
  | 0, _ -> binname := Some x
  | _, None -> fnames := Some [x]
  | _, Some l -> fnames := Some (x::l));
  incr arg;;

let () = Arg.parse speclist anon usage;;

if !arg < 1 then
  (Arg.usage speclist usage;
   exit 1);;

Tunegc.set_gc ();;

let asmp = Asmir.open_program (BatOption.get !binname);;

let funcs = Func_boundary.get_function_ranges asmp;;

let lift_func (n,s,e) =
  let go = match !fnames with
    | Some l when List.mem n l -> true
    | Some _ -> false
    | None -> true
  in
  if go then (
    Printf.printf "Lifting %s\n" n;
    incr total;
    flush stdout;
    let cfg, vsainfo = match !recoverf asmp s with
      | Rd cfg -> cfg, None
      | Vsa (cfg, Some vsainfo) -> cfg, Some vsainfo
      | Vsa (cfg, None) -> cfg, None
    in
    let cfg = Hacks.ast_remove_indirect cfg in
    let cfg = Ast_cond_simplify.simplifycond_cfg cfg in
    Cfg_pp.AstStmtsDot.output_graph (open_out ("resolve"^n^".dot")) cfg;
    Cfg_pp.SsaStmtsDot.output_graph (open_out ("resolvessa"^n^".dot")) (Cfg_ssa.of_astcfg cfg);
    BatOption.may (fun vsainfo ->
      let ssacfg = Switch_condition.add_switch_conditions vsainfo in
      Cfg_pp.SsaStmtsDot.output_graph (open_out ("resolvessaswitch"^n^".dot")) ssacfg)
      vsainfo;
    let pp = new Pp.pp_oc (open_out ("resolve"^n^".il")) in
    pp#ast_program (Cfg_ast.to_prog cfg);
    pp#close;
    incr succ
  )
let lift_func =
  Util.timeout ~secs:!timeout ~f:lift_func
let lift_func ((n,_,_) as x) =
  try lift_func ~x
  with e ->
    Printf.printf "Lifting %s failed: %s\n" n (Printexc.to_string e)

let funcs = List.iter lift_func funcs;;

Printf.printf "%d out of %d functions recovered (%.2f%%)\n" !succ !total (((float_of_int !succ) *. 100.0) /. (float_of_int !total));;

