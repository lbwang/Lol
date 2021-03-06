{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

-- benchmarks at the lowest level, without harness. This may require some
-- fiddling in exports of 'Tensor' instances to compile.

module Crypto.Lol.Benchmarks.CTBenches (ctBenches) where

import Control.Applicative
import Control.Monad.Random

import Crypto.Lol.Cyclotomic.Tensor
import Crypto.Lol.Prelude
import Crypto.Lol.Types
import Crypto.Random.DRBG

import Criterion

ctBenches :: _ => _ -> _ -> IO Benchmark
ctBenches (Proxy :: Proxy '(t,m,r)) (Proxy::Proxy (gen :: *)) = do
  x1 :: t m (r, r) <- getRandom
  x2 :: t m r <- getRandom
  x3 :: t m r <- getRandom
  gen <- newGenIO
  return $ bgroup "CT" [
    bench "unzipPow"    $ nf unzipT' x1,
    bench "unzipDec"    $ nf unzipT' x1,
    bench "unzipCRT"    $ nf unzipT' x1,
    bench "zipWith (*)" $ nf (zipWithT' (*) x2) x3,
    bench "crt"         $ nf (wrap $ fromJust' "CTBenches.crt" crt') x2,
    bench "crtInv"      $ nf (wrap $ fromJust' "CTBenches.crtInv" crtinv') x2,
    bench "l"           $ nf (wrap l') x2,
    bench "lInv"        $ nf (wrap lInv') x2,
    bench "*g Pow"      $ nf (wrap mulGPow'') x2,
    bench "*g CRT"      $ nf (wrap $ fromJust' "CTBenches.gcrt" mulGCRT'') x2,
    bench "lift"        $ nf (fmapT lift) x2,
    bench "error"       $ nf (evalRand (fmapT (roundMult one) <$>
                           (CT <$> cDispatchGaussian
                             (0.1 :: Double) :: Rand (CryptoRand gen) (T M Double))) :: CryptoRand gen -> (t m Int64)) gen
    ]
