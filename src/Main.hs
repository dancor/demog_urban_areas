import Control.Applicative
import Control.Arrow
import Data.Char
import Data.Function
import Data.List
import Data.List.Split
import Data.Maybe
import System.Environment
import System.FilePath

data LineType = Header | Num | Word | Letter
  deriving (Eq, Show)

headerPrefixes = [
  "Demographia World Urban Areas: ",
  "Table 1",
  "LARGEST URBAN AREAS IN THE WORLD",
  "Threshold Population for Ranking",
  "Rank",
  "Geography",
  "Urban Area",
  "Population",
  "Estimate",
  "Year",
  "Base Year Land Area:",
  "Square",
  "Miles",
  "Land",
  "Area:",
  "Km2",
  "Density Base Year",
  "Popula-",
  "tion",
  "Method",
  "Area",
  "Source"
  ]

runTests testResPairs = head $ map snd (filter fst testResPairs)

lineGetType :: String -> LineType
lineGetType cs =
  runTests [
    (all (\ c -> isDigit c || c == ',') cs, Num),
    (any (`isPrefixOf` cs) headerPrefixes, Header),
    (length cs == 1 && all isUpper cs, Letter),
    (True, Word)
    ]

summ :: String -> String
summ s = 
  if length s <= half * 2 
    then s 
    else take (half - 1) s ++ ".." ++ drop (length s - half + 1) s
  where
  half = 80

toChunk lineType cs = 
  if null rem then Nothing else Just (snd $ head rem, tail rem) 
  where
  rem = dropWhile ((/= lineType) . fst) cs

getFirstPage cs = do
  (countries, cs2) <- toChunk Word cs
  (cities, cs3) <- toChunk Word cs2
  (pops, cs4) <- toChunk Num cs3
  (yrs, cs5) <- toChunk Num cs4
  (pop2sArea2s, cs6) <- toChunk Num cs5
  (dens2s, cs7) <- toChunk Num cs6
  (areas, cs8) <- toChunk Num cs7
  (denssYr2s, cs9) <- toChunk Num cs8
  let denss = map head $ splitEvery 2 denssYr2s
  r <- getPage cs9
  return $ zip3 countries cities pops ++ r

getPage cs = do
  (cc, cs2) <- toChunk Word cs
  let (countries:cities:_) = splitEvery (length cc `div` 2) cc
  (lol, cs3) <- toChunk Num cs2
  let [pops, yrs, pop2s, area2s, dens2s, areas, denss, yr2s] = 
        splitEvery (length lol `div` 8) lol
      r = case getPage cs3 of
        Nothing -> []
        Just r2 -> r2
  return (zip3 countries cities pops ++ r)

nationIsUN n =
  not $ any (`isInfixOf` n) [
    ":", "Germany-", "France-", "Switzerland &", "Austria &", "Bermuda",
    "Greenland", "Western Sahara"]

-- I have a certain set of names and abbrs. that I tend to stick too.
-- Also some other normalization and cleanup.
cleanData (n, c, p) = (f n, f c, p) where
  f x = case x of
    "United States" -> "USA"
    "Viet Nam" -> "Vietnam"
    "Congo (Dem. Rep.)" -> "DRCongo"
    "United Kingdom" -> "UK"
    "Ivory Coast" -> "Côte d'Ivoire"
    "United Arab Emirates" -> "UAE"
    "Congo (Rep.)" -> "RCongo"
    "Dijibouti" -> "Djibouti"
    "Central African Rep." -> "CAR"
    "Serbia-Montenegro" -> "Montenegro"
    "Katowice-Gliwice-Tychy" -> "Katowice"
    _ -> x

n2cp :: (String, String, String) -> (String, (Int, String))
n2cp (n, c, p) = (n, (read $ filter isDigit p, c))

expNot :: Double -> (Double, Int)
expNot x = 
  (c, e)
  where
  e = floor (logBase 10 x)
  c = x / (10 ** fromIntegral e)

-- result of (1234, 2) means 1.234e2
expNotSigDigs :: Int -> Double -> (Int, Int)
expNotSigDigs d x = (cSig', e')
  where
  (cSig', e') = 
    if length (show cSig) > d
      then (cSig `div` 10, e + 1) 
      else (cSig, e)
  cSig = round $ c * (10 ** fromIntegral (d - 1))
  (c, e) = expNot x

placeDecimal :: Int -> Int -> String
placeDecimal pos x = 
  l ++ (if null r then "" else "." ++ r)
  where
  l = take pos (sx ++ repeat '0')
  r = drop pos sx
  sx = show x

metricSigDigs :: Int -> Double -> (String, String)
metricSigDigs d x = 
  if e >= 6
    then (placeDecimal (e + 1 - 6) c, "M")
    else
      if e >= 3
        then (placeDecimal (e + 1 - 3) c, "k")
        else (placeDecimal (e + 1) c, "")
  where
  (c, e) = expNotSigDigs d x
  ds = show c
    
showN :: Int -> String
showN x = 
  c ++ suf
  where
  (c, suf) = metricSigDigs 2 (fromIntegral x) 
  
showLol :: (Maybe String, (Int, String)) -> String
showLol (n, (p, c)) = showN p ++ " " ++ (maybe "" (++ ": ") n) ++ c

main :: IO ()
main = do
  ls <- lines <$> readFile "data/raw_pdf_copy"
  args <- getArgs
  let 
    typeChunks =
      map (\ xs -> (fst (head xs), map snd xs)) .
      groupBy ((==) `on` fst) $
      map (\ l -> (lineGetType l, l)) ls    
    usageErr = error "Program was invoked with invalid arguments."
    runTypeArg = case args of
      [] -> "all"
      [x] -> x
      _ -> usageErr
    onePerNation = nubBy ((==) `on` fst)
    showNation = map (first Just)
    hideNation = map (first (const Nothing))
    (runType, filterFunc, finalFunc) = case runTypeArg of
      "all" -> (runTypeArg, const True, showNation)
      "un1" -> (runTypeArg, nationIsUN . fst, showNation . onePerNation)
      n -> ("by_nation" </> n, 
        (== map toLower n) . map toLower . fst, hideNation)
  {- analysis phase:
  putStr $ unlines $ map summ $
    map (\ (a, b) -> [head $ show a] ++ show (length b) ++ " " ++ 
                        intercalate " " b)
    typeChunks
 -- w(country) w(city) n(pop) n(yr) n(pop2,area2) n(dens2) n(area) n(dens,yr2)
 -- w(country)w(city) n(pop)n(yr)n(pop2)n(area2)n(dens2)n(area)n(dens)n(yr2)
  -}
  writeFile ("output" </> runType) . unlines .
    map showLol .
    finalFunc .
    filter filterFunc .
    map (\ (n, c, p) -> (n, (read $ filter isDigit p, c))) .
    map cleanData .
    fromJust $
    getFirstPage typeChunks
