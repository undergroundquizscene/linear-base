{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# OPTIONS_GHC -Wno-unused-matches #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MagicHash #-}


module Simple.TopSort where

import qualified Prelude.Linear as Linear
import Prelude.Linear ((&))
import Data.Unrestricted.Linear
import qualified Data.HashMap.Linear as HMap
import Data.HashMap.Linear (HashMap)
import Data.Bifunctor.Linear (second)
import Data.Maybe.Linear (catMaybes)
import qualified Data.Functor.Linear as Data
import Test.HUnit hiding (Node)


-- # All Tests
-------------------------------------------------------------------------------

test1 :: Test
test1 = topsort [(1,[2,3]), (2, [4]), (3,[4]), (4,[])] ~=?
  [1,2,3,4]

test2 :: Test
test2 = topsort [(5,[2,0]), (4,[0,1]), (0,[]), (2,[3]), (3,[1]), (1,[])] ~=?
  [5,2,3,4,0,1]

test3 :: Test
test3 = topsort
  [ (1,[2]), (2,[4,5]), (3,[9,7]), (4,[7,8,10]), (5,[10]), (6,[10])
  , (7,[]),(8,[]),(9,[]),(10,[])
  ] ~=?
    [1,2,4,8,5,3,9,7,6,10]

topsortTests :: IO Counts
topsortTests = runTestTT  $ TestList [test1, test2, test3]

-- # The topological sort of a DAG
-------------------------------------------------------------------------------

type Node = Int
type InDegGraph = HashMap Node ([Node], Int)

topsort :: [(Node, [Node])] -> [Node]
topsort = reverse . postOrder . fmap (  \(n,nbrs) -> (n,(nbrs,0))  )
  where
    postOrder :: [(Node, ([Node], Int))] -> [Node]
    postOrder [] = []
    postOrder (xs) = let nodes = map fst xs in
      unur Linear.$ HMap.empty (length xs * 2) Linear.$
        \hm -> postOrderHM nodes (HMap.insertAll xs hm)


postOrderHM :: [Node] -> InDegGraph #-> Ur [Node]
postOrderHM nodes dag = findSources nodes (computeInDeg nodes dag) & \case
  (dag, Ur sources) -> pluckSources sources [] dag
 where
   -- O(V + N)
  computeInDeg :: [Node] -> InDegGraph #-> InDegGraph
  computeInDeg nodes dag = Linear.foldl incChildren dag nodes

  -- Increment in-degree of all neighbors
  incChildren :: InDegGraph #-> Node -> InDegGraph
  incChildren dag node = HMap.lookup dag node & \case
     (dag, Ur Nothing) -> dag
     (dag, Ur (Just (xs,i))) -> incNodes (move xs) dag
    where
      incNodes :: Ur [Node] #-> InDegGraph #-> InDegGraph
      incNodes (Ur ns) dag = Linear.foldl incNode dag ns

      incNode :: InDegGraph #-> Node -> InDegGraph
      incNode dag node = HMap.lookup dag node & \case
        (dag', Ur Nothing) -> dag'
        (dag', Ur (Just (n,d))) ->
          HMap.insert dag' node (n,d+1)
        --HMap.alter dag (\(Just (n,d)) -> Just (n,d+1)) node


-- pluckSources sources postOrdSoFar dag
pluckSources :: [Node] -> [Node] -> InDegGraph #-> Ur [Node]
pluckSources [] postOrd dag = lseq dag (move postOrd)
pluckSources (s:ss) postOrd dag = HMap.lookup dag s & \case
  (dag, Ur Nothing) -> pluckSources ss (s:postOrd) dag
  (dag, Ur (Just (xs,i))) -> walk xs dag & \case
      (dag', Ur newSrcs) ->
        pluckSources (newSrcs ++ ss) (s:postOrd) dag'
  where
    -- decrement degree of children, save newly made sources
    walk :: [Node] -> InDegGraph #-> (InDegGraph, Ur [Node])
    walk children dag =
      second (Data.fmap catMaybes) (mapAccum decDegree children dag)

    -- Decrement the degree of a node, save it if it is now a source
    decDegree :: Node -> InDegGraph #-> (InDegGraph, Ur (Maybe Node))
    decDegree node dag = HMap.lookup dag node & \case
        (dag', Ur Nothing) -> (dag', Ur Nothing)
        (dag', Ur (Just (n,d))) ->
          checkSource node (HMap.insert dag' node (n,d-1))


-- Given a list of nodes, determines which are sources
findSources :: [Node] -> InDegGraph #-> (InDegGraph, Ur [Node])
findSources nodes dag =
  second (Data.fmap catMaybes) (mapAccum checkSource nodes dag)


-- | Check if a node is a source, and if so return it
checkSource :: Node -> InDegGraph #-> (InDegGraph, Ur (Maybe Node))
checkSource node dag = HMap.lookup dag node & \case
  (dag, Ur Nothing) -> (dag, Ur Nothing)
  (dag, Ur (Just (xs,0))) ->  (dag, Ur (Just node))
  (dag, Ur (Just (xs,n))) -> (dag, Ur Nothing)


mapAccum ::
  (a -> b #-> (b, Ur c)) -> [a] -> b #-> (b, Ur [c])
mapAccum f [] b =  (b, Ur [])
mapAccum f (x:xs) b = mapAccum f xs b & \case
  (b, Ur cs) -> second (Data.fmap (:cs)) (f x b)

