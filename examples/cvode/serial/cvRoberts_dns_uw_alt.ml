(*
 * -----------------------------------------------------------------
 * $Revision: 1.2 $
 * $Date: 2007/10/25 20:03:29 $
 * -----------------------------------------------------------------
 * Programmer(s): Scott D. Cohen, Alan C. Hindmarsh and
 *                Radu Serban @ LLNL
 * -----------------------------------------------------------------
 * OCaml port: Timothy Bourke, Inria, Sep 2010.
 * -----------------------------------------------------------------
 * Example problem:
 * 
 * The following is a simple example problem, with the coding
 * needed for its solution by CVODE. The problem is from
 * chemical kinetics, and consists of the following three rate
 * equations:         
 *    dy1/dt = -.04*y1 + 1.e4*y2*y3
 *    dy2/dt = .04*y1 - 1.e4*y2*y3 - 3.e7*(y2)^2
 *    dy3/dt = 3.e7*(y2)^2
 * on the interval from t = 0.0 to t = 4.e10, with initial
 * conditions: y1 = 1.0, y2 = y3 = 0. The problem is stiff.
 * While integrating the system, we also use the rootfinding
 * feature to find the points at which y1 = 1e-4 or at which
 * y3 = 0.01. This program solves the problem with the BDF method,
 * Newton iteration with the CVDENSE dense linear solver, and a
 * user-supplied Jacobian routine.
 * It uses a user-supplied function to compute the error weights
 * required for the WRMS norm calculations.
 * Output is printed in decades from t = .4 to t = 4.e10.
 * Run statistics (optional outputs) are printed at the end.
 * -----------------------------------------------------------------
 *)

module RealArray = Sundials.RealArray
module Roots = Sundials.Roots
let unvec = Sundials.unvec

let printf = Printf.printf

let ith v i = v.{i - 1}
let set_ith v i e = v.{i - 1} <- e

(* Test the Cvode.Alternate module *)

module DM = Dls.ArrayDenseMatrix
module LintArray = Sundials.LintArray

type cvdls_mem = {
  mutable nstlj : int;

  dm : DM.t;
  savedj : DM.t;

  pivots : LintArray.t;
}

let alternate_dense jacfn =
  let nje = ref 0 in
  let cvd_msbj = 50 in
  let cvd_dgmax = 0.2 in

  let linit mem s = (nje := 0; true) in

  let lsetup mem s convfail ypred fpred tmp =
    (* NB: Cannot access session.gamma/gammap from OCaml *)
    let gamma, gammap = Cvode.Alternate.get_gamma s in
    let dgamma = abs_float ((gamma/.gammap) -. 1.0) in
    let nst = Cvode.get_num_steps s in
    let jbad = (nst = 0) || (nst > mem.nstlj + cvd_msbj)
             || ((convfail = Cvode.Alternate.FailBadJ) && (dgamma < cvd_dgmax))
             || (convfail = Cvode.Alternate.FailOther)
    in
    let jok = not jbad in
    if jok then
      (* If jok = TRUE, use saved copy of J *)
      DM.copy mem.savedj mem.dm
    else begin
      (* If jok = FALSE, call jac routine for new J value *)
      incr nje;
      mem.nstlj <- nst;
      Bigarray.Array2.fill (Sundials.RealArray2.unwrap mem.dm) 0.0;
      let tn = Cvode.get_current_time s in
      jacfn tn ypred fpred mem.dm tmp;
      DM.copy mem.dm mem.savedj
    end;
    DM.scale (-.gamma) mem.dm;
    DM.add_identity mem.dm;
    DM.getrf mem.dm mem.pivots;
    true
  in

  let lsolve mem s b weight ycur fcur =
    let nst = Cvode.get_num_steps s in
    let gamma, gammap = Cvode.Alternate.get_gamma s in
    let gamrat = if nst > 0 then gamma /. gammap else 1.0 in
    DM.getrs mem.dm mem.pivots b;
    if (*lmm = Cvode.BDF && *) gamrat <> 1.0 then
      (let s = 2.0/.(1.0 +. gamrat) in
      RealArray.map (fun v -> s *. v) b)
  in

  let lfree mem s = () in

  let solver =
    Cvode.Alternate.make_solver (fun s nv ->
        let n = RealArray.length (Sundials.unvec nv) in
        let mem = {
          nstlj  = 0;
          dm     = DM.create n n;
          savedj = DM.create n n;
          pivots = LintArray.create n;
        }
        in
        {
          Cvode.Alternate.linit = Some (linit mem);
          Cvode.Alternate.lsetup = Some (lsetup mem);
          Cvode.Alternate.lsolve = lsolve mem;
          Cvode.Alternate.lfree = Some (lfree mem);
        })
  in
  (solver, fun () -> 0, !nje)

(* Problem Constants *)

let neq    = 3        (* number of equations  *)
let y1     = 1.0      (* initial y components *)
let y2     = 0.0
let y3     = 0.0
let rtol   = 1.0e-4   (* scalar relative tolerance            *)
let atol1  = 1.0e-8   (* vector absolute tolerance components *)
let atol2  = 1.0e-14
let atol3  = 1.0e-6
let t0     = 0.0      (* initial time           *)
let t1     = 0.4      (* first output time      *)
let tmult  = 10.0     (* output time factor     *)
let nout   = 12       (* number of output times *)
let nroots = 2        (* number of root functions *)

let f t y yd =
  let y_ith i = y.{i - 1} in
  let yd_ith = set_ith yd
  in
  let (y1, y2, y3) = (y_ith 1, y_ith 2, y_ith 3)
  in
  let yd1 = -0.04 *. y1 +. 1.0e4 *. y2 *. y3;
  and yd3 = 3.0e7 *. y2 *. y2;
  in
  yd_ith 1 yd1;
  yd_ith 2 (-. yd1 -. yd3);
  yd_ith 3 yd3

let g t y gout =
  let y_ith i = y.{i - 1}
  in
  let (y1, y3) = (y_ith 1, y_ith 3)
  in
  gout.{0} <- y1 -. 0.0001;
  gout.{1} <- y3 -. 0.01

let jac tn jac_y fpred jmat tmp =
  let y_ith i = jac_y.{i - 1}
  and j_ijth (i, j) = DM.set jmat (i - 1) (j - 1)
  in
  let (y1, y2, y3) = (y_ith 1, y_ith 2, y_ith 3)
  in
  j_ijth (1, 1) (-0.04);
  j_ijth (1, 2) (1.0e4 *. y3);
  j_ijth (1, 3) (1.0e4 *. y2);
  j_ijth (2, 1) (0.04); 
  j_ijth (2, 2) (-1.0e4 *. y3 -. 6.0e7 *. y2);
  j_ijth (2, 3) (-1.0e4 *. y2);
  j_ijth (3, 2) (6.0e7 *. y2)
  
let ewt y w =
  let atol = [| atol1; atol2; atol3 |] in
  for i = 1 to 3 do
    let yy = ith y i in
    let ww = rtol *. abs_float(yy) +. atol.(i - 1) in
    if (ww <= 0.0) then raise Sundials.NonPositiveEwt;
    set_ith w i (1.0 /. ww)
  done

let print_output =
  printf "At t = %0.4e      y =%14.6e  %14.6e  %14.6e\n"

let print_root_info r1 r2 =
  printf "    rootsfound[] = %3d %3d\n"
    (Roots.int_of_root_event r1)
    (Roots.int_of_root_event r2)

let print_final_stats s nfeLS nje =
  let nst = Cvode.get_num_steps s
  and nfe = Cvode.get_num_rhs_evals s
  and nsetups = Cvode.get_num_lin_solv_setups s
  and netf = Cvode.get_num_err_test_fails s
  and nni = Cvode.get_num_nonlin_solv_iters s
  and ncfn = Cvode.get_num_nonlin_solv_conv_fails s
  and nge = Cvode.get_num_g_evals s
  in
  printf "\nFinal Statistics:\n";
  printf "nst = %-6d nfe  = %-6d nsetups = %-6d nfeLS = %-6d nje = %d\n"
    nst nfe nsetups nfeLS nje;
  printf "nni = %-6d ncfn = %-6d netf = %-6d nge = %d\n \n"
    nni ncfn netf nge

let main () =
  (* Create serial vector of length NEQ for I.C. *)
  let y = Nvector_serial.make neq 0.0
  and roots = Roots.create nroots
  in
  let ydata = unvec y in
  let r = Roots.get roots in

  (* Initialize y *)
  set_ith ydata 1 y1;
  set_ith ydata 2 y2;
  set_ith ydata 3 y3;

  printf " \n3-species kinetics problem\n\n";

  (* Call CVodeCreate to create the solver memory and specify the 
   * Backward Differentiation Formula and the use of a Newton iteration *)
  (* Call CVodeInit to initialize the integrator memory and specify the
   * user's right hand side function in y'=f(t,y), the inital time T0, and
   * the initial dependent variable vector y. *)
  (* Call CVodeRootInit to specify the root function g with 2 components *)
  (* Call CVDense to specify the CVDENSE dense linear solver *)
  (* Set the Jacobian routine to Jac (user-supplied) *)
  let altdense, get_stats = alternate_dense jac in
  let cvode_mem =
    Cvode.init Cvode.BDF (Cvode.Newton altdense)
      (Cvode.WFtolerances ewt) f ~roots:(nroots, g) ~t0:t0 y
  in
  Gc.compact ();

  (* In loop, call CVode, print results, and test for error.
  Break out of loop when NOUT preset output times have been reached.  *)

  let tout = ref t1
  and iout = ref 0
  in
  while (!iout <> nout) do

    let (t, flag) = Cvode.solve_normal cvode_mem !tout y
    in
    print_output t (ith ydata 1) (ith ydata 2) (ith ydata 3);

    match flag with
    | Sundials.RootsFound ->
        Cvode.get_root_info cvode_mem roots;
        print_root_info (r 0) (r 1)

    | Sundials.Continue ->
        iout := !iout + 1;
        tout := !tout *. tmult

    | Sundials.StopTimeReached ->
        iout := nout
  done;

  (* Print some final statistics *)
  let nfe, nje = get_stats () in
  print_final_stats cvode_mem nfe nje

let n =
  match Sys.argv with
  | [|_; n|] -> int_of_string n
  | _ -> 1
let _ = for i = 1 to n do main () done


let _ = Gc.compact ()
