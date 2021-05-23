module SigmaTest where
import Declare
a = Unary Neg (Lit 1)

b = Binary Add (Lit 1) (Lit 2)

c = Let (Var "x") (Lit 1) (SigmaVar (Var "x"))

d = Let (Var "x") (Binary Add (Lit 1) (Lit 2)) (SigmaVar (Var "x"))


-- Objects
e = Object [(Label "l", Method (Var "this") (Lit 10))]

f = Call (Object [(Label "l", Method (Var "this") (Lit 10)), (Label "l2", Method (Var "this") (Binary Add (Lit 20) (Call (SigmaVar (Var "this")) (Label "l"))))]) (Label "l2")

g = Call (Call (Object [(Label "l", Method (Var "this") (SigmaVar (Var "this"))), (Label "l1", Method (Var "this") (Lit 10))]) (Label "l")) (Label "l1")

h = Call (Object [(Label "l", Method (Var "this") (Call (SigmaVar (Var "this")) (Label "l1"))), (Label "l1", Method (Var "this") (Lit 10))]) (Label "l")


-- Lets
i = Let (Var "o1") (Object [(Label "l", Method (Var "this") (Lit 10))]) (Binary Sub (Lit 34) (Call (SigmaVar (Var "o1")) (Label "l")))

-- Cloning
j = Let (Var "o1") e (Let (Var "o2") (Update (Clone (SigmaVar (Var "o1"))) (Label "l") (Method (Var "this") (Lit 20))) (Call (SigmaVar (Var "o2")) (Label "l")))

k = Let (Var "o1") (Object [(Label "l", Method (Var "this") (Lit 0))]) (Let (Var "o2") (Update (Clone (SigmaVar (Var "o1"))) (Label "l") (Method (Var "this") (Lit 10))) (Binary Add (Call (SigmaVar (Var "o1")) (Label "l")) (Call (SigmaVar (Var "o2")) (Label "l"))))
