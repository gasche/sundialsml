
open Sundials
open Bigarray

module M = Dls.BandMatrix
let printf = Format.printf
let fprintf = Format.fprintf

let print_mat out m =
  let {M.n; M.mu; M.ml; M.smu} = M.size m in
  fprintf out "@[<v>";
  for i = 0 to n - 1 do
    fprintf out "@[<h>";
    for j = 0 to n - 1 do
      if (i > j + ml) || (j > i + mu)
      then fprintf out "       --     "
      else fprintf out "@ % e" (M.get m i j)
    done;
    fprintf out "@]@ "
  done;
  fprintf out "@]"

let print_factored_mat out m =
  let {M.n; M.mu; M.ml; M.smu} = M.size m in
  fprintf out "@[<v>";
  for i = 0 to n - 1 do
    fprintf out "@[<h>";
    for j = 0 to n - 1 do
      if (j > i + mu) && (j <= i + smu)
      then fprintf out "@ (% e)" (M.get m i j)
      else if (i > j + ml) || (j > i + mu)
      then fprintf out "        --      "
      else fprintf out "@  % e " (M.get m i j)
    done;
    fprintf out "@]@ "
  done;
  fprintf out "@]"

let print_vec out m =
  let nr = Array1.dim m in
  fprintf out "@[<h>";
  for i = 0 to nr - 1 do
    fprintf out "@ % e" m.{i}
  done;
  fprintf out "@]"

let print_p out p =
  let nc = Array1.dim p in
  fprintf out "@[<h>";
  for i = 0 to nc - 1 do
    fprintf out "@ % d" p.{i}
  done;
  fprintf out "@]"

let n =5
and mu = 1
and ml = 1;;
let smu = min (n - 1) (mu + ml);;

let main () =
  let a = M.create {M.n; M.mu; M.ml; M.smu} in

  M.set a 0 0 ( 1.0);
  M.set a 0 1 ( 2.0);

  M.set a 1 0 ( 2.0);
  M.set a 1 1 ( 2.0);
  M.set a 1 2 ( 3.0);

  M.set a 2 1 ( 3.0);
  M.set a 2 2 ( 3.0);
  M.set a 2 3 ( 4.0);

  M.set a 3 2 ( 4.0);
  M.set a 3 3 ( 4.0);
  M.set a 3 4 ( 5.0);

  M.set a 4 3 ( 5.0);
  M.set a 4 4 ( 5.0);

  printf "initially: a=@\n%a@\n" print_mat a;

  let b = M.create {M.n; M.mu; M.ml; M.smu} in
  M.blit a b mu ml;

  M.scale 2.0 b;
  printf "scale copy x2: b=@\n%a@\n" print_mat b;

  M.add_identity b;
  printf "add identity: b=@\n%a@\n" print_mat b;

  let p = LintArray.create 5 in
  Array1.fill p 0;
  M.gbtrf a p;
  printf "getrf: a=@\n%a@\n" print_factored_mat a;
  printf "       p=@\n%a@\n@\n" print_p p;

  let s = RealArray.create n in
  s.{0} <-  5.0;
  s.{1} <- 15.0;
  s.{2} <- 31.0;
  s.{3} <- 53.0;
  s.{4} <- 45.0;
  M.gbtrs a p s;
  printf "getrs: s=@\n%a@\n" print_vec s;;

main ();;
Gc.compact ();;

