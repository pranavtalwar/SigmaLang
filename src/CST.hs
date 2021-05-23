module CST where
import Target
import Source
import Declare
import Prelude hiding (LT, GT, EQ)

data Checked a = Good a | Error String
  deriving Show

isGood :: Checked a -> Bool 
isGood (Good _) = True 
isGood _ = False

extractGood :: Checked a -> a
extractGood (Good a) = a
extractGood _ = error "Not good"

extractError :: Checked String -> String
extractError (Error a) = a
extractError _ = error "Not an error"

instance Functor CheckedStateful 
instance Applicative CheckedStateful

data CheckedStateful t = CST (Mem -> (Checked t, Mem))

instance Monad CheckedStateful where
  return val = CST (\m -> (Good val, m))
  (CST c) >>= f = 
    CST (\m ->
      let (val, m') = c m in
        case val of
          Good v ->
            let CST f' = f v in
              f' m'
          Error msg -> (Error msg, m'))

returnError :: String -> CheckedStateful t
returnError msg = CST (\m -> (Error msg, m))

returnGood :: t -> CheckedStateful t
returnGood v = CST (\m -> (Good v, m))


checkedUnary :: UnaryOp -> Value -> CheckedStateful Value
checkedUnary Not (VBool b) = returnGood (VBool (not b))
checkedUnary Neg (VInt i)  = returnGood (VInt (-i))
checkedUnary _ _ = returnError "Type error"

checkedBinary :: BinaryOp -> Value -> Value -> CheckedStateful Value
checkedBinary Add (VInt a)  (VInt b)  = returnGood (VInt (a + b))
checkedBinary Sub (VInt a)  (VInt b)  = returnGood (VInt (a - b))
checkedBinary Mult (VInt a)  (VInt b)  = returnGood (VInt (a * b))
checkedBinary Div (VInt a)  (VInt 0)  = returnError "Division by zero"
checkedBinary Div (VInt a)  (VInt b)  = returnGood (VInt (a `div` b))
checkedBinary And (VBool a) (VBool b) = returnGood (VBool (a && b))
checkedBinary Or  (VBool a) (VBool b) = returnGood (VBool (a || b))
checkedBinary LT  (VInt a)  (VInt b)  = returnGood (VBool (a < b))
checkedBinary LE  (VInt a)  (VInt b)  = returnGood (VBool (a <= b))
checkedBinary GE  (VInt a)  (VInt b)  = returnGood (VBool (a >= b))
checkedBinary GT  (VInt a)  (VInt b)  = returnGood (VBool (a > b))
checkedBinary EQ  a  b = returnGood (VBool (a == b))
checkedBinary _  _  _ = returnError "Type error"

readMemoryChecked :: Int -> CheckedStateful Object
readMemoryChecked i = CST (\mem-> (Good (mem !! i), mem))

newMemoryChecked :: Object -> CheckedStateful Value
newMemoryChecked obj = CST (\mem -> (Good (ObjRef (length mem)), mem ++ [obj]))

updateMemoryChecked :: Int -> Label -> MethodClosure -> CheckedStateful Value
updateMemoryChecked i l closure = CST (\mem -> let (before, mid : after) = splitAt i mem in
  (Good (ObjRef i), before ++ [map (\(n, c) -> if l == n then (n, closure) else (n,c)) mid] ++ after))

evaluateCM :: SigmaTerm -> Env -> CheckedStateful Value
evaluateCM (SigmaVar v) e = case lookup v e of
  Just a -> return a
  Nothing -> returnError ("Variable " ++ show v ++ " is undefined!")
evaluateCM (Object o) e = newMemoryChecked obj where obj = map (\(l, Method v t) -> (l, Closure e v t)) o
evaluateCM (Call a l) e = do
  ref <- evaluateCM a e
  case ref of
    ObjRef i -> do
      ms <- readMemoryChecked i
      case lookup l ms of
          Just (Closure env v m) -> evaluateCM m ((v, ObjRef i) : env)
          _ -> returnError ("Method not found: The method " ++ show l ++ " was not found in:\n" ++ show ms) 
    _ -> returnError ("Type error: The expression:\n "  ++ show a ++ "\n does not evaluate to an Object!")
evaluateCM (Let x a b) e = do
  v <- evaluateCM a e
  evaluateCM b ((x, v) : e)
evaluateCM (Clone a) e = do
  ref <- evaluateCM a e
  case ref of
    ObjRef i -> do
      obj <- readMemoryChecked i
      newMemoryChecked obj
    _  -> returnError ("Type error: The expression:\n" ++ show a ++ "\n does not evaluate to an Object!")
evaluateCM (Lit a) e = return (VInt a)
evaluateCM (Boolean a) e = return (VBool a)                        
evaluateCM (Update a l (Method v m)) e = do
  ref <- evaluateCM a e
  case ref of
    ObjRef i -> updateMemoryChecked i l closure where closure = Closure e v m
    _  -> returnError ("Type error: The expression:\n "  ++ show a ++ "\n does not evaluate to an Object!")
evaluateCM (Binary op a b) e = do
  v1 <- evaluateCM a e
  v2 <- evaluateCM b e
  checkedBinary op v1 v2
evaluateCM (Unary op a) e = do
  v <- evaluateCM a e
  checkedUnary op v
evaluateCM (If a b c) e = do
  cond <- evaluateCM a e
  case cond of
    VBool cond' -> if cond' then evaluateCM b e else evaluateCM c e
    _  -> returnError ("Expected boolean but found" ++ show a)

runStatefulCM :: SigmaTerm -> CheckedStateful SigmaTerm
runStatefulCM e = do
  val <- evaluateCM e []
  case val of
    ObjRef i -> do
      obj <- readMemoryChecked i
      return (revert obj)
    VInt i -> return (Lit i)
    VBool i -> return (Boolean i)

executeCM :: SigmaTerm -> SigmaTerm
executeCM e = case runStatefulCM e of
  (CST c) -> case c [] of
      (Good v, mem) -> v
      (Error str, mem) -> error str