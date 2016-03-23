{-# LANGUAGE FlexibleContexts, GADTs, RecordWildCards, ScopedTypeVariables #-}

module Challenges.MakeReader (Challenge(..), mkReader, tryReadLWEChallenge) where

import Challenges.Beacon
import Challenges.LWE
import Challenges.Verify

import Control.Monad
import Control.Monad.Trans
import Control.Monad.Trans.Maybe

import Crypto.Lol (intLog, Proxy)
import Crypto.Lol.Types.Proto

import Data.ByteString as BS hiding (putStrLn, null, map, tail, init, writeFile, intercalate, length, head)
import Data.ByteString.Lazy (fromStrict, null)
import Data.List hiding (null)
import Data.List.Split
import Data.Map (fromList, intersection, foldMapWithKey, keys)

import Prelude hiding (null)

import System.Directory

import Text.ProtocolBuffers.Header (ReflectDescriptor, Wire)

data Challenge where
  Challenge :: (Protoable (ChallengeSecrets t m zp)) => 
   {name :: String,
    numInsts :: Int,
    numBits :: Int,
    secretIdx :: Maybe Int, -- when this is not Nothing, the LWEChallenge will have (numInsts-1) instances
    challenge :: LWEChallenge v t m zp,
    secrets :: ChallengeSecrets t m zp} -> Challenge

-- does some validation and assembles a Challenge
mkChallenge :: forall a v t m zp . (a ~ LWEChallenge v t m zp, ReflectDescriptor (ProtoType a), 
                     Wire (ProtoType a), Protoable a, Protoable (ChallengeSecrets t m zp))
  => FilePath -> String -> LWEChallenge v t m zp -> ChallengeSecrets t m zp -> Challenge
mkChallenge secretDir name challenge@(LWEChallenge beaconTime bitOffset svar instMap :: a) (ChallengeSecrets secretMap) =
  let numInsts = length $ keys instMap
      numSecrets = length $ keys secretMap
      (secretIdx,instMap') = 
        if (numInsts == numSecrets) && (secretDir == topSecretPath)
        then if (length $ keys $ intersection instMap secretMap == numSecrets) 
             then (Nothing, instMap)
             else error $ "Challenges and secret keys have different indices for " ++ name
        else if ((numInsts-1) == numSecrets) && (secretDir == revealPath)
             then let challMap' = intersection instMap secretMap
                  in if (length $ keys challMap') == numSecrets
                     then (Just $ head $ (keys instMap) \\ (keys challMap'), challMap')
                     else error $ "Challenges and secret keys have different indices for " ++ name
             else error $ "Invalid number of secret keys for " ++ name
      bp = BP beaconTime bitOffset
      challenge = LWEChallenge bp svar instMap'
      secrets = ChallengeSecrets secretMap
      numBits = intLog 2 numInsts
  in Challenge{..}

tryReadLWEChallenge :: forall a v t m zp .
  (a ~ LWEChallenge v t m zp, ReflectDescriptor (ProtoType a), 
   Wire (ProtoType a), Protoable a, Protoable (ChallengeSecrets t m zp))
  => FilePath -> FilePath -> Proxy a -> MaybeT IO Challenge
tryReadLWEChallenge secretDir path _ = do
  let challengeFile = challengePath ++ "/" ++ path
      secretFile = secretDir ++ "/" ++  path
  foundChallenge <- lift $ doesFileExist challengeFile
  foundSecret <- lift $ doesFileExist secretFile
  when (not foundChallenge) $ do
    lift $ putStrLn $ "Could not find challenge " ++ challengeFile ++ ". Skipping..."
    MaybeT $ return Nothing
  when (not foundSecret) $ do
    lift $ putStrLn $ "Could not find secret " ++ secretFile ++ ". Skipping..."
    MaybeT $ return Nothing
  chall :: LWEChallenge v t m zp <- msgGet' <$> (lift $ BS.readFile challengeFile)
  sec :: ChallengeSecrets t m zp <- msgGet' <$> (lift $ BS.readFile secretFile)

  return $ mkChallenge secretDir path chall sec



msgGet' :: (ReflectDescriptor (ProtoType a), Wire (ProtoType a), Protoable a) => ByteString -> a
msgGet' bs = 
  case msgGet $ fromStrict bs of
    (Left str) -> error $ "when getting protocol buffer. Got string " ++ str
    (Right (a,bs')) -> 
      if null bs'
      then a
      else error $ "when getting protocol buffer. There were leftover bits!"

data TensorType = RT | CT deriving (Show)

mkReader :: [String] -> IO ()
mkReader names =
  let header = 
       "{-# LANGUAGE DataKinds, ScopedTypeVariables, TemplateHaskell, TypeFamilies #-}\n\n" ++
       "--Don't modify this file: it is generated by `mkReader` in Challenges.MakeReader\n\n" ++
       "module Challenges.Reader where\n\n" ++
       "import Challenges.MakeReader\n" ++ 
       "import Challenges.ProtoReader\n" ++ 
       "import Control.Applicative\n" ++ 
       "import Control.Monad.Trans.Maybe\n" ++ 
       "import Crypto.Lol (fType,Proxy(..))\n" ++
       "import Data.Maybe\n" ++ 
       "import Utils\n\n"
      body = 
       "readChallenges secretDir (_::Proxy t) = catMaybes <$> (mapM runMaybeT [\n" ++
       (intercalate ",\n" $ map readChallenge names) ++ "])"
      readChallenge name = 
        let (m,q) = parseName name
        in "  tryReadLWEChallenge secretDir " ++ (show name) ++ " (Proxy::Proxy (LWEChallenge Double t $(fType " ++ 
             (showInt m) ++ ") (Zq " ++ (showInt q) ++ ")))"
      parseName str = 
        let [m,q] = init $ tail $ splitOn "-" str
        in (m,q)
      showInt = init . tail . show
  in do
    d1 <- doesDirectoryExist "challenges/Challenges/" -- for GHCi from Lol
    d2 <- doesDirectoryExist "Challenges/"            -- for GHC/cabal from Lol/challenges
    cd <- getCurrentDirectory
    if d1 
    then writeFile "challenges/Challenges/Reader.hs" $ header ++ body
    else if d2 
         then writeFile "Challenges/Reader.hs" $ header ++ body
         else error $ "Could not locate directory to write Reader.hs. Current directory is " ++ cd