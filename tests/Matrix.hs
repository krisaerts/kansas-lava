{-# LANGUAGE ScopedTypeVariables, RankNTypes, TypeFamilies, FlexibleContexts, ExistentialQuantification #-}

module Matrix where

import Language.KansasLava

import Data.Sized.Arith
import Data.Sized.Unsigned
import qualified Data.Sized.Matrix as M hiding (length)
import Data.Sized.Ix

tests :: TestSeq -> IO ()
tests test = do

        let t1 :: (Size (W w2),
                      Size (MUL w1 (W w2)),
                      Size w1,
                      Rep w2,
                      Rep w1,
                      Num w2,
                      Integral w1) => String -> Gen (M.Matrix w1 w2) -> IO ()
	    t1 str arb = testMatrix1 test str arb

        t1 "X1xU4" (arbitrary :: Gen (M.Matrix X1 U4))
        t1 "X2xU4" (arbitrary :: Gen (M.Matrix X2 U4))
        t1 "X3xU4" (arbitrary :: Gen (M.Matrix X3 U4))

        let t2 :: (Size (MUL w1 (W w2)),
                      Size w1,
                      Rep w2,
                      Rep w1,
                      Num w2,
                      Integral w1) => String -> Gen (M.Matrix w1 w2) -> IO ()
	    t2 str arb = testMatrix2 test str arb

        t2 "X1xU4" (arbitrary :: Gen (M.Matrix X1 U4))
        t2 "X2xU4" (arbitrary :: Gen (M.Matrix X2 U4))
        t2 "X3xU4" (arbitrary :: Gen (M.Matrix X3 U4))

        let t3 :: (Size (ADD (W w) X1), Rep w, Show w) => String -> Gen (Maybe w) -> IO ()
	    t3 str arb = testMatrix3 test str arb

        t3 "U3" (arbitrary :: Gen (Maybe U3))
        t3 "Bool" (arbitrary :: Gen (Maybe Bool))

        return ()


testMatrix1 :: forall w1 w2 .
               ( Integral w1, Size w1, Eq w1, Rep w1
               , Num w2, Eq w2, Show w2, Rep w2
               , Size (W w2), Size (MUL w1 (W w2)))
            => TestSeq
            -> String
            -> Gen (M.Matrix w1 w2)
            -> IO ()
testMatrix1 (TestSeq test toList') tyName ws = do
        let ms = toList' ws
            cir = sum . M.toList . unpack :: Seq (M.Matrix w1 w2) -> Seq w2
            driver = do
                outStdLogicVector "i0" (bitwise (toSeq ms) :: Seq (Unsigned (MUL w1 (W w2))))
            dut = do
                i0 <- inStdLogicVector "i0"
                let o0 = cir i0
                outStdLogicVector "o0" o0
            res = toSeq [ sum $ M.toList m | m <- ms ] :: Seq w2

        test ("matrix/1/" ++ tyName) (length ms) dut (driver >> matchExpected "o0" res) 

testMatrix2 :: forall w1 w2 .
               ( Integral w1, Size w1, Eq w1, Rep w1
               , Eq w2, Show w2, Rep w2, Num w2
               , Size (MUL w1 (W w2)))
            => TestSeq
            -> String
            -> Gen (M.Matrix w1 w2)
            -> IO ()
testMatrix2 (TestSeq test toList') tyName ws = do
        let ms = toList' ws
            cir = pack . (\ m -> M.forAll $ \ i -> m M.! i) . unpack :: Seq (M.Matrix w1 w2) -> Seq (M.Matrix w1 w2)
            driver = do
		return ()
                outStdLogicVector "i0" (bitwise (toSeq ms) :: Seq (Unsigned (MUL w1 (W w2))))
            dut = do
		return ()
                i0 <- inStdLogicVector "i0"
                let o0 = cir i0
                outStdLogicVector "o0" o0
            res = toSeq [ m | m <- ms ] :: Seq (M.Matrix w1 w2)

        test ("matrix/2/" ++ tyName) (length ms) dut (driver >> matchExpected "o0" res) 



testMatrix3 :: forall w1 .
	(Size (ADD (W w1) X1), Rep w1, Show w1)
            => TestSeq
            -> String
            -> Gen (Maybe w1)
            -> IO ()
testMatrix3 (TestSeq test toList') tyName ws = do
        let ms = toList' ws
	    cir :: Seq (Enabled w1) -> Seq (Enabled w1)
            cir = mapEnabled (\ m -> unpack m M.! 0)
		. mapEnabled (\ x -> pack (M.matrix [ x, x ]) :: Comb (M.Matrix X2 w1))
            driver = do
		return ()
                outStdLogicVector "i0" (bitwise (toSeq ms) :: Seq (Enabled w1))
            dut = do
		return ()
                i0 <- inStdLogicVector "i0"
                let o0 = cir i0
                outStdLogicVector "o0" o0
            res = toSeq [ m | m <- ms ] :: Seq (Enabled w1)

        test ("matrix/3/" ++ tyName) (length ms) dut (driver >> matchExpected "o0" res) 
