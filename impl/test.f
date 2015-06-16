/* Examples for testing */
fa = lambda x: Ref Nat. x;
x = ref 1;
y1 = fa x;

m = mvar 1;
$m;
/* I don't know why m =<< 1; will fail here */
a = ref 1;
b = ref 2;
fork{x := succ(!x), x := 10};
!x;

/* here fa will fail */
y2 = fa x;
