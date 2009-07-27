module Language.KansasLava.Seq 
        where
                
import Data.Traversable
-- import Data.Foldable 
import Control.Applicative
import Control.Monad
import Prelude hiding (zipWith,zipWith3)

infixr 5 :~

-- A clocked sequence of values, which can be undefined (Nothing),  or have a specific value.
data Seq a = Maybe a :~ Seq a
           | Constant (Maybe a)
        deriving Show

        -- Just a :~ pure a

instance Applicative Seq where
        pure a = Constant (Just a)
        (Constant h1) <*> (h2 :~ t2)    = (h1 `ap` h2) :~ (Constant h1 <*> t2)
        (h1 :~ t1) <*> (Constant h2)    = (h1 `ap` h2) :~ (t1 <*> Constant h2)
        (h1 :~ t1) <*> (h2 :~ t2)       = (h1 `ap` h2) :~ (t1 <*> t2)
        (Constant h1) <*> (Constant h2) = Constant (h1 `ap` h2)

undefinedSeq :: Seq a
undefinedSeq = Constant Nothing

instance Functor Seq where
   fmap f (a :~ as) = liftM f a :~ fmap f as
   fmap f (Constant a) = Constant $ liftM f a

zipWith' :: (a -> b -> c) -> Seq a -> Seq b -> Seq c
zipWith' f xs ys = pure f <*> xs <*> ys

fromList :: [Maybe a] -> Seq a
fromList (x : xs) = x :~ fromList xs
fromList []       = error "Seq.fromList"

toList :: Seq a -> [Maybe a]
toList (x :~ xs) = x : toList xs
toList (Constant x) = repeat x