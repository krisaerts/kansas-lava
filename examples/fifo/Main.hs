{-# LANGUAGE ScopedTypeVariables, RecursiveDo, KindSignatures, RankNTypes, GADTs, RecordWildCards, FlexibleInstances #-}
module Main where

import Language.KansasLava
import Language.KansasLava.Protocols
import Language.KansasLava.Utils
import Language.KansasLava.Fabric (ioFabric, observeFabric)
import Control.Monad.Fix
import Control.Monad.IO.Class
import Control.Monad
import System.IO
import Data.Monoid

import Data.Word
import Data.Sized.Ix
import Data.Sized.Unsigned
import Control.Concurrent.STM
import Control.Concurrent
import System.Environment

import Control.Concurrent.MVar
import System.IO.Unsafe
import Control.Monad.Trans.Class
import System.Random
import Control.Monad
import Control.Monad.Trans.Trace

import FED


main :: IO ()
main = do
        args <- getArgs
        main2 args

main2 :: [String] -> IO ()
main2 ["dut"] = do
        hState <- openFile "DUT_STATE" ReadWriteMode
        hIn    <- openFile "DUT_IN"    ReadWriteMode
        hOut   <- openFile "DUT_OUT"   ReadWriteMode

        let stmt :: STMT ()
            stmt = do
                    inp :: ReadReadyBox U8  <- connectReadReadyBox  "i0" "i_valid" "i_ready"
                    out :: WriteReadyBox U8 <- connectWriteReadyBox "o0" "o_valid" "o_ready"
                    VAR reg :: VAR U8 <- SIGNAL $ var 0

                    SPARK $ \ loop -> do
                            takeReadyBox inp $ \ v -> reg := v
                            putReadyBox out reg
                            GOTO loop

        let dut :: Fabric ()
            dut = compileToFabric stmt

        let dut_wrapper :: SuperFabric IO ()
            dut_wrapper = do
                hWriterFabric hState
                        [ IN (inStdLogic         "i_ready" :: SuperFabric IO (Seq Bool))
                        ]
                hReaderFabric hIn
                        [ OUT (outStdLogicVector "i0"      :: Seq U8   -> SuperFabric IO ())
                        , OUT (outStdLogic       "i_valid" :: Seq Bool -> SuperFabric IO ())
                        , OUT (outStdLogic       "o_ready" :: Seq Bool -> SuperFabric IO ())
                        ]
                hWriterFabric hOut
                        [ IN (inStdLogicVector   "o0"      :: SuperFabric IO (Seq U8))
                        , IN (inStdLogic         "o_valid" :: SuperFabric IO (Seq Bool))
                        ]

        runFabricWithDriver (ioFabric dut) dut_wrapper

        -- wait for 1000 seconds
        threadDelay $ 1000 * 1000 * 1000

        return ()

main2 ["driver"] = do
        hState <- openFile "DUT_STATE" ReadWriteMode
        hIn    <- openFile "DUT_IN"    ReadWriteMode
        hOut   <- openFile "DUT_OUT"   ReadWriteMode

        var_i_ready <- newEmptyMVar

        hReaderFabric hState
                [ OUT (flip writeIOS $ putMVar var_i_ready :: Seq Bool -> IO ())
                ]
        var_i0 <- newEmptyMVar
        var_i_valid <- newEmptyMVar
        var_o_ready <- newEmptyMVar

        hWriterFabric hIn
                [ IN (readIOS (takeMVar var_i0)      :: IO (Seq U8))
                , IN (readIOS (takeMVar var_i_valid) :: IO (Seq Bool))
                , IN (readIOS (takeMVar var_o_ready) :: IO (Seq Bool))
                ]

        var_o0 <- newEmptyMVar
        var_o_valid <- newEmptyMVar

        hReaderFabric hOut
                [ OUT (flip writeIOS $ putMVar var_o0      :: Seq U8 -> IO ())
                , OUT (flip writeIOS $ putMVar var_o_valid :: Seq Bool -> IO ())
                ]

        let hl_dut = DUT
                { i0 = sendDatum (takeMVar var_i_ready)
                                 (putMVar var_i0)
                                 (putMVar var_i_valid)
                , o0  = recvDatum (putMVar var_o_ready)
                                  (takeMVar var_o0)
                                  (takeMVar var_o_valid)
                }

        let sender =
                let loop n = do
                        send n 10
                        loop (n+1)
                 in loop 0

        let recvr = forever $ do
                 d <- recv 10
                 liftIO $ print ("recved",d)

        let prog =
                parFifoM [ sender
                         , recvr
                         ]

        events <- runFifoM (callout hl_dut) prog

        print $ prop_fifo (take 100 events)

        return ()

------------------------------------------------------------------


-- This is the low level API into the DUT, reflecting the
-- VHDL almost directly. Note the tick, which is an extra
-- field that 'ticks'  every


-- The high level API into the DUT.
-- Note you need to call these functions from top to bottom.

data DUT = DUT
        -- inputs
        { i0                    :: SendDatum U8 -> IO Bool

        -- outputs
        , o0                    :: RecvDatum   -> IO (Maybe U8)
        }



------------------------------------------------------------------
{-
data FifoE :: * where
        SendEvent :: Maybe (U8,Integer) -> FifoE    -- val x cycle-sent
        WaitEvent :: Int -> FifoE
        ResetEvent :: FifoE

instance Show FifoE where
        show (SendEvent v) = "send(" ++ show v ++ ")"
        show (WaitEvent n)  = "pause(" ++ show n ++ ")"
        show (ResetEvent)  = "reset"

data FifoM :: * -> * where
        FifoM :: (Env -> IO a)          -> FifoM a

instance Monad FifoM where
        return a = FifoM $ \ env -> return a
        (FifoM m) >>= k = FifoM $ \ env -> do
                r <- m env
                case k r of
                  FifoM m -> m env

instance MonadIO FifoM where
        liftIO m = FifoM $ \ _ -> m

data Env = Env
        { env_rand  :: forall r . (Random r) => IO r -- a random number generator
        , env_randR :: forall r . (Random r) => (r,r) -> IO r
        , in_val    :: TMVar U8
        , the_clk   :: TVar Integer
        }


send :: Int -> TraceT FifoE FifoM Bool
send n = event $ FifoM $ \ env -> do
        let dat = fromIntegral n :: U8
        -- waits until sent
        tm <- atomically $ do
                putTMVar (in_val env) dat
                readTVar (the_clk env)
        return (SendEvent (Just (dat,tm)), True)

wait :: Int -> TraceT FifoE FifoM ()
wait n = event $ FifoM $ \ env -> do { return (WaitEvent n,()) }

reset :: TraceT FifoE FifoM ()
reset = event $ FifoM $ \ env -> do { return (ResetEvent,()) }

-}


send :: U8 -> Int -> FifoM FifoCmd Bool
send d 0 = return False
send d n = do
        r <- putCmd $ \ reply -> mempty { send1 = Just (d,reply) }
        case r of
          True  -> return True
          False -> send d (n-1)

recv :: Int -> FifoM FifoCmd (Maybe U8)
recv 0 = return Nothing
recv n = do
        r <- putCmd $ \ reply -> mempty { recv1 = Just reply }
        case r of
          Nothing -> recv (n-1)
          Just r -> return (Just r)


------------------------------------------------------------------

data FifoCmd resp = FifoCmd
        { send1 :: Maybe (U8,resp Bool)
        , recv1 :: Maybe (resp (Maybe U8))
        }

instance Show (FifoCmd Ret) where
        show (FifoCmd { .. }) =
                "FifoCmd { send1 = " ++ show send1 ++
                        ", recv1 = " ++ show recv1 ++
                        "}"

instance Monoid (FifoCmd a) where
        mempty = FifoCmd
         { send1 = Nothing
         , recv1 = Nothing
         }
        mappend f1 f2 = FifoCmd
         { send1 = send1 f1 `join` send1 f2
         , recv1 = recv1 f1 `join` recv1 f2
         } where join Nothing   Nothing  = Nothing
                 join (Just a)  Nothing  = Just a
                 join Nothing   (Just b) = Just b
                 join _         _        = error "FifoCmd attempting to request Cmd twice"


-- All the logic that modifies the DUT is inside here.
-- This is called once per cycle.
callout :: DUT -> FifoCmd Reply -> IO (FifoCmd Ret)
callout  (DUT { .. }) (FifoCmd { .. }) = do
        send1' <- case send1 of
                   Nothing -> do
                           _ <- i0 SendNoDatum
                           return Nothing
                   Just (u8,Reply resp) -> do
                           r <- i0 (SendDatum u8)
                           resp r
                           return $ Just (u8,Ret r)

        recv1' <- case recv1 of
                   Nothing -> do
                           r <- o0 RecvNoDatum
                           return Nothing
                   Just (Reply resp) -> do
                           r <- o0 RecvDatum
                           resp r
                           return $ Just (Ret r)

        return $ FifoCmd
                { send1 = send1'
                , recv1 = recv1'
                }


-- This is the key concept, correctnes of the FIFO.

prop_fifo :: [FifoCmd Ret] -> Bool
prop_fifo cmds = and $ zipWith (==) xs ys
  where
          xs = [ u | FifoCmd { send1 = Just (u,Ret True) } <- cmds ]
          ys = [ u | FifoCmd { recv1 = Just (Ret (Just u)) } <- cmds ]
