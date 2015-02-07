{-# LANGUAGE OverloadedStrings #-}

module Emit where

import LLVM.General.Module
import LLVM.General.Context

import qualified LLVM.General.AST as AST
import qualified LLVM.General.AST.Constant as C
import qualified LLVM.General.AST.Float as F
import qualified LLVM.General.AST.FloatingPointPredicate as FP

import Data.Traversable
import Control.Monad.Trans.Except
import Control.Monad

import Codegen
import Syntax

toSig :: [String] -> [(AST.Type, AST.Name)]
toSig = map (\x -> (double, AST.Name x))

codegenTop :: Expr -> LLVM ()
codegenTop (Function name args body) = define double name fnargs bls
  where
    fnargs = toSig args
    bls = createBlocks $ execCodegen $ do
      blk <- addBlock entryBlockName
      setBlock blk
      for args $ \a -> do
        var <- alloca double
        store var (local (AST.Name a))
        assign a var
      cgen body >>= ret

codegenTop (Extern name args) = external double name fnargs
  where fnargs = toSig args

codegenTop expr = define double "main" [] blks
  where
    blks = createBlocks $ execCodegen $ do
      blk <- addBlock entryBlockName
      setBlock blk
      cgen expr >>= ret

-------------------------------------------------------------------------------
-- Operations
-------------------------------------------------------------------------------

lt :: AST.Operand -> AST.Operand -> Codegen AST.Operand
lt a b = do
  test <- fcmp FP.ULT a b
  uitofp double test

asIRbinOp :: BinOp -> AST.Operand -> AST.Operand -> Codegen AST.Operand
asIRbinOp Add = fadd
asIRbinOp Sub = fsub
asIRbinOp Mul = fmul
asIRbinOp Div = fdiv

{-binops :: Map.Map S.Name (AST.Operand -> AST.Operand -> Codegen AST.Operand)-}
{-binops = Map.fromList [-}
      {-("+", fadd)-}
    {-, ("-", fsub)-}
    {-, ("*", fmul)-}
    {-, ("/", fdiv)-}
  {-]-}

cgen :: Expr -> Codegen AST.Operand
cgen (BinOpExp op a b) = do
  ca <- cgen a
  cb <- cgen b
  asIRbinOp op ca cb
cgen (VarExp x) = getvar x >>= load
cgen (NumberExp n) = return $ constOpr $ C.Float (F.Double n)
cgen (CallExp fn args) = do
  operands <- traverse cgen args
  call (externf (AST.Name fn)) operands
cgen _ = error "cgen called with unexpected Expr"
--cgen (S.UnaryOp op a) = cgen $ S.Call ("unary" ++ op) [a]
--cgen (S.BinaryOp "=" (S.Var var) val) = do
  --a <- getvar var
  --cval <- cgen val
  --store a cval
  --return cval

-------------------------------------------------------------------------------
-- Compilation
-------------------------------------------------------------------------------

liftError :: ExceptT String IO a -> IO a
liftError = runExceptT >=> either fail return

codegen :: AST.Module -> [Expr] -> IO AST.Module
codegen modl fns = withContext $ \context ->
  liftError $ withModuleFromAST context newast $ \m -> do
    llstr <- moduleLLVMAssembly m
    putStrLn llstr
    return newast
 where
  modn    = traverse codegenTop fns
  newast  = runLLVM modl modn