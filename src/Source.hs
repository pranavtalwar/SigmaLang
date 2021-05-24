module Source where
import Parser
import Declare
import Target
import Data.List
import Data.Maybe

type TClass = [(Var, Exp)]

substitute :: SigmaTerm -> SigmaTerm -> SigmaTerm -> SigmaTerm
substitute term s1 s2 = subhelper term
    where subhelper (Lit i)  = Lit i
          subhelper (Boolean b) = Boolean b
          subhelper (Binary op a b) = Binary op (subhelper a) (subhelper b)
          subhelper (Unary op a) = Unary op (subhelper a)
          subhelper (Clone a) = Clone (subhelper a)
          subhelper (Let v a b) = Let v (subhelper a) (subhelper b)
          subhelper (If a b c) = If (subhelper a) (subhelper b) (subhelper c)
          subhelper (Object xs) = Object [(label, Method v (subhelper a)) | (label, Method v a) <- xs]
          subhelper (Call a l) = Call (subhelper a) l
          subhelper (Update a l (Method v b)) = Update (subhelper a) l (Method v (subhelper b))
          subhelper (SigmaVar x) = if SigmaVar x == s1 then s2 else SigmaVar x

translate :: Exp -> TClass -> SigmaTerm
translate (SLit i) _ = Lit i
translate (SBool b) _ = Boolean b
translate (SUnary op a) tc = Unary op (translate a tc)
translate (SBin op a b) tc = Binary op (translate a tc) (translate b tc)
translate (SIf a b c) tc = If (translate a tc) (translate b tc) (translate c tc)
translate (SVar v) tc = SigmaVar v
translate (SClone c) tc = Clone (translate c tc)
translate (SObject xs) tc = Object [(l, Method v (translate e tc)) |(l, SMethod v e) <- xs]
translate (SCall a l) tc = Call (translate a tc) l
translate (SUpdate a l (SMethod v m)) tc = Update (translate a tc) l (Method v (translate m tc))
translate (SLet v a b) tc = case a of
    (Class xs _) -> Let v (translate genClass tc) (translate b ((v, genClass): tc))
        where genClass = classGen a tc
    _ -> Let v (translate a tc) (translate b tc)
translate (Lam v a) tc = Object [(Label "arg", Method v (Call (SigmaVar v) (Label "arg"))), (Label "val", Method v translation)]
    where translation = substitute (translate a tc) (SigmaVar v) (Call (SigmaVar v) (Label "arg"))
translate (Apply a b) tc = Let (Var "f") (Clone (translate a tc)) (Let (Var "y") (translate b tc) (Call (Update (SigmaVar (Var "f")) (Label "arg") (Method (Var "_") (SigmaVar (Var "y")))) (Label "val")))
translate (SNew a) tc = case a of
    (Class _ _) -> Call (translate (classGen a tc) tc) (Label "new")
    (SVar v) -> case lookup v tc of
        Just exp -> Call (translate exp tc) (Label "new")
        _ -> error "Could not find the class"

-- convert methods to for object instatiation
convertToInneRefMethods :: [(Label, SMethod)] -> [(Label, SMethod)]
convertToInneRefMethods xs = [(l, SMethod v (Apply (SCall (SVar (Var "z")) l) (SVar v))) | (l, SMethod v _) <- xs]

-- convert methods to self reference methods
convertToOuterRefMethods :: [(Label, SMethod)] -> [(Label, SMethod)]
convertToOuterRefMethods xs = [(l, SMethod (Var "_") (Lam v e)) | (l, SMethod v e) <- xs]

rmdups :: [(Label, SMethod)]-> [(Label, SMethod)]
rmdups = map head . group

rmdupswithExp :: [(Label, SMethod, Exp)]-> [(Label, SMethod, Exp)]
rmdupswithExp = map head . groupBy (\ (a, _, _) (b, _, _) -> a == b)

third :: (a, b, c) -> c
third (_, _, c) = c

classGen :: Exp -> TClass -> Exp
-- no inheritance as it is extedns bas "Top" class
classGen (Class xs [Top]) tc = SObject
    ((Label "new", SMethod (Var "z") (SObject (convertToInneRefMethods xs))) : convertToOuterRefMethods xs)
-- inheritance
classGen (Class xs fathers) tc = case fathers of
    [SVar x] -> case lookup x tc of
        Just e -> SObject ((Label "new", SMethod (Var "z") (SObject (childClassInnerMethods ++ parentClassInnerMethodsFiltered))) : childClassOuterMethods ++ parentClassOuterMethods)
            where
                  -- converting inner methods for child class
                  childClassInnerMethods = convertToInneRefMethods xs
                  methodLabels = map fst xs
                  SObject parentClassMethods = e
                  Just (SMethod v (SObject parentClassInnerMethods)) = lookup (Label "new") parentClassMethods
                  -- filtering parent class innerMethods to only include methods not in child class
                  parentClassInnerMethodsFiltered = filter (\(l, m) -> l `notElem` methodLabels) parentClassInnerMethods
                  -- converting child class outer methods after replacing super keyword with parentClass variable
                  childClassOuterMethods = convertToOuterRefMethods (map (\(l, SMethod v m) -> (l, SMethod v (replaceSuper m (SVar x)))) xs)
                  -- filtered out parents class methods not in child class and converted them to appropriate format
                  filteredParentClassMethods = filter (\(l, m) -> l /= Label "new" && l `notElem` methodLabels) parentClassMethods
                  parentClassOuterMethods = map (\(l, m) -> (l, SMethod (Var "_") (SCall (SVar x) l))) filteredParentClassMethods
    parents -> if not $ and [isJust $ lookup x tc | (SVar x) <- parents] then error "Could not find one of the parent classes to extend" else
        SObject ((Label "new", SMethod (Var "z") (SObject (childClassInnerMethods ++ parentClassInnerMethodsFiltered))) : childClassOuterMethods ++ parentClassOuterMethods)
        where
            childClassInnerMethods = convertToInneRefMethods xs
            methodLabels = map fst xs
            parentClasses = [fromJust $ lookup x tc | (SVar x) <- parents]
            parentClassInnerMethods = [fromJust $ lookup (Label "new") methods | (SObject methods) <- parentClasses]
            parentClassInnerMethodsFiltered = rmdups $ filter (\(l, m) -> l `notElem` methodLabels) $ concat [innerMethods | (SMethod v (SObject innerMethods)) <- parentClassInnerMethods]
            childClassOuterMethods = convertToOuterRefMethods (map (\(l, SMethod v m) -> (l, SMethod v (replaceSuper m (if isInParentClass l then whichParentClass l else SVar (Var "_"))))) xs)
            allParentClassMethodsWithLabel label = concat [map (\(l, m) -> (l, m, parentClasses !! i)) (filter (\(l, m) -> l == label) methods) | (SObject methods, i) <- zip parentClasses [0..]]
            findSuperclassWithMethod label = find (\(l,m,p) -> label == l) $ allParentClassMethodsWithLabel label
            isInParentClass label = isJust $ findSuperclassWithMethod label
            whichParentClass label = third $ fromJust $ findSuperclassWithMethod label
            allParentClassMethods = rmdupswithExp $ concat [map (\(l, m) -> (l, m, parentClasses !! i)) (filter (\(l, m) -> l /= Label "new" && l `notElem` methodLabels) methods) | (SObject methods, i) <- zip parentClasses [0..]]
            parentClassOuterMethods = map (\(l, m, e) -> (l, SMethod (Var "_") (SCall e l))) allParentClassMethods
classGen _ _ = error "Parsing or Syntactic Mistake"

-- method to replace "super variable" with a given expression
replaceSuper :: Exp -> Exp -> Exp
replaceSuper Top _ = Top
replaceSuper (SLit a) _ = SLit a
replaceSuper (SBool a) _ = SBool a
replaceSuper (SUnary op a) e = SUnary op (replaceSuper a e)
replaceSuper (SBin op a b) e = SBin op (replaceSuper a e) (replaceSuper b e)
replaceSuper (SIf a b c) e = SIf (replaceSuper a e) (replaceSuper b e) (replaceSuper c e)
replaceSuper (SVar (Var x)) e = if x == "super" then e else SVar (Var x)
replaceSuper (Lam v a) e = Lam v (replaceSuper a e)
replaceSuper (Apply a b) e = Apply (replaceSuper a e) (replaceSuper b e)
replaceSuper (SClone a) e = SClone (replaceSuper a e)
replaceSuper (SCall a l) e = SCall (replaceSuper a e) l
replaceSuper (SObject xs) e = SObject [(l, SMethod v (replaceSuper m e))  | (l, SMethod v m) <- xs]
replaceSuper (SUpdate a l (SMethod v b)) e = SUpdate (replaceSuper a e) l (SMethod v (replaceSuper b e))
replaceSuper (SLet v a b) e = SLet v (replaceSuper a e) (replaceSuper b e)
replaceSuper (Class xs f) e = Class [(l, SMethod v (replaceSuper m e)) | (l, SMethod v m) <- xs] ([replaceSuper x e | x <- f])
replaceSuper (SNew a) e = SNew (replaceSuper a e)