
(* val seperate : int list -> (int list, int list) list *)

let rec seperate (xs: int list): (int list * int list) list = match xs with
		[] -> [([], [])]
	| x::xs' -> 
			let ys = seperate xs' in
			 	(List.fold_left 
					(fun acc (y1,y2) -> ((x::y1),y2)::(y1,(x::y2))::acc)
					[]
					ys)