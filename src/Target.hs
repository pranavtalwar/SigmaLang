{-# LANGUAGE BlockArguments #-}
module Target where

import Parser
import Declare
import Data.List
import Data.Maybe

import Prelude hiding (LT, EQ, GT)
import Control.Monad.Fail
import Data.Typeable

{-

The type Mem is a model of memory: it is used to store objects in memory.
For this language we have to have memory, just as in the interpreter
with mutable state, because objects are mutable. That is, the method
update operation can actually modify methods stored in objects.

Therefore the memory stores all the objects that are allocated in the program.
-}

type Object = [(Label, MethodClosure)]

type Mem = [Object]

{- The replace operation, updates a method for an object in memory -}

replace :: Int -> Label -> MethodClosure -> Mem -> Mem
replace i l closure mem =
    let (before, o : after) = splitAt i mem in
    before ++ [[if l == n then (n, closure) else (n,c) | (n,c) <- o]] ++ after

{- Evaluation takes the following arguments:

SigmaTerm: The expression to be evaluated
Env: The current environment
Mem: The current memory

and returns the following:

Value: The value that is computed
Mem: The updated memory (in case method update operations have been performed)

-}

unary :: UnaryOp  -> Value -> Value
unary Neg (VInt i) = VInt (negate i)
unary Not (VBool b) = VBool (not b)
unary _ _ = error "Operation not supported!"

binary :: BinaryOp -> Value -> Value -> Value
binary Add (VInt a) (VInt b) = VInt (a + b)
binary Sub (VInt a) (VInt b) = VInt (a - b)
binary Mult (VInt a) (VInt b) = VInt (a * b)
binary Div (VInt a) (VInt b) = VInt (a `div` b)
binary And (VBool a) (VBool b) = VBool (a && b)
binary Or (VBool a) (VBool b) = VBool (a || b)
binary LT (VInt a) (VInt b) = VBool (a < b)
binary LE (VInt a) (VInt b) = VBool (a <= b)
binary GE (VInt a) (VInt b) = VBool (a >= b)
binary GT (VInt a) (VInt b) = VBool (a > b)
binary EQ a b = VBool (a == b)
binary _ _ _ = error "Operation not supported"

evaluateS :: SigmaTerm -> Env -> Mem -> Maybe (Value, Mem)
evaluateS (SigmaVar v) e mem = case lookup v e of
  Just a -> Just (a, mem)
  Nothing -> error ("Variable " ++ show v ++ " is undefined!")
evaluateS (Object o) e mem =
  let mc = map (\(l, Method v t) -> (l, Closure e v t)) o
  in Just (ObjRef (length mem), mem ++ [mc])
evaluateS (Call a l) e mem = 
    case evaluateS a e mem of
      Just (ObjRef i, mem') ->
        let ms = mem' !! i
        in case lookup l ms of
              Just (Closure env v m) -> evaluateS m ((v, ObjRef i) : env) mem'
              _ -> error ("Method not found: The method " ++ show l
                          ++ " was not found in:\n" ++ show ms) 
      _ -> error ("Type error: The expression:\n "  ++
                     show a ++ "\n does not evaluate to an Object!")
evaluateS (Let x a b) e mem = case evaluateS a e mem of
  Just (v, mem') -> evaluateS b ((x, v) : e) mem'
  _ -> error "Let Operation failed"
evaluateS (Clone a) e mem = case evaluateS a e mem of
    Just (ObjRef i, mem') -> let obj = mem' !! i in Just (ObjRef (length mem'), mem' ++ [obj])
    _  -> error ("Type error: The expression: "  ++ show a ++ " does not evaluate to an object")
evaluateS (Lit a) e mem = Just (VInt a, mem)
evaluateS (Boolean a) e mem = Just (VBool a, mem)                           
evaluateS (Update a l (Method v m)) e mem =
  case evaluateS a e mem of
    Just (ObjRef i, mem') ->
      Just (ObjRef i, replace i l (Closure e v m) mem')
evaluateS (Binary op a b) e mem = case evaluateS a e mem of
  Just (v1 ,mem') -> case evaluateS b e mem' of
    Just (v2, mem'') -> Just (binary op v1 v2, mem'')
    _ -> error ("Binary Operation " ++ show op ++  " failed")
  _ -> error ("Binary Operation " ++ show op ++  " failed")
evaluateS (Unary op a) e mem = case evaluateS a e mem of
  Just (v, mem') -> Just (unary op v, mem')
  _ -> error ("Unary Operation " ++ show op ++  " failed")
evaluateS (If a b c) e mem = case evaluateS a e mem of
  Just (v, mem') -> case v of 
    (VBool test) -> if test then evaluateS b e mem' else evaluateS c e mem'
    _ ->error ("Type error: The expression:\n "  ++
        show a ++ "\n does not evaluate to a Boolean!")
  _ -> error "Error while evaluating if condition"

executeS :: SigmaTerm -> SigmaTerm
executeS e = case evaluateS e [] [] of
  Just (ObjRef i, ms) ->  revert (ms !! i)
  Just (VInt i, ms) -> Lit i
  Just (VBool i, ms) -> Boolean i
  _ -> error "Answer is not a value"

data Stateful t = ST (Mem -> (t, Mem))

instance Functor Stateful 
instance Applicative Stateful

instance Monad Stateful where
  return val = ST (\m -> (val, m))
  (ST c) >>= f = 
    ST (\m -> 
      let (val, m') = c m in
        let ST f' = f val in
          f' m'
      )

instance MonadFail Stateful

readMemory :: Int -> Stateful Object
readMemory i = ST (\mem-> (mem !! i, mem))

newMemory :: Object -> Stateful Value
newMemory obj = ST (\mem -> (ObjRef (length mem), mem ++ [obj]))

updateMemory :: Int -> Label -> MethodClosure -> Stateful Value
updateMemory i l closure = ST(\mem -> let (before, mid : after) = splitAt i mem in
  (ObjRef i, before ++ [map (\(n, c) -> if l == n then (n, closure) else (n,c)) mid] ++ after))

evaluateM :: SigmaTerm -> Env -> Stateful Value
evaluateM (SigmaVar v) e = case lookup v e of
  Just a -> return a
  Nothing -> error ("Variable " ++ show v ++ " is undefined!")
evaluateM (Object o) e = newMemory obj where obj = map (\(l, Method v t) -> (l, Closure e v t)) o
evaluateM (Call a l) e = do
  ref <- evaluateM a e
  case ref of
    ObjRef i -> do
      ms <- readMemory i
      case lookup l ms of
          Just (Closure env v m) -> evaluateM m ((v, ObjRef i) : env)
          _ -> error ("Method not found: The method " ++ show l
                          ++ " was not found in:\n" ++ show ms) 
    _ -> error ("Type error: The expression:\n "  ++
      show a ++ "\n does not evaluate to an Object!")
evaluateM (Let x a b) e = do
  v <- evaluateM a e
  evaluateM b ((x, v) : e)
evaluateM (Clone a) e = do
  ref <- evaluateM a e
  case ref of
    ObjRef i -> do
      obj <- readMemory i
      newMemory obj
    _  -> error ("Type error: The expression:\n "  ++
        show a ++ "\n does not evaluate to an Object!")
evaluateM (Lit a) e = return (VInt a)
evaluateM (Boolean a) e = return (VBool a)                        
evaluateM (Update a l (Method v m)) e = do
  ref <- evaluateM a e
  case ref of
    ObjRef i -> updateMemory i l closure where closure = Closure e v m
    _  -> error ("Type error: The expression:\n "  ++
        show a ++ "\n does not evaluate to an Object!")
evaluateM (Binary op a b) e = do
  v1 <- evaluateM a e
  v2 <- evaluateM b e
  return (binary op v1 v2)
evaluateM (Unary op a) e = do
  v <- evaluateM a e
  return (unary op v)
evaluateM (If a b c) e = do
  cond <- evaluateM a e
  case cond of
    VBool cond' -> if cond' then evaluateM b e else evaluateM c e
    _  -> error ("Type error: The expression:\n "  ++
        show a ++ "\n does not evaluate to a Boolean!")

runStateful :: SigmaTerm -> Stateful SigmaTerm
runStateful e = do
  val <- evaluateM e []
  case val of
    ObjRef i -> do
      obj <- readMemory i
      return (revert obj)
    VInt i -> return (Lit i)
    VBool i -> return (Boolean i)

execute :: SigmaTerm -> SigmaTerm
execute e = case runStateful e of
  (ST c) -> let (val, mem) = c [] in val

revert :: Object -> SigmaTerm
revert [] = Object []
revert (x:xs) = let (l, cl) = x in
  case cl of
    Closure _ y s -> let mt = Method y s in
      case revert xs of
        Object ms -> Object ((l, mt):ms)
        _ -> error "Revert function fails"

-- | Tests for Target
--
-- >>> o1 = Object [(Label "l", Method (Var "x")  (Call (SigmaVar (Var "x")) (Label "l")))]
-- >>> o2 = Object [(Label "l", Method (Var "x")  (SigmaVar (Var "x")))]
-- >>> o3 = Object [(Label "l", Method (Var "y")  (Update (SigmaVar (Var "y")) (Label "l") (Method (Var "x") (SigmaVar (Var "x")))))]
-- >>> p1 = Call o1 (Label "l")
-- >>> p2 = Call o2 (Label "l")
-- >>> p3 = Call o3 (Label "l")
-- >>> a2 = execute p2
-- >>> a3 = execute p3
-- >>> a2 == o2
-- True
-- >>> a3 == o2
-- True
-- >>> vtrue = Object [(Label "if", Method (Var "x")  (Call (SigmaVar (Var "x")) (Label "then"))), (Label "then", Method (Var "x")  (Call (SigmaVar (Var "x")) (Label "then"))), (Label "else", Method (Var "x")  (Call (SigmaVar (Var "x")) (Label "else")))]
-- >>> vfalse = Object [(Label "if", Method (Var "x")  (Call (SigmaVar (Var "x")) (Label "else"))), (Label "then", Method (Var "x")  (Call (SigmaVar (Var "x")) (Label "then"))), (Label "else", Method (Var "x")  (Call (SigmaVar (Var "x")) (Label "else")))]
-- >>> cond b c d = Call (Update (Update b (Label "then") (Method (Var "_") c)) (Label "else") (Method (Var "_") d)) (Label "if")
-- >>> if1 = cond vtrue vfalse vtrue
-- >>> (execute if1) == vfalse
-- True
-- >>> if2 = cond vfalse vfalse vtrue
-- >>> (execute if2) == vtrue
-- True

