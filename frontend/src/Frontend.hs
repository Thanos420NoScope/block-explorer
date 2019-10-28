{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
module Frontend where

------------------------------------------------------------------------------
import           Control.Monad
import           Control.Monad.Reader
import           Control.Monad.Ref
import           Data.Aeson
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import           Data.Ord
import           Data.Readable
import           Data.Text (Text)
import qualified Data.Text as T
import           Data.Time
import           Data.Time.Clock.POSIX
import           GHCJS.DOM.Types (MonadJSM)
import           Obelisk.Frontend
import           Obelisk.Generated.Static
import           Obelisk.Route
import           Obelisk.Route.Frontend
import           Reflex.Dom.Core hiding (Value)
import           Reflex.Network
import           Text.Printf
------------------------------------------------------------------------------
import           Common.Route
import           Common.Types
import           Common.Utils
import           Frontend.About
import           Frontend.App
import           Frontend.AppState
import           Frontend.ChainwebApi
import           Frontend.Common
import           Frontend.Nav
import           Frontend.Page.Block
------------------------------------------------------------------------------

frontend :: Frontend (R FrontendRoute)
frontend = Frontend
  { _frontend_head = appHead
  , _frontend_body = do
      route <- getAppRoute
      curNet <- divClass "ui fixed inverted menu" nav
      _ <- elAttr "div" ("class" =: "ui main container" <> "style" =: "width: 1124px;") $
        networkView (appWithNetwork route <$> curNet)
      footer
      display =<< askRoute
  }

appWithNetwork
  :: (SetRoute t (R FrontendRoute) (Client (Client m)),
      Routed t (R FrontendRoute) (Client m),
      RouteToUrl (R FrontendRoute) (Client (Client m)),
      DomBuilder t m, Prerender js t m)
  => Text
  -> Maybe Network
  -> m ()
appWithNetwork route Nothing = do
  divClass "ui segment" $ do
    divClass "ui active dimmer" $ do
      divClass "ui text loader" $ text "Loading"
    el "p" $ text " "
    el "p" $ text " "
    el "p" $ text " "
appWithNetwork route (Just curNet) = do
  let ch = networkHost curNet
  _ <- prerender blank $ do
    dsi <- getServerInfo ch
    void $ networkView (appWithServer route ch <$> dsi)
  return ()

appWithServer
  :: (DomBuilder t m, Routed t (R FrontendRoute) m, MonadHold t m, MonadFix m,
      Prerender js t m, PostBuild t m, MonadJSM (Performable m),
      HasJSContext (Performable m), PerformEvent t m, TriggerEvent t m,
      RouteToUrl (R FrontendRoute) (Client m), MonadRef m, MonadSample t (Performable m),
      SetRoute t (R FrontendRoute) (Client m),
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m)
  => Text
  -> ChainwebHost
  -> Maybe ServerInfo
  -> m ()
appWithServer _ _ Nothing = text "Loading server info..."
appWithServer route ch (Just si) = runApp route ch si mainApp

getServerInfo
  :: (PostBuild t m, TriggerEvent t m, PerformEvent t m,
      HasJSContext (Performable m), MonadJSM (Performable m), MonadHold t m)
  => ChainwebHost
  -> m (Dynamic t (Maybe ServerInfo))
getServerInfo h = do
  pb <- getPostBuild
  ese <- cutToServerInfo <$$$> getCut (h <$ pb)
  holdDyn Nothing ese

mainApp
  :: (MonadApp r t m, Prerender js t m, MonadJSM (Performable m), HasJSContext (Performable m),
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m)
  => App (R FrontendRoute) t m ()
mainApp = do
    pb <- getPostBuild
    subRoute_ $ \case
      FR_Main -> setRoute ((FR_Testnet :/ NetRoute_Chainweb :/ ()) <$ pb)
      FR_About -> aboutWidget
      FR_Mainnet -> blockTableWidget
      FR_Testnet -> blockTableWidget
      FR_Customnet -> subPairRoute_ $ \domain -> do
        blockPage $ NetId_Custom (ChainwebHost h Testnet02)
        --case fromText domain of
        --  Nothing -> text "Error in URL"
        --  Just h -> text $ "got host " <> h --blockPage $ NetId_Custom (ChainwebHost h Testnet02)

networkDispatch
  :: MonadApp r t m
  => NetId
  -> m ()
networkDispatch net = do
  subRuote_ $ \case
    NetRoute_Chainweb -> blockTableWidget
    NetRoute_Chain -> blockPage


footer
  :: (DomBuilder t m)
  => m ()
footer = do
    divClass "ui inverted vertical footer segment" $ do
      divClass "ui center aligned container" $ do
        elAttr "img" ("src" =: static @"kadena-k-logo.png" <>
                    "class" =: "ui centered mini image" <>
                    "alt" =: "Kadena" ) blank
        divClass "ui horizontal inverted small divided link list" $ do
          lnk "Discord" "https://discordapp.com/invite/bsUcWmX"
          lnk "Twitter" "https://twitter.com/kadena_io"
          lnk "Medium" "https://medium.com/kadena-io/"
          lnk "GitHub" "https://github.com/kadena-io/"
          lnk "YouTube" "https://www.youtube.com/KadenaBlockchain"
  where
    lnk nm url = elAttr "a" ("class" =: "item" <> "href" =: url) $ text nm


appHead :: DomBuilder t m => m ()
appHead = do
  el "title" $ text "Kadena Block Explorer"
  elAttr "link" ("rel" =: "shortcut icon" <>
                 "href" =: "/static/favicon.svg" <>
                 "type" =: "image/svg+xml"
                ) blank

  css (static @"semantic.min.css")
  css (static @"css/custom.css")
  --jsScript "https://cdnjs.cloudflare.com/ajax/libs/jquery/2.2.3/jquery.min.js"
  jsScript (static @"jquery-3.1.1.min.js")
  jsScript (static @"semantic.min.js")

css :: DomBuilder t m => Text -> m ()
css url = elAttr "link" ("rel" =: "stylesheet" <> "type" =: "text/css" <> "href" =: url) blank

jsScript :: DomBuilder t m => Text -> m ()
jsScript url = elAttr "script" ("src" =: url <> "type" =: "text/javascript") blank

script :: DomBuilder t m =>  Text -> m ()
script code = elAttr "script" ("type" =: "text/javascript") $ text code

leftAndRightBorder :: Text
leftAndRightBorder = "border-left: 1px solid rgba(34,36,38,.1); border-right: 1px solid rgba(34,36,38,.1);"

showResp :: Maybe Value -> String
showResp = show

statistic :: (DomBuilder t m) => Text -> m () -> m ()
statistic label val = do
  divClass "statistic" $ do
    divClass "value" $ val
    divClass "label" $ text label

calcTps :: GlobalStats -> NominalDiffTime -> Double
calcTps gs elapsed = fromIntegral (_gs_txCount gs) / realToFrac elapsed

showTps :: Double -> Text
showTps = T.pack . printf "%.2f"

blockTableWidget
  :: (MonadApp r t m, Prerender js t m,
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m)
  => App r t m ()
blockTableWidget = do
  as <- ask
  let stats = _as_stats as
      dbt = _as_blockTable as

  dti <- fmap join $ prerender (return $ constDyn dummy) $ do
    t <- liftIO getCurrentTime
    clockLossy 1 t

  let elapsedTime gs ti = diffUTCTime (_tickInfo_lastUTC ti) (_gs_startTime gs)
      elapsed = elapsedTime <$> stats <*> dti
      tps = calcTps <$> stats <*> elapsed
      hashrate = (\ti s -> calcNetworkHashrate (utcTimeToPOSIXSeconds $ _tickInfo_lastUTC ti) s) <$> dti <*> dbt

  divClass "ui segment" $ divClass "ui three statistics" $ do
    statistic "Est. Network Hash Rate" (dynText $ maybe "-" ((<>"/s") . diffStr) <$> hashrate)
    statistic "Transactions Received" (dynText $ tshow . _gs_txCount <$> stats)
    statistic "Current TPS" (dynText $ showTps <$> tps)

  divClass "block-table" $ do
    divClass "header-row" $ do
      elClass "span" "table-header" $ text "Height"
      chains <- asks (_siChains . _as_serverInfo)
      forM_ chains $ \cid -> elClass "span" "table-header" $ do
        el "div" $ text $ "Chain " <> tshow cid
        elAttr "div" ("data-tooltip" =: "The expected number of hashes to mine a block on this chain" <>
                      "data-variation" =: "narrow") $ dynText $ chainDifficulty cid <$> dbt

    rec hoverChanges <- listWithKey (M.mapKeys Down . _blockTable_blocks <$> dbt)
                                    (rowsWidget dti hoveredBlock)
        hoveredBlock <- holdDyn Nothing (switch $ current $ leftmost . M.elems <$> hoverChanges)
    return ()
  where
    dummy = TickInfo (UTCTime (ModifiedJulianDay 0) 0) 0 0

chainDifficulty :: ChainId -> BlockTable -> Text
chainDifficulty cid bt =
  maybe "" (\b -> diffStr (blockDifficulty $ _blockHeaderTx_header b)) $
    M.lookup cid $ _blockTable_cut bt

rowsWidget
  :: (MonadApp r t m, Prerender js t m,
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m)
  => Dynamic t TickInfo
  -> Dynamic t (Maybe BlockRef)
  -> Down BlockHeight
  -> Dynamic t (Map ChainId BlockHeaderTx)
  -> m (Event t (Maybe BlockRef))
rowsWidget ti hoveredBlock (Down bh) cs = mdo
  hoverChanges <- blockHeightRow ti hoveredBlock bh cs
  chains <- asks (_siChains . _as_serverInfo)
  spacerRow chains cs hoveredBlock bh
  return hoverChanges

blockHeightRow
  :: (MonadApp r t m, Prerender js t m,
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m)
  => Dynamic t TickInfo
  -> Dynamic t (Maybe BlockRef)
  -> BlockHeight
  -> Dynamic t (Map ChainId BlockHeaderTx)
  -> m (Event t (Maybe BlockRef))
blockHeightRow ti hoveredBlock height headers = do
  divClass "block-row" $ do
    elClass "span" "block-height" $ text $ tshow height
    chains <- asks (_siChains . _as_serverInfo)
    es <- forM chains $ blockWidget0 ti hoveredBlock headers height
    return $ (height,) <$$> leftmost es

blockWidget0
  :: (MonadApp r t m, Prerender js t m,
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m)
  => Dynamic t TickInfo
  -> Dynamic t (Maybe BlockRef)
  -> Dynamic t (Map ChainId BlockHeaderTx)
  -> BlockHeight
  -> ChainId
  -> m (Event t (Maybe ChainId))
blockWidget0 ti hoveredBlock hs height cid = do
  let mkAttrs = \case
        Nothing -> "class" =: "summary-details"
        Just hb -> if isDownstreamFrom hb (height, cid)
                     then "class" =: "summary-details hovered-block"
                     else "class" =: "summary-details"
  let mbh = M.lookup cid <$> hs
  (e,_) <- elDynAttr' "span" (mkAttrs <$> hoveredBlock) $ do
    viewIntoMaybe mbh blank $ \bh -> do
      divClass "summary-inner" $ do
        el "div" $ do
          let getHash = hashB64U . _blockHeader_hash . _blockHeaderTx_header
          let mkRoute h = addNetRoute NetId_Testnet $ unChainId cid :. getHash h :. Block_Header :/ () --TODO: Which NetId should it be?
          elClass "span" "blockheight" $ do
            dynRouteLink (mkRoute <$> bh) $
              dynText $ T.take 8 . hashHex . _blockHeader_hash . _blockHeaderTx_header <$> bh

        let getCreationTime = posixSecondsToUTCTime . _blockHeader_creationTime . _blockHeaderTx_header
        void $ prerender blank $ divClass "blockdiv" $
          pastTimeWidget ti (Just . getCreationTime <$> bh)

        divClass "blockdiv" $ do
          dynText $ maybe "" (\c -> tshow c <> " txs") . _blockHeaderTx_txCount <$> bh

        --divClass "blockdiv" $ do
        --  dynText $ diffStr . fromIntegral . targetToDifficulty . leToInteger .
        --            unBytesLE . _blockHeader_target . _blockHeaderTx_header <$> bh

  return $ leftmost [ fmap (const cid) <$> tag (current mbh) (domEvent Mouseenter e)
                    , Nothing <$ domEvent Mouseleave e]

diffStr :: Double -> Text
diffStr d = T.pack $ printf "%.2f %s" (d / divisor) units
  where
    (divisor, units :: String)
      | d >= 1e12 = (1e12, "TH")
      | d >= 1e9 = (1e9, "GH")
      | d >= 1e6 = (1e6, "MH")
      | d >= 1e3 = (1e3, "KH")
      | otherwise = (1, "H")

pastTimeWidget
  :: (DomBuilder t m, PostBuild t m)
  => Dynamic t TickInfo
  -> Dynamic t (Maybe UTCTime)
  -> m ()
pastTimeWidget ti dt = do
  let calcDiff lastTick t = maybe "" (diffTimeToSecsAgo . diffUTCTime (_tickInfo_lastUTC lastTick)) t
  dynText (calcDiff <$> ti <*> dt)


diffTimeToSecsAgo :: NominalDiffTime -> Text
diffTimeToSecsAgo delta = tshow (roundInt delta) <> "s ago"

--diffTimeToRelativeEnglish :: NominalDiffTime -> Text
--diffTimeToRelativeEnglish delta
--  | delta < 5 = "Just now"
--  | delta < oneMinute * 2 = tshow (roundInt delta) <> " secs ago"
--  | delta < oneHour = tshow (roundInt $ delta / oneMinute) <> " min ago"
--  | delta < oneHour * 2 = "an hour ago"
--  | delta < oneDay = tshow (roundInt $ delta / oneHour) <> " hours ago"
--  | delta < oneDay * 2 = "1 day ago"
--  | delta < oneWeek = tshow (roundInt $ delta / oneDay) <> " days ago"
--  | delta < oneWeek * 2 = "1 week ago"
--  | delta < oneMonth = tshow (roundInt $ delta / oneWeek) <> " weeks ago"
--  | delta < oneMonth * 2 = "1 month ago"
--  | delta < oneYear = tshow (roundInt $ delta / oneMonth) <> " months ago"
--  | delta < oneYear * 2 = "a year ago"
--  | otherwise = tshow (roundInt $ delta / oneYear) <> " years ago"

roundInt :: NominalDiffTime -> Int
roundInt = round

oneMinute :: NominalDiffTime
oneMinute = 60
oneHour :: NominalDiffTime
oneHour = oneMinute * 60
oneDay :: NominalDiffTime
oneDay = oneHour * 24
oneWeek :: NominalDiffTime
oneWeek = oneDay * 7
oneMonth :: NominalDiffTime
oneMonth = oneDay * 30
oneYear :: NominalDiffTime
oneYear = oneDay * 365

blockWidth :: Int
blockWidth = 110

blockSeparation :: Int
blockSeparation = 50

spacerRow
  :: (DomBuilder t m, PostBuild t m)
  => [ChainId]
  -> Dynamic t (Map ChainId BlockHeaderTx)
  -> Dynamic t (Maybe BlockRef)
  -> BlockHeight
  -> m ()
spacerRow chains cs hoveredBlock bh = do
  let sty = "margin-left: 102px; height: " <> tshow blockSeparation <> "px; " <>
            "border: 0; padding: 0;"
  elAttr "div" ("class" =: "spacer-row" <>
                "style" =: sty ) $ do
    chainweb chains cs hoveredBlock bh

svgElDynAttr
  :: (DomBuilder t m, PostBuild t m)
  => Text
  -> Dynamic t (Map Text Text)
  -> m a
  -> m a
svgElDynAttr elTag attrs child = elDynAttrNS (Just "http://www.w3.org/2000/svg") elTag attrs child

svgElAttr
  :: (DomBuilder t m, PostBuild t m)
  => Text
  -> Map Text Text
  -> m a
  -> m a
svgElAttr elTag attrs child = svgElDynAttr elTag (constDyn attrs) child

chainweb
  :: (DomBuilder t m, PostBuild t m)
  => [ChainId]
  -> Dynamic t (Map ChainId BlockHeaderTx)
  -> Dynamic t (Maybe BlockRef)
  -> BlockHeight
  -> m ()
chainweb chains cs hoveredBlock bh = do
  let attrs = ("viewBox" =: ("0 0 1100 " <> tshow (blockSeparation + 4)) <>
               "style" =: "vertical-align: middle;")
  svgElAttr "svg" attrs $ do
    forM_ chains (\c -> linksFromBlock cs hoveredBlock (bh, c))
    void $ networkView $ lastLinesForActiveBlock cs hoveredBlock bh <$> hoveredBlock

lastLinesForActiveBlock
  :: (DomBuilder t m, PostBuild t m)
  => Dynamic t (Map ChainId BlockHeaderTx)
  -> Dynamic t (Maybe BlockRef)
  -> BlockHeight
  -> Maybe BlockRef
  -> m ()
lastLinesForActiveBlock _ _ _ Nothing = blank
lastLinesForActiveBlock cs hoveredBlock curBH (Just b) =
  if curBH > (fst b) then blank else linksFromBlock cs hoveredBlock b

fromPos :: Int -> Int
fromPos f = blockWidth `div` 2 + f * blockWidth

toPos :: Int -> Int
toPos t = blockWidth `div` 2 + t * blockWidth

linksFromBlock
  :: (DomBuilder t m, PostBuild t m)
  => Dynamic t (Map ChainId BlockHeaderTx)
  -> Dynamic t (Maybe BlockRef)
  -> BlockRef
  -> m ()
linksFromBlock cs hoveredBlock fromBlock = do
  let from = unChainId $ snd fromBlock
  let toBlocks = petersonGraph M.! from
      mkAttrs bs mhb = stroke <> (maybe ("style" =: "display: none;") mempty (M.lookup (snd fromBlock) bs))
        where
          heightDiff b = fst b - fst fromBlock
          stroke =
            case mhb of
              Nothing -> "stroke" =: "rgb(220,220,220)"
              Just hb ->
                if fst fromBlock > fst hb
                  then "stroke" =: "rgb(220,220,220)"
                  else if hb == fromBlock ||
                          heightDiff hb > 0
                         then "stroke" =: "rgb(100,100,100)" <>
                              "stroke-width" =: "1.0"
                         else "stroke" =: "rgb(220,220,220)"
  svgElDynAttr "g" (mkAttrs <$> cs <*> hoveredBlock) $ do
    linkFromTo from from
    mapM_ (linkFromTo from) toBlocks

linkFromTo :: (DomBuilder t m, PostBuild t m) => Int -> Int -> m ()
linkFromTo f t =
    svgElAttr "line" ("x1" =: (tshow $ fromPos f) <>
                      "y1" =: "0" <>
                      "x2" =: (tshow $ toPos t) <>
                      "y2" =: (tshow (blockSeparation + 4)) ) blank

type BlockRef = (BlockHeight, ChainId)

isDownstreamFrom :: BlockRef -> BlockRef -> Bool
isDownstreamFrom (ph, ChainId pc) (h, ChainId c)
  | h > ph = False
  | otherwise = shortestPath pc c <= ph - h

petersonGraph :: M.Map Int [Int]
petersonGraph = M.fromList
    [ (0, [2,3,5])
    , (1, [3,4,6])
    , (2, [4,0,7])
    , (3, [0,1,8])
    , (4, [1,2,9])
    , (5, [0,6,9])
    , (6, [1,5,7])
    , (7, [2,6,8])
    , (8, [3,7,9])
    , (9, [4,8,5])
    ]

shortestPath :: Int -> Int -> Int
shortestPath from to = shortestPaths M.! (from * 10 + to)

shortestPaths :: M.Map Int Int
shortestPaths = M.fromList $ zip [0..]
    [ 0, 2, 1, 1, 2, 1, 2, 2, 2, 2
    , 2, 0, 2, 1, 1, 2, 1, 2, 2, 2
    , 1, 2, 0, 2, 1, 2, 2, 1, 2, 2
    , 1, 1, 2, 0, 2, 2, 2, 2, 1, 2
    , 2, 1, 1, 2, 0, 2, 2, 2, 2, 1
    , 1, 2, 2, 2, 2, 0, 1, 2, 2, 1
    , 2, 1, 2, 2, 2, 1, 0, 1, 2, 2
    , 2, 2, 1, 2, 2, 2, 1, 0, 1, 2
    , 2, 2, 2, 1, 2, 2, 2, 1, 0, 1
    , 2, 2, 2, 2, 1, 1, 2, 2, 1, 0
    ]
