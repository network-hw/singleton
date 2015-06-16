/* Examples for testing */
fa = lambda x: Ref Nat. x;
x = ref 1;
y = x;
x := 2;
y := 2;

/* This will not work
let x = ref 1 in
let y = x in
x := 2;
*/

/* This also will not work */
/* (lambda x:Ref Nat.(lambda y: Ref Nat. x := 2) x) (ref 1); */

/* y1 = fa x; */

m = mvar 1;
$m;
/* I don't know why m =<< 1; will fail here */

fork{x := succ(!x), x := 10};
!x;

/* here fa will fail */
/* y2 = fa x; */
