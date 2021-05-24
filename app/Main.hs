module Main where

import System.Environment
import System.Directory
import Data.List
import System.IO

import Parser
import Declare
import Target
import Source
import CST

-- The following functions take user input and check their validity                                          
-- Gets a file and returns its contents if the file exists and its contents are valid
getFile :: IO String
getFile = do putStr "Enter the file name: "
             hFlush stdout
             fileName <- getLine
             fileChecker <- doesFileExist fileName
             if fileChecker then
                do
                    readFile fileName
             else
                do putStrLn "Invalid input! The file does not exist in this directory"
                   getFile

changeLine :: IO ()
changeLine = putStr "\n"

fileOption :: IO String
fileOption = do 
        putStrLn "Select one of the following"
        putStrLn "1. Read from file"
        putStrLn "2. Read from console text"
        putStr "Enter your choice: "
        hFlush stdout
        opt <- getChar
        changeLine
        if opt == '1' then
            do
                fileContents <- getFile
                return fileContents
        else if opt == '2' then
            do
                putStr "Enter the code: "
                contents <- getLine
                return contents
        else
            do
                putStrLn "Please select a valid option!"
                fileOption

evaluatorOption :: IO Char
evaluatorOption = do 
        putStrLn "Select one of the following"
        putStrLn "1. Normal Evaluator"
        putStrLn "2. Stateful Evaluator"
        putStrLn "3. Checked Stateful Evaluator"
        putStr "Enter your choice: "
        hFlush stdout
        opt <- getChar
        changeLine
        if opt /= '1' && opt /= '2' && opt /= '3' then
            do
                putStrLn "Please select a valid option!"
                evaluatorOption
        else
            do
                return opt
                
repl :: IO ()
repl = do
        hSetBuffering stdin NoBuffering
        putStrLn "Select one of the following options:"
        putStrLn "1. Parse code to SLang"
        putStrLn "2. Translate code to Sigma"
        putStrLn "3. Evaluate code"
        putStrLn "4. Quit REPL"
        putStr "Enter your choice: "
        hFlush stdout
        option <- getChar
        changeLine
        if option == '1' then
            do
                contents <- fileOption
                putStrLn "Parsing code to SLang...."
                let parsedCode = parseExpr contents
                let Right v = parsedCode
                print v
                repl
        else if option == '2' then
            do
                contents <- fileOption
                putStrLn "Translating code to Sigma...."
                let parsedCode = parseExpr contents
                let Right v = parsedCode
                let translatedCode = translate v []
                print translatedCode
                repl
        else if option == '3' then
            do
                contents <- fileOption
                let parsedCode = parseExpr contents
                let Right v = parsedCode
                let translatedCode = translate v []
                evalOpt <- evaluatorOption
                putStrLn "Evaluating code...."
                let result = if evalOpt == '1' then 
                        executeS translatedCode 
                    else if evalOpt == '2' then
                        execute translatedCode
                    else
                        executeCM translatedCode
                print result
                repl
        else if option == '4' then
            do
                putStrLn "Exiting...."
                return ()
        else
            do
                putStrLn "Please select a valid option!"
                repl

main :: IO()
main = do
        putStrLn "Welcome to the Sigma" 
        repl