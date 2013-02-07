{- |

Selection operators for genetic algorithms.

-}

module Moo.GeneticAlgorithm.Selection
  (
  -- * Selection
    rouletteSelect
  , tournamentSelect
  , sortByFitness
  , sortByCost
  , withScale
  , withFitnessScale
  , minimizing, minimizing'
  , sigmaScale
  , rankScale
  ) where

import Moo.GeneticAlgorithm.Types
import Moo.GeneticAlgorithm.Random
import Moo.GeneticAlgorithm.Statistics (variance, average)

import Control.Monad (liftM, replicateM)
import Control.Arrow (second)
import Data.List (sortBy)
import Data.Function (on)

-- | Apply given scaling or other transform to population before selection.
withScale :: (Population a -> Population a) -> SelectionOp a -> SelectionOp a
withScale scale select = \pop -> select (scale pop)

-- | Transform fitness values before seletion.
withFitnessScale :: (Fitness -> Fitness) -> SelectionOp a -> SelectionOp a
withFitnessScale f select =
    let scale = map (second f)
    in  withScale scale select

-- | Sigma scaling. Fitness values of all genomes are scaled with
-- respect to standard devation of population fitness.
sigmaScale :: Population a -> Population a
sigmaScale pop = map (\(g,f) -> (g,1+(f-f_avg)/(2*σ))) pop
    where
      fs = map snd pop
      σ   = sqrt . variance $ fs
      f_avg = average fs

-- | Replace fitness values in the population with their ranks.  For a
-- population of size @n@, the best genome has rank @n' <= n@, and the
-- worst genome has rank @1@. 'rankScale' may be useful to avoid
-- domination of few super-genomes in 'rouletteSelect' or to apply
-- 'rouletteSelect' when fitness is not necessarily positive.
rankScale :: Population a -> Population a
rankScale pop =
    let sorted = reverse $ sortByFitness pop
        worstF = snd . head $ sorted
    in  ranks 1 worstF sorted
    where
      ranks _ _ [] = []
      ranks rank worst ((genome,fitness):rest)
          | worst == fitness    = (genome,rank)   : ranks rank worst rest
          | otherwise           = (genome,rank+1) : ranks (rank+1) fitness rest

-- |Fitness-proportionate (roulette-wheel) selection: select @n@
-- random items with each item's chance of being selected is
-- proportional to its score.
rouletteSelect :: Int -> SelectionOp a
rouletteSelect n xs = replicateM n roulette1
  where
  fs = map snd xs  -- fitnesses
  gs = map fst xs  -- genomes
  xs' = zip gs (scanl1 (+) fs)
  sumScores = (snd . last) xs'
  roulette1 = do
    rand <- (sumScores*) `liftM` getDouble
    return $ (fst . head . dropWhile ((rand >) . snd)) xs'

-- |Performs tournament selection amoing @size@ individuals and
-- returns the winner. Repeat @n@ times.
tournamentSelect :: Int -- ^ size of the tournament group
                 -> Int -- ^ how many tournaments to run
                 -> SelectionOp a
tournamentSelect size n xs = replicateM n tournament1
  where
  tournament1 = do
    contestants <- randomSample size xs
    let winner = head $ eliteGenomes contestants
    return winner

-- |Transform a maximizing selection operator to minimizing one
-- by changing fitness sign.
minimizing :: SelectionOp a -> SelectionOp a
minimizing = withFitnessScale negate

-- |Transform a maximizing selection operator to minimizing one
-- by applying @1/1+x@ fitness transform.
minimizing' :: SelectionOp a -> SelectionOp a
minimizing' = withFitnessScale (\x -> 1.0 / (1.0 + x))

-- | Sort population (a list of (genome,fitness) pairs) by fitness
-- (descending). The best genomes are put in the head of the list.
sortByFitness :: Population a -> Population a
sortByFitness = sortBy (flip compare `on` snd)

-- | Sort population by increasing fitness (also known as cost for
-- minimization problems). The genomes with the smallest fitness
-- (cost) are put in the head of the list.
sortByCost :: Population a -> Population a
sortByCost = sortBy (compare `on` snd)

-- | Takes a list of (genome,fitness) pairs and returns a list of
-- genomes sorted by fitness (descending)
eliteGenomes :: Population a -> [Genome a]
eliteGenomes = map takeGenome . sortByFitness