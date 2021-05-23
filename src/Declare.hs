module Declare where

import Data.Maybe (fromJust)
import Data.List (intersperse, intercalate)
import Prelude hiding (LT, GT, EQ)
import Data.Char

data BinaryOp = Add | Sub | Mult | Div
              | And | Or  | GT   | LT  | LE
              | GE  | EQ
              deriving (Eq)

data UnaryOp = Neg
             | Not
             deriving Eq

data Var = Var String
  deriving (Eq)

data Label = Label String
  deriving (Eq)

data SMethod = SMethod Var Exp
  deriving Eq


data Exp = SLit Int
         | SBool Bool
         | SUnary UnaryOp Exp
         | SBin BinaryOp Exp Exp
         | SIf Exp Exp Exp
         | SVar Var
         | Lam Var Exp
         | Apply Exp Exp
         | SClone Exp
         | SObject [(Label, SMethod)]
         | SCall Exp Label
         | SUpdate Exp Label SMethod
         | SLet Var Exp Exp
         | Top
         | Class [(Label, SMethod)] [Exp]
         | SNew Exp
         deriving (Eq)

data Method = Method Var SigmaTerm
  deriving Eq

data MethodClosure = Closure Env Var SigmaTerm
  deriving Eq

data SigmaTerm = SigmaVar Var
  | Object [(Label, Method)]
  | Call SigmaTerm Label
  | Update SigmaTerm Label Method
  | Let Var SigmaTerm SigmaTerm
  | Clone SigmaTerm
  | Lit Int
  | Boolean Bool
  | Binary BinaryOp SigmaTerm SigmaTerm
  | Unary UnaryOp SigmaTerm
  | If SigmaTerm SigmaTerm SigmaTerm
  deriving (Eq)

data Value = VInt Int | VBool Bool | ObjRef Int deriving Eq

instance Show Value where
  show (VInt i)           = show i
  show (VBool b)          = show b
  {-
  show (VClosure env ms)  =
    "<" ++ show env ++ ", " ++ (show $ map (\(l,m) -> show l ++ " = " ++ show m) ms)
  -}
  show (ObjRef i)       = "@" ++ show i

type Env = [(Var, Value)]

-- Pretty printer

instance Show SMethod where
  show (SMethod v  a) = case v of
    Var "_" -> show a
    _ -> "{" ++ show v  ++ "} " ++ show a

instance Show BinaryOp where
  show Add = "+"
  show Sub = "-"
  show Mult = "*"
  show Div = "/"
  show And = "&&"
  show Or = "||"
  show GT = ">"
  show LT = "<"
  show LE = "<="
  show GE = ">="
  show EQ = "=="

instance Show UnaryOp where
  show Neg = "-"
  show Not = "!"

instance Show Label where
  show (Label x) = x

instance Show Var where
  show (Var x) = x

instance Show Exp where
  show (SObject ms) = "[" ++ intercalate ", "
    (map (\(l,m) -> show l ++ "=" ++ show m) ms)
    ++ "]"
  show (SCall a l) = show' a ++ "." ++ show l
    where show' a'@SUpdate {} = "(" ++ show a' ++ ")"
          show' a' = show a'
  show (SUpdate a l m) = show' a ++ "." ++ show l ++ "<~" ++ show m
    where show' a'@SUpdate {} = "(" ++ show a' ++ ")"
          show' a' = show a'
  show (Class ms fathers) = "class {" ++ intercalate ","
    (map (\(l,m) -> show l ++ "=" ++ show m) ms)
    ++ "}" ++ case fathers of
      [Top] -> ""
      xs -> " extends " ++ intercalate ", " (map show xs)
      _ -> error "Wrong Class Definition"
  show (SClone a) =  "clone(" ++ show a ++ ")"
  show (SNew a) = "(new " ++ show a ++ ")"
  show (SLet x a b) = "var " ++ show x ++ " = " ++ show a ++ "; " ++ show b
  show (SLit i) = show i
  show (SBool b) = if b then "true" else "false"
  show (SBin op a b) = show a ++ " " ++ show op ++ " " ++ show b
  show (SUnary op a) = if op == Neg then show op ++ "(" ++ show a ++ ")" else show op ++ show a
  show (SIf a b c) = "if (" ++ show a ++ ") then " ++ show b ++ " else " ++ show c
  show (SVar v) = show v
  show (Lam v a) = "\\" ++ show v ++ " -> " ++ show a
  show (Apply a b) = show a ++ "(" ++ show b ++ ")"

instance Show Method where
  show (Method (Var s) t) = "{" ++ s ++ "} " ++ show t

instance Show MethodClosure where
  show (Closure env (Var s) t) = "<<" ++ show env ++ ", {" ++ s ++ "} " ++ show t ++ ">>"


instance Show SigmaTerm where
  show (SigmaVar v) = show v
  show (Object ms) = "[" ++ intercalate ","
    (map (\(l,m) -> show l ++ "=" ++ show m) ms)
    ++ "]"
  show (Call a l) = show' a ++ "." ++ show l
    where show' a'@Update {} = "(" ++ show a' ++ ")"
          show' a' = show a'
  show (Update a l m) = show' a ++ "." ++ show l ++ "<~" ++ show m
    where show' a'@Update {} = "(" ++ show a' ++ ")"
          show' a' = show a'
  show (Let x a b) = "var " ++ show x ++ " = " ++ show a ++ "; " ++ show b
  show (Lit i) = show i
  show (Boolean b) = if b then "true" else "false"
  show (Binary op a b) = show a ++ " " ++ show op ++ " " ++ show b
  show (Unary op a) = if op == Neg then show op ++ "(" ++ show a ++ ")" else show op ++ show a
  show (If a b c) = "if (" ++ show a ++ ") then " ++ show b ++ " else " ++ show c
  show (Clone a) = "clone(" ++ show a ++ ")"
  -- TODO: question 1/2/3