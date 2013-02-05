(* Sanity checks *)

open Cfg
module D=Debug.Make(struct let name = "Checks" and default=`Debug end)
open D

exception Sanity of string

type 'a sanityf = 'a -> string -> unit

let insane s = raise (Sanity s)

let wrapdebug f x y =
  if debug () then f x y
  else ()

module MakeConnectedCheck(C:Cfg.CFG) = struct
  module R = Reachable.Make(C)

  let connected_check g s =
    let unreachable = R.unreachable g (C.G.V.create BB_Entry) in
    match unreachable with
    | [] -> ()
    | x::[] -> insane (Printf.sprintf "Analysis %s expects a connected graph, but %s is unreachable. You should prune unreachable nodes." s (C.v2s x))
    | x::y ->
      insane (Printf.sprintf "Analysis %s expects a connected graph, but %s and %d other nodes are unreachable. You should prune unreachable nodes." s (C.v2s x) (List.length y))
  let connected_check = wrapdebug connected_check

end

let connected_astcfg = let module CC = MakeConnectedCheck(Cfg.AST) in CC.connected_check
let connected_ssacfg = let module CC = MakeConnectedCheck(Cfg.SSA) in CC.connected_check

module MakeAcyclicCheck(C:Cfg.CFG) = struct
  let acyclic_check g s =
    let find_backedges cfg =
      let module H = Hashtbl.Make(C.G.V) in
      let h = H.create (C.G.nb_vertex cfg)
      and entry = C.find_vertex cfg Cfg.BB_Entry in
      let color v = try H.find h v with Not_found -> `White
      and setcolor v c = H.replace h v c in
      let rec walk v edges=
        let walk_edge e edges =
	  let d = C.G.E.dst e in
	  if color d = `White then walk d edges
	  else if color d = `Gray then e::edges
          else edges
        in
        setcolor v `Gray;
        let edges = C.G.fold_succ_e walk_edge cfg v edges in
        setcolor v `Black;
        edges
      in
      walk entry []
    in
    match find_backedges g with
    | [] -> ()
    | x::[] -> insane (Printf.sprintf "Analysis %s expects an acyclic graph, but the backedge from %s to %s forms a cycle. You should remove backedges before running %s." s (C.v2s (C.G.E.src x)) (C.v2s (C.G.E.dst x)) s)
    | x::y ->
      insane (Printf.sprintf "Analysis %s expects an acyclic graph, but the backedge from %s to %s, and %d other backedge(s), form at least one cycle. You should remove backedges before running %s." s (C.v2s (C.G.E.src x)) (C.v2s (C.G.E.dst x)) (List.length y) s)
end

let acyclic_astcfg = let module AC = MakeAcyclicCheck(Cfg.AST) in AC.acyclic_check
let acyclic_ssacfg = let module AC = MakeAcyclicCheck(Cfg.SSA) in AC.acyclic_check
