
module HOI4.SpecialHandlers (
        handleIdeas
    ,   handleTimedIdeas
    ,   handleSwapIdeas
    ,   handleModifier
    ,   showIdea
    ,   plainmodifiermsg
    ,   modifierMSG
    ,   handleResearchBonus
    ,   handleHiddenModifier
    ,   handleTargetedModifier
    ,   handleEquipmentBonus
    ,   modifiersTable
    ,   addDynamicModifier
    ,   removeDynamicModifier
    ,   hasDynamicModifier
    ,   addPowerBalanceModifier
    ,   addFieldMarshalRole
    ,   addAdvisorRole
    ,   removeAdvisorRole
    ,   addLeaderRole
    ,   createLeader
    ,   promoteCharacter
    ,   setCharacterName
    ,   withCharacter
    ,   createOperativeLeader
    ,   handleTrait
    ,   addRemoveLeaderTrait
    ,   addRemoveUnitTrait
    ,   addTimedTrait
    ,   swapLeaderTrait
    ) where

import Data.Text (Text)
import qualified Data.Text as T

import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
--import Data.Set (Set)


import Data.List (foldl', sortOn, elemIndex)
import Data.Maybe

import Control.Monad.State (gets)
import Data.Foldable (fold)

import Abstract -- everything
import qualified Doc -- everything
import HOI4.Messages -- everything
import MessageTools (iquotes

                    , formatDays)
import QQ -- everything
-- everything
import SettingsTypes ( PPT, IsGameData (..), GameData (..), IsGameState (..), GameState (..)
                     , indentUp, getCurrentIndent, withCurrentIndent, withCurrentIndentCustom
                     , getGameL10n, getGameL10nIfPresent
                     , concatMapM
                     , getGameInterface, getGameInterfaceIfPresent)
import {-# SOURCE #-} HOI4.Common (ppMany, ppOne, extractStmt, matchLhsText)
import HOI4.Types -- everything
import Debug.Trace
import HOI4.Handlers -- everything

-----------------
-- handle idea --
-----------------

handleSwapIdeas :: forall g m. (HOI4Info g, Monad m) =>
        StatementHandler g m
handleSwapIdeas stmt@[pdx| %_ = @scr |]
    = pp_si (parseTA "add_idea" "remove_idea" scr)
    where
        pp_si :: TextAtom -> PPT g m IndentedMessages
        pp_si ta = case (ta_what ta, ta_atom ta) of
            (Just what, Just atom) -> do
                add_loc <- handleIdea True what
                remove_loc <- handleIdea False atom
                case (add_loc, remove_loc) of
                    (Just (addcategory, addideaIcon, addideaKey, addidea_loc, Just addeffectbox),
                     Just (category, ideaIcon, ideaKey, idea_loc, _)) ->
                        if addidea_loc == idea_loc then do
                                idmsg <- msgToPP $ MsgModifyIdea category ideaIcon ideaKey idea_loc
                                                    addcategory addideaIcon addideaKey addidea_loc
                                return $ idmsg ++ addeffectbox
                        else do
                            idmsg <- msgToPP $ MsgReplaceIdea category ideaIcon ideaKey idea_loc
                                                addcategory addideaIcon addideaKey addidea_loc
                            return $ idmsg ++ addeffectbox
                    (Just (addcategory, addideaIcon, addideaKey, addidea_loc, Nothing),
                     Just (category, ideaIcon, ideaKey, idea_loc, _)) ->
                        if addidea_loc == idea_loc then
                            msgToPP $ MsgModifyIdea category ideaIcon ideaKey idea_loc
                                addcategory addideaIcon addideaKey addidea_loc
                        else
                            msgToPP $ MsgReplaceIdea category ideaIcon ideaKey idea_loc
                                addcategory addideaIcon addideaKey addidea_loc
                    _ -> preStatement stmt
            _ -> preStatement stmt
handleSwapIdeas stmt = preStatement stmt

handleTimedIdeas :: forall g m. (HOI4Info g, Monad m) =>
        (Text -> Text -> Text -> Text -> Double -> ScriptMessage) -- ^ Message constructor, if abs value >= 1
        -> StatementHandler g m
handleTimedIdeas msg stmt@[pdx| %_ = @scr |]
    = pp_idda (parseTV "idea" "days" scr)
    where
        pp_idda :: TextValue -> PPT g m IndentedMessages
        pp_idda tv = case (tv_what tv, tv_value tv) of
            (Just what, Just value) -> do
                ideashandled <- handleIdea True what
                case ideashandled of
                    Just (category, ideaIcon, ideaKey, idea_loc, Just effectbox) -> do
                        idmsg <- msgToPP $ msg category ideaIcon ideaKey idea_loc value
                        return $ idmsg ++ effectbox
                    Just (category, ideaIcon, ideaKey, idea_loc, Nothing) -> msgToPP $ msg category ideaIcon ideaKey idea_loc value
                    Nothing -> preStatement stmt
            _ -> preStatement stmt
handleTimedIdeas _ stmt = preStatement stmt

handleIdeas :: forall g m. (HOI4Info g, Monad m) =>
    Bool ->
    (Text -> Text -> Text -> Text -> ScriptMessage)
        -> StatementHandler g m
handleIdeas addIdea msg stmt@[pdx| $lhs = %idea |] = case idea of
    CompoundRhs ideas -> if length ideas == 1 then do
                ideashandled <- handleIdea addIdea (mconcat $ map getbareidea ideas)
                case ideashandled of
                    Just (category, ideaIcon, ideaKey, idea_loc, Just effectbox) -> do
                        idmsg <- msgToPP $ msg category ideaIcon ideaKey idea_loc
                        return $ idmsg ++ effectbox
                    Just (category, ideaIcon, ideaKey, idea_loc, Nothing) -> msgToPP $ msg category ideaIcon ideaKey idea_loc
                    Nothing -> preStatement stmt
            else do
                ideashandle <- mapM (handleIdea addIdea . getbareidea) ideas
                let ideashandled = catMaybes ideashandle
                    ideasmsgd :: [(Text, Text, Text, Text, Maybe IndentedMessages)] -> PPT g m [IndentedMessages]
                    ideasmsgd ihs = mapM (\ih ->
                            let (category, ideaIcon, ideaKey, idea_loc, effectbox) = ih in
                            withCurrentIndent $ \i -> case effectbox of
                                    Just boxNS -> return ((i, msg category ideaIcon ideaKey idea_loc):boxNS)
                                    _-> return [(i, msg category ideaIcon ideaKey idea_loc)]
                                ) ihs
                ideasmsgdd <- ideasmsgd ideashandled
                return $ mconcat ideasmsgdd
    GenericRhs txt [] -> do
        ideashandled <- handleIdea addIdea txt
        case ideashandled of
            Just (category, ideaIcon, ideaKey, idea_loc, Just effectbox) -> do
                idmsg <- msgToPP $ msg category ideaIcon ideaKey idea_loc
                return $ idmsg ++ effectbox
            Just (category, ideaIcon, ideaKey, idea_loc, Nothing) -> msgToPP $ msg category ideaIcon ideaKey idea_loc
            Nothing -> preStatement stmt
    _ -> preStatement stmt
handleIdeas _ _ stmt = preStatement stmt

getbareidea :: GenericStatement -> Text
getbareidea (StatementBare (GenericLhs e [])) = e
getbareidea _ = "<!-- Check Script -->"

handleIdea :: (HOI4Info g, Monad m) =>
        Bool -> Text ->
           PPT g m (Maybe (Text, Text, Text, Text, Maybe IndentedMessages))
handleIdea addIdea ide = do
    ides <- getIdeas
    charto <- getCharToken
    let midea = HM.lookup ide ides
    case midea of
        Just iidea -> do
            let ideaKey = id_id iidea
                ideaname = id_name iidea
            ideaIcon <- do
                micon <- getGameInterfaceIfPresent ("GFX_idea_" <> ideaKey)
                case micon of
                    Nothing -> getGameInterface "idea_unknown" (id_picture iidea)
                    Just idicon -> return idicon
            idea_loc <- getGameL10n ideaname
            category <- if id_category iidea == "country" then getGameL10n "FE_COUNTRY_SPIRIT" else getGameL10n $ id_category iidea
            effectbox <- modmessage iidea idea_loc ideaKey ideaIcon
            effectboxNS <- if id_category iidea == "country" && addIdea then return $ Just effectbox else return Nothing
            return $ Just (category, ideaIcon, ideaKey, idea_loc, effectboxNS)
        Nothing -> case HM.lookup ide charto of
            Nothing -> return Nothing
            Just cchat -> do
                let namekey = adv_cha_id cchat
                mloc <- getGameL10nIfPresent $ adv_cha_name cchat
                name_loc <- case mloc of
                    Just nloc -> return nloc
                    _ -> getGameL10n $ adv_idea_token cchat
                slot <- getGameL10n (adv_advisor_slot cchat)
                return $ Just (slot, "", namekey, name_loc, Nothing)


showIdea :: (HOI4Info g, Monad m) => StatementHandler g m
showIdea stmt@[pdx| $lhs = $idea |] = do
    ides <- getIdeas
    charto <- getCharToken
    case HM.lookup idea ides of
        Just iidea -> do
            modifier <- maybe (return []) (indentUp . ppOne) (id_modifier iidea)
            targeted_modifier <-
                maybe (return []) (indentUp . concatMapM handleTargetedModifier) (id_targeted_modifier iidea)
            research_bonus <- maybe (return []) (indentUp . ppOne) (id_research_bonus iidea)
            equipment_bonus <- maybe (return []) (indentUp . ppOne) (id_equipment_bonus iidea)
            let ideamods = modifier ++ targeted_modifier ++ research_bonus ++ equipment_bonus
            idea_loc <- getGameL10n (id_name iidea)
            basemsg <- msgToPP $ MsgShowIdea idea_loc idea
            return $ basemsg ++ ideamods
        Nothing -> case HM.lookup idea charto of
            Nothing -> preStatement stmt
            Just ccharto -> do
                let traits = case adv_traits ccharto of
                        Just trts -> trts
                        _-> []
                mloc <- getGameL10nIfPresent $ adv_cha_name ccharto
                name_loc <- case mloc of
                    Just nloc -> return nloc
                    _ -> getGameL10n $ adv_idea_token ccharto
                modmsg <- maybe (return []) (indentUp .handleModifier) (adv_modifier ccharto)
                resmsg <- maybe (return []) (indentUp .handleResearchBonus) (adv_research_bonus ccharto)
                traitmsg <- concatMapM ppHt traits
                basemsg <- msgToPP $ MsgShowIdea name_loc idea
                return $ basemsg ++ traitmsg ++ modmsg ++ resmsg
showIdea stmt = preStatement stmt

modmessage :: forall g m. (HOI4Info g, Monad m) => HOI4Idea -> Text -> Text -> Text -> PPT g m IndentedMessages
modmessage iidea idea_loc ideaKey ideaIcon = do
        curind <- getCurrentIndent
        curindent <- case curind of
            Just curindt -> return curindt
            _ -> return 1
        withCurrentIndentCustom 1 $ \_ -> do
            ideaDesc <- case id_desc_loc iidea of
                Just desc -> return $ Doc.nl2br desc
                _ -> return ""
            traitmsg <- case id_traits iidea of
                Just arr -> do
                    let traitbare = mapMaybe getbaretraits arr
                    concatMapM (\t-> do
                        traitloc <- getGameL10n t
                        namemsg <- plainMsg' ("'''" <> traitloc <> "'''")
                        traitmsg <- indentUp $ getLeaderTraits t
                        return $ namemsg : traitmsg) traitbare
                _-> return []
            modifier <- maybe (return []) ppOne (id_modifier iidea)
            targeted_modifier <-
                maybe (return []) (concatMapM handleTargetedModifier) (id_targeted_modifier iidea)
            research_bonus <- maybe (return []) ppOne (id_research_bonus iidea)
            equipment_bonus <- maybe (return []) ppOne (id_equipment_bonus iidea)
            let boxend = [(0, MsgEffectBoxEnd curindent)]
            withCurrentIndentCustom curindent $ \_ -> do
                let ideamods = traitmsg ++modifier ++ targeted_modifier ++ research_bonus ++ equipment_bonus ++ boxend
                return $ (0, MsgEffectBox idea_loc ideaKey ideaIcon ideaDesc) : ideamods


-----------------------
-- modifier handlers --
-----------------------
plainmodifiermsg :: forall g m. (HOI4Info g, Monad m) =>
        ScriptMessage -> StatementHandler g m
plainmodifiermsg msg stmt@[pdx| %_ = @scr |] = do
    let (mmod, _) = extractStmt (matchLhsText "modifier") scr
    modmsg <- case mmod of
        Just stmt@[pdx| modifier = @_ |] -> indentUp $ handleModifier stmt
        _ -> preStatement stmt
    basemsg <- msgToPP msg
    return $ basemsg ++ modmsg
plainmodifiermsg _ stmt = preStatement stmt

handleModifier :: forall g m. (HOI4Info g, Monad m) =>
        StatementHandler g m
handleModifier [pdx| %_ = @scr |] = do
    keys <- getModKeys
    sm <- sortmods scr keys
    fold <$> traverse (modifierMSG False "") sm
handleModifier stmt = preStatement stmt

sortmods :: forall g m. (HOI4Info g, Monad m) => GenericScript -> [Text] -> PPT g m GenericScript
sortmods scr keys = modsrec' keys scr [] [] [] []
    where
    modsrec' :: forall g m. (HOI4Info g, Monad m) => [Text] -> GenericScript ->[(Int,GenericStatement)] -> GenericScript -> GenericScript -> GenericScript -> PPT g m GenericScript
    modsrec' _ [] ord_mod unord_mod hid_mod custom =
        let moo = map snd $ sortOn fst ord_mod in
        return $  moo ++ reverse unord_mod ++ reverse hid_mod ++ reverse custom
    modsrec' keys (stmt:xs) ord_mod unord_mod hid_mod custom = case stmt of
        [pdx| hidden_modifier = %_|] ->
            let hr = stmt:hid_mod in
            modsrec' keys xs ord_mod unord_mod hr custom
        [pdx| custom_modifier_tooltip = %_|] ->
            let cr = stmt:custom in
            modsrec' keys xs ord_mod unord_mod hid_mod cr
        [pdx| $mod = %_|] -> case elemIndex mod keys of
            Just num ->
                let mor = (num,stmt):ord_mod in
                modsrec' keys xs mor unord_mod hid_mod custom
            Nothing ->
                let sr = stmt:unord_mod in
                modsrec' keys xs ord_mod sr hid_mod custom
        _ -> let sr = stmt:unord_mod in modsrec' keys xs ord_mod sr hid_mod custom

modifierMSG :: forall g m. (HOI4Info g, Monad m) =>
        Bool -> Text -> StatementHandler g m
modifierMSG _ targ stmt@[pdx| $specmod = @scr|]
    | specmod == "hidden_modifier" = do
        keys <- getModKeys
        sm <- sortmods scr keys
        fold <$> traverse (modifierMSG True targ) sm
    | otherwise = do
        terrain <- getTerrain
        if specmod `elem` terrain || specmod `elem` ["fort", "river", "night"]
        then do
            ter <- getGameL10n specmod
            termsg <- plainMsg' ("{{color|Yellow|" <> ter <> "}}:")
            modmsg <- fold <$> indentUp (traverse (modifierMSG False targ) scr)
            return $ termsg : modmsg
        else trace ("unknown modifier type: " ++ show specmod ++ " IN: " ++ show stmt) $ preStatement stmt
modifierMSG hidden targ stmt@[pdx| $mod = !num |] = let lmod = T.toLower mod in case HM.lookup lmod modifiersTable of
    Just (key, msg) -> do
        loc <- getGameL10n key
        let bonus = num :: Double
            loc' = locprep hidden targ loc
        numericLoc loc' msg stmt
    Nothing
        | "cat_" `T.isPrefixOf` lmod -> do
            mloc <- getGameL10nIfPresent lmod
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    numericLoc loc' MsgModifierPcNegReduced stmt
                Nothing -> preStatement stmt
        | ("production_speed_" `T.isPrefixOf` lmod && "_factor" `T.isSuffixOf` lmod) ||
            ("state_production_speed_" `T.isPrefixOf` lmod && "_factor" `T.isSuffixOf` lmod) ||
            ("experience_gain_" `T.isPrefixOf` lmod && "_combat_factor" `T.isSuffixOf` lmod) ||
            ("trait_" `T.isPrefixOf` lmod && "_xp_gain_factor" `T.isSuffixOf` lmod) ||
            ("repair_speed" `T.isPrefixOf` lmod && "_factor" `T.isSuffixOf` lmod) ||
            ("state_repair_speed" `T.isPrefixOf` lmod && "_factor" `T.isSuffixOf` lmod) -> do --precision 2
            mloc <- getGameL10nIfPresent ("modifier_" <> lmod)
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    numericLoc loc' MsgModifierPcPosReduced stmt
                Nothing -> preStatement stmt
        | "unit_" `T.isPrefixOf` lmod && "_design_cost_factor" `T.isSuffixOf` lmod -> do
            mloc <- getGameL10nIfPresent ("modifier_" <> lmod)
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    numericLoc loc' MsgModifierPcNegReduced stmt
                Nothing -> preStatement stmt
        | "modifier_army_sub_" `T.isPrefixOf` lmod ||
            ("operation_" `T.isPrefixOf` lmod && "_outcome" `T.isSuffixOf` lmod) -> do
            mloc <- getGameL10nIfPresent lmod
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    numericLoc loc' MsgModifierPcPosReduced stmt
                Nothing -> preStatement stmt
        | "operation_" `T.isPrefixOf` lmod && ("_risk" `T.isSuffixOf` lmod || "_cost" `T.isSuffixOf` lmod ) ||
            "_design_cost_factor" `T.isSuffixOf` lmod -> do
            mloc <- getGameL10nIfPresent lmod
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    numericLoc loc' MsgModifierPcNegReduced stmt
                Nothing -> preStatement stmt
        | ("state_resource_" `T.isPrefixOf` lmod && not ("state_resource_cost_" `T.isPrefixOf` lmod)) || --precision 0
            ("country_resource_" `T.isPrefixOf` lmod && not ("country_resource_cost_" `T.isPrefixOf` lmod)) || --precision 0
            "temporary_state_resource_" `T.isPrefixOf` lmod -> do --precision 0
            mloc <- getGameL10nIfPresent lmod
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    numericLoc loc' MsgModifierColourPos stmt
                Nothing -> preStatement stmt
        | "country_resource_cost_" `T.isPrefixOf` lmod -> do --precision 0
            mloc <- getGameL10nIfPresent lmod
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    numericLoc loc' MsgModifierColourNeg stmt
                Nothing -> preStatement stmt
        | "production_cost_max_" `T.isPrefixOf` lmod -> do --precision 0
            mloc <- getGameL10nIfPresent ("modifier_" <> lmod)
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    numericLoc loc' MsgModifierYellow stmt
                Nothing -> preStatement stmt
        | otherwise -> do
            moddef <- getModifierDefinitions
            case HM.lookup mod moddef of
                Just scrmsg -> do
                    mloc <- getGameL10nIfPresent mod
                    case mloc of
                        Just loc ->
                            let loc' = locprep hidden targ loc in
                            numericLoc loc' scrmsg stmt
                        Nothing -> preStatement stmt
                Nothing -> preStatement stmt
modifierMSG _ _ stmt@[pdx| custom_modifier_tooltip = $key|] = do
    loc <- getGameL10nIfPresent key
    maybe (preStatement stmt)
        (msgToPP . MsgCustomModifierTooltip)
        loc
modifierMSG hidden targ stmt@[pdx| $mod = $var|] =  let lmod = T.toLower mod in case HM.lookup lmod modifiersTable of
    Just (key, msg) -> do
        loc <- getGameL10n key
        let loc' = locprep hidden targ loc
        msgToPP $ MsgModifierVar loc' var
    Nothing
        | "cat_" `T.isPrefixOf` lmod -> do
            mloc <- getGameL10nIfPresent lmod
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    msgToPP $ MsgModifierVar loc' var
                Nothing -> preStatement stmt
        | ("production_speed_" `T.isPrefixOf` lmod && "_factor" `T.isSuffixOf` lmod) ||
            ("state_production_speed_" `T.isPrefixOf` lmod && "_factor" `T.isSuffixOf` lmod) ||
            ("unit_" `T.isPrefixOf` lmod && "_design_cost_factor" `T.isSuffixOf` lmod) ||
            ("experience_gain_" `T.isPrefixOf` lmod && "_combat_factor" `T.isSuffixOf` lmod) ||
            ("trait_" `T.isPrefixOf` lmod && "_xp_gain_factor" `T.isSuffixOf` lmod) ||
            ("repair_speed" `T.isPrefixOf` lmod && "_factor" `T.isSuffixOf` lmod) ||
            ("state_repair_speed" `T.isPrefixOf` lmod && "_factor" `T.isSuffixOf` lmod) -> do
            mloc <- getGameL10nIfPresent ("modifier_" <> lmod)
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    msgToPP $ MsgModifierVar loc' var
                Nothing -> preStatement stmt
        | "modifier_army_sub_" `T.isPrefixOf` lmod ||
            ("operation_" `T.isPrefixOf` lmod && "_outcome" `T.isSuffixOf` lmod) ||
            ("country_resource_" `T.isPrefixOf` lmod && not ("country_resource_cost_" `T.isPrefixOf` lmod)) ||
            "_design_cost_factor" `T.isSuffixOf` lmod ||
            "state_resource_" `T.isPrefixOf` lmod ||
            "country_resource_cost_" `T.isPrefixOf` lmod ||
            "temporary_state_resource_" `T.isPrefixOf` lmod -> do
            mloc <- getGameL10nIfPresent lmod
            case mloc of
                Just loc ->
                    let loc' = locprep hidden targ loc in
                    msgToPP $ MsgModifierVar loc' var
                Nothing -> preStatement stmt
        | otherwise -> do
            moddef <- getModifierDefinitions
            case HM.lookup mod moddef of
                Just scrmsg -> do
                    mloc <- getGameL10nIfPresent mod
                    case mloc of
                        Just loc ->
                            let loc' = locprep hidden targ loc in
                            msgToPP $ MsgModifierVar loc' var
                        Nothing -> preStatement stmt
                Nothing -> preStatement stmt
modifierMSG _ _ stmt = preStatement stmt

numericLocPost :: (IsGameState (GameState g), IsGameData (GameData g), Monad m) =>
    Text
        -> (Text -> Double -> Maybe Text -> ScriptMessage)
        -> StatementHandler g m
numericLocPost what msg [pdx| %_ = !amt |]
    = do whatloc <- getGameL10n what
         msgToPP $ msg whatloc amt Nothing
numericLocPost _ _  stmt = plainMsg $ preStatementText' stmt

locprep :: Bool -> Text -> Text -> Text
locprep hidden targ loc = do
    let loc' = if ": " `T.isSuffixOf` loc then T.dropEnd 2 loc else loc
        loctag = if T.null targ then loc' else "(" <> targ <> ")" <> loc'
    if hidden then "(Hidden)" <> loctag else loctag

handleResearchBonus :: forall g m. (HOI4Info g, Monad m) =>
        StatementHandler g m
handleResearchBonus [pdx| %_ = @scr |] = fold <$> traverse handleResearchBonus' scr
    where
        handleResearchBonus' stmt@[pdx| $tech = !num |] = let bonus = num :: Double in numericLoc (T.toLower tech <> "_research") MsgModifierPcPosReduced stmt
        handleResearchBonus' scr = preStatement scr
handleResearchBonus stmt = preStatement stmt

handleHiddenModifier :: forall g m. (HOI4Info g, Monad m) =>
        StatementHandler g m
handleHiddenModifier [pdx| %_ = @scr |] = do
    keys <- getModKeys
    sm <- sortmods scr keys
    fold <$> traverse (modifierMSG True "") sm
handleHiddenModifier stmt = preStatement stmt

handleTargetedModifier :: forall g m. (HOI4Info g, Monad m) =>
        StatementHandler g m
handleTargetedModifier stmt@[pdx| %_ = @scr |] = do
    let (tag, rest) = extractStmt (matchLhsText "tag") scr
    tagmsg <- case tag of
        Just [pdx| tag = $country |] -> flagText (Just HOI4Country) country
        _ -> return "CHECK SCRIPT"
    keys <- getModKeys
    sm <- sortmods rest keys
    fold <$> traverse (modifierTagMSG tagmsg) sm
        where
            modifierTagMSG = modifierMSG False
handleTargetedModifier stmt = preStatement stmt


handleEquipmentBonus :: forall g m. (HOI4Info g, Monad m) =>
        StatementHandler g m
handleEquipmentBonus stmt@[pdx| %_ = @scr |] = fold <$> traverse modifierEquipMSG scr
        where
            modifierEquipMSG [pdx| $tech = @scr |] = do
                let (_, rest) = extractStmt (matchLhsText "instant") scr
                techloc <- getGameL10n tech
                techmsg <- plainMsg' ("{{color|yellow|"<> techloc <> "}}:")
                modmsg <- do
                    keys <- getModKeys
                    sm <- sortmods rest keys
                    fold <$> indentUp (traverse modifierEquipMSG' sm)
                return $ techmsg : modmsg
            modifierEquipMSG stmt = preStatement stmt

            modifierEquipMSG' = modifierMSG False ""
handleEquipmentBonus stmt = preStatement stmt


-- | Handlers for numeric statements with icons
modifiersTable :: HashMap Text (Text, Text -> Double -> ScriptMessage)
modifiersTable = HM.fromList
        [
        --general modifiers
         ("monthly_population"              , ("MODIFIER_GLOBAL_MONTHLY_POPULATION", MsgModifierPcPosReduced))
        ,("nuclear_production_factor"       , ("MODIFIER_NUCLEAR_PRODUCTION_FACTOR", MsgModifierPcPosReduced))
        ,("research_sharing_per_country_bonus" , ("MODIFIER_RESEARCH_SHARING_PER_COUNTRY_BONUS", MsgModifierPcPosReduced))
        ,("research_sharing_per_country_bonus_factor" , ("MODIFIER_RESEARCH_SHARING_PER_COUNTRY_BONUS_FACTOR", MsgModifierPcPosReduced))
        ,("research_speed_factor"           , ("MODIFIER_RESEARCH_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("local_resources_factor"          , ("MODIFIER_LOCAL_RESOURCES_FACTOR", MsgModifierPcPosReduced))
        ,("surrender_limit"                 , ("MODIFIER_SURRENDER_LIMIT", MsgModifierPcPosReduced))
        ,("max_surrender_limit_offset"      , ("MODIFIER_MAX_SURRENDER_LIMIT_OFFSET", MsgModifierPcPosReduced)) --precision 2

            -- Politics modifiers
        ,("min_export"                      , ("MODIFIER_MIN_EXPORT_FACTOR", MsgModifierPcReducedSign)) -- yellow
        ,("trade_opinion_factor"            , ("MODIFIER_TRADE_OPINION_FACTOR", MsgModifierPcReducedSign))
        ,("economy_cost_factor"             , ("economy_cost_factor", MsgModifierPcNegReduced))
        ,("disabled_ideas"                  , ("MODIFIER_DISABLE_IDEA_TAKING", MsgModifierNoYes))
        ,("mobilization_laws_cost_factor"   , ("mobilization_laws_cost_factor", MsgModifierPcNegReduced))
        ,("political_advisor_cost_factor"   , ("political_advisor_cost_factor", MsgModifierPcNegReduced))
        ,("trade_laws_cost_factor"          , ("trade_laws_cost_factor", MsgModifierPcNegReduced))
        ,("tank_manufacturer_cost_factor"   , ("tank_manufacturer_cost_factor", MsgModifierPcNegReduced))
        ,("naval_manufacturer_cost_factor"  , ("naval_manufacturer_cost_factor", MsgModifierPcNegReduced))
        ,("aircraft_manufacturer_cost_factor" , ("aircraft_manufacturer_cost_factor", MsgModifierPcNegReduced))
        ,("materiel_manufacturer_cost_factor" , ("materiel_manufacturer_cost_factor", MsgModifierPcNegReduced))
        ,("industrial_concern_cost_factor"  , ("industrial_concern_cost_factor", MsgModifierPcNegReduced))
        ,("theorist_cost_factor"            , ("theorist_cost_factor", MsgModifierPcNegReduced))
        ,("army_chief_cost_factor"          , ("army_chief_cost_factor", MsgModifierPcNegReduced))
        ,("navy_chief_cost_factor"          , ("navy_chief_cost_factor", MsgModifierPcNegReduced))
        ,("air_chief_cost_factor"           , ("air_chief_cost_factor", MsgModifierPcNegReduced))
        ,("high_command_cost_factor"        , ("high_command_cost_factor", MsgModifierPcNegReduced))
        ,("air_advisor_cost_factor"         , ("MODIFIER_AIR_ADVISOR_COST_FACTOR", MsgModifierPcNegReduced))
        ,("army_advisor_cost_factor"        , ("MODIFIER_ARMY_ADVISOR_COST_FACTOR", MsgModifierPcNegReduced))
        ,("navy_advisor_cost_factor"        , ("MODIFIER_NAVY_ADVISOR_COST_FACTOR", MsgModifierPcNegReduced))
        ,("offensive_war_stability_factor"  , ("MODIFIER_STABILITY_OFFENSIVE_WAR_FACTOR", MsgModifierPcPosReduced))
        ,("defensive_war_stability_factor"  , ("MODIFIER_STABILITY_DEFENSIVE_WAR_FACTOR", MsgModifierPcPosReduced))
        ,("unit_leader_as_advisor_cp_cost_factor" , ("MODIFIER_UNIT_LEADER_AS_ADVISOR_CP_COST_FACTOR", MsgModifierPcNegReduced)) --precision 1
        ,("improve_relations_maintain_cost_factor" , ("MODIFIER_IMPROVE_RELATIONS_MAINTAIN_COST_FACTOR", MsgModifierPcNegReduced))
        ,("party_popularity_stability_factor" , ("MODIFIER_STABILITY_POPULARITY_FACTOR", MsgModifierPcPosReduced))
        ,("political_power_cost"            , ("MODIFIER_POLITICAL_POWER_COST", MsgModifierColourNeg))
        ,("political_power_gain"            , ("MODIFIER_POLITICAL_POWER_GAIN", MsgModifierColourPos)) --precision 2
        ,("political_power_factor"          , ("MODIFIER_POLITICAL_POWER_FACTOR", MsgModifierPcPosReduced))
        ,("stability_factor"                , ("MODIFIER_STABILITY_FACTOR", MsgModifierPcPosReduced)) --precision 2
        ,("stability_weekly"                , ("MODIFIER_STABILITY_WEEKLY", MsgModifierPcPosReduced))
        ,("stability_weekly_factor"         , ("MODIFIER_STABILITY_WEEKLY_FACTOR", MsgModifierPcPosReduced))
        ,("war_stability_factor"            , ("MODIFIER_STABILITY_WAR_FACTOR", MsgModifierPcPosReduced))
        ,("war_support_factor"              , ("MODIFIER_WAR_SUPPORT_FACTOR", MsgModifierPcPosReduced))
        ,("war_support_weekly"              , ("MODIFIER_WAR_SUPPORT_WEEKLY", MsgModifierPcPosReduced))
        ,("war_support_weekly_factor"       , ("MODIFIER_WAR_SUPPORT_WEEKLY_FACTOR", MsgModifierPcPosReduced))
        ,("weekly_casualties_war_support"   , ("MODIFIER_WEEKLY_CASUALTIES_WAR_SUPPORT", MsgModifierPcPosReduced))
        ,("weekly_convoys_war_support"      , ("MODIFIER_WEEKLY_CONVOYS_WAR_SUPPORT", MsgModifierPcPosReduced))
        ,("weekly_bombing_war_support"      , ("MODIFIER_WEEKLY_BOMBING_WAR_SUPPORT", MsgModifierPcPosReduced))
        ,("drift_defence_factor"            , ("MODIFIER_DRIFT_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("power_balance_daily"             , ("MODIFIER_POWER_BALANCE_DAILY", MsgModifierBop))
        ,("power_balance_weekly"            , ("MODIFIER_POWER_BALANCE_WEEKLY", MsgModifierBop))
        ,("communism_drift"                 , ("communism_drift", MsgModifierColourPos)) --precision 2
        ,("democratic_drift"                , ("democratic_drift", MsgModifierColourPos)) --precision 2
        ,("fascism_drift"                   , ("fascism_drift", MsgModifierColourPos)) --precision 2
        ,("neutrality_drift"                , ("neutrality_drift", MsgModifierColourPos)) --precision 2
        ,("communism_acceptance"            , ("communism_acceptance", MsgModifierColourPos))
        ,("democratic_acceptance"           , ("democratic_acceptance", MsgModifierColourPos))
        ,("fascism_acceptance"              , ("fascism_acceptance", MsgModifierColourPos))
        ,("neutrality_acceptance"           , ("neutrality_acceptance", MsgModifierColourPos))

            -- Diplomacy
        ,("civil_war_involvement_tension"   , ("MODIFIER_CIVIL_WAR_INVOLVEMENT_TENSION", MsgModifierPcNegReduced)) -- precision 1
        ,("enemy_declare_war_tension"       , ("MODIFIER_ENEMY_DECLARE_WAR_TENSION", MsgModifierPcPosReduced))
        ,("enemy_justify_war_goal_time"     , ("MODIFIER_ENEMY_JUSTIFY_WAR_GOAL_TIME", MsgModifierPcPosReduced))
        ,("faction_trade_opinion_factor"    , ("MODIFIER_FACTION_TRADE_OPINION_FACTOR", MsgModifierPcReducedSign)) --precision 2 yellow
        ,("generate_wargoal_tension"        , ("MODIFIER_GENERATE_WARGOAL_TENSION_LIMIT", MsgModifierPcReducedSign)) -- yellow
        ,("guarantee_cost"                  , ("MODIFIER_GUARANTEE_COST", MsgModifierPcNegReduced))
        ,("guarantee_tension"               , ("MODIFIER_GUARANTEE_TENSION_LIMIT", MsgModifierPcNegReduced))
        ,("join_faction_tension"            , ("MODIFIER_JOIN_FACTION_TENSION_LIMIT", MsgModifierPcNegReduced))
        ,("justify_war_goal_time"           , ("MODIFIER_JUSTIFY_WAR_GOAL_TIME", MsgModifierPcNegReduced))
        ,("justify_war_goal_when_in_major_war_time" , ("MODIFIER_JUSTIFY_WAR_GOAL_WHEN_IN_MAJOR_WAR_TIME", MsgModifierPcNegReduced))
        ,("lend_lease_tension"              , ("MODIFIER_LEND_LEASE_TENSION_LIMIT", MsgModifierPcNegReduced))
        ,("opinion_gain_monthly"            , ("MODIFIER_OPINION_GAIN_MONTHLY", MsgModifierColourPos))
        ,("opinion_gain_monthly_factor"     , ("MODIFIER_OPINION_GAIN_MONTHLY_FACTOR", MsgModifierPcPosReduced))
        ,("opinion_gain_monthly_same_ideology_factor" , ("MODIFIER_OPINION_GAIN_MONTHLY_SAME_IDEOLOGY_FACTOR", MsgModifierPcPosReduced))
        ,("request_lease_tension"           , ("MODIFIER_REQUEST_LEASE_TENSION_LIMIT", MsgModifierPcNegReduced))
        ,("annex_cost_factor"               , ("MODIFIER_ANNEX_COST_FACTOR", MsgModifierPcNegReduced))
        ,("puppet_cost_factor"              , ("MODIFIER_PUPPET_COST_FACTOR", MsgModifierPcNegReduced))
        ,("send_volunteer_divisions_required" , ("MODIFIER_SEND_VOLUNTEER_DIVISIONS_REQUIRED", MsgModifierPcNegReduced))
        ,("send_volunteer_factor"           , ("MODIFIER_SEND_VOLUNTEER_FACTOR", MsgModifierPcPosReduced))
        ,("send_volunteer_size"             , ("MODIFIER_SEND_VOLUNTEER_SIZE", MsgModifierColourPos))
        ,("send_volunteers_tension"         , ("MODIFIER_SEND_VOLUNTEERS_TENSION_LIMIT", MsgModifierPcNegReduced))
        ,("air_volunteer_cap"               , ("MODIFIER_AIR_VOLUNTEER_CAP", MsgModifierColourPos))
        ,("embargo_threshold_factor"        , ("MODIFIER_EMBARGO_THRESHOLD_FACTOR", MsgModifierPcNegReduced))
        ,("embargo_cost_factor"             , ("MODIFIER_EMBARGO_COST_FACTOR", MsgModifierPcNegReduced))

            -- autonomy
        ,("autonomy_gain"                   , ("MODIFIER_AUTONOMY_GAIN", MsgModifierColourPos))
        ,("autonomy_gain_global_factor"     , ("MODIFIER_AUTONOMY_GAIN_GLOBAL_FACTOR", MsgModifierPcPosReduced))
        ,("subjects_autonomy_gain"          , ("MODIFIER_AUTONOMY_SUBJECT_GAIN", MsgModifierColourPos))
        ,("autonomy_gain_trade_factor"      , ("MODIFIER_AUTONOMY_GAIN_TRADE_FACTOR", MsgModifierPcPosReduced))
        ,("autonomy_manpower_share"         , ("MODIFIER_AUTONOMY_MANPOWER_SHARE", MsgModifierPcReducedSign))
        ,("can_master_build_for_us"         , ("MODIFIER_CAN_MASTER_BUILD_FOR_US", MsgModifierNoYes))
        ,("cic_to_overlord_factor"          , ("MODIFIER_CIC_TO_OVERLORD_FACTOR", MsgModifierPcPosReduced))
        ,("mic_to_overlord_factor"          , ("MODIFIER_MIC_TO_OVERLORD_FACTOR", MsgModifierPcPosReduced))
        ,("extra_trade_to_overlord_factor"  , ("MODIFIER_TRADE_TO_OVERLORD_FACTOR", MsgModifierPcPosReduced))
        ,("master_ideology_drift"           , ("MODIFIER_MASTER_IDEOLOGY_DRIFT", MsgModifierColourPos))
        ,("overlord_trade_cost_factor"      , ("MODIFIER_TRADE_COST_FACTOR", MsgModifierPcNegReduced))

            -- Governments in exile
        ,("dockyard_donations"              , ("MODIFIER_DOCKYARD_DONATIONS", MsgModifierColourPos))
        ,("industrial_factory_donations"    , ("MODIFIER_INDUSTRIAL_FACTORY_DONATIONS", MsgModifierColourPos))
        ,("military_factory_donations"      , ("MODIFIER_MILITARY_FACTORY_DONATIONS", MsgModifierColourPos))
        ,("exile_manpower_factor"           , ("MODIFIER_EXILED_MAPOWER_GAIN_FACTOR", MsgModifierPcPosReduced))
        ,("exiled_government_weekly_manpower" , ("MODIFIER_EXILED_GOVERNMENT_WEEKLY_MANPOWER", MsgModifierColourPos))
        ,("legitimacy_daily"                , ("MODIFIER_LEGITIMACY_DAILY", MsgModifierColourPos))
        ,("legitimacy_gain_factor"          , ("MODIFIER_LEGITIMACY_FACTOR", MsgModifierPcPosReduced))

            -- Equipment
        ,("equipment_capture"               , ("MODIFIER_EQUIPMENT_CAPTURE", MsgModifierPcPosReduced))
        ,("equipment_capture_factor"        , ("MODIFIER_EQUIPMENT_CAPTURE_FACTOR", MsgModifierPcPosReduced))
        ,("equipment_conversion_speed"      , ("EQUIPMENT_CONVERSION_SPEED_MODIFIERS", MsgModifierPcPosReduced))
        ,("equipment_upgrade_xp_cost"       , ("MODIFIER_EQUIPMENT_UPGRADE_XP_COST", MsgModifierPcNegReduced))
        ,("license_purchase_cost"           , ("MODIFIER_LICENSE_PURCHASE_COST", MsgModifierPcNegReduced))
        ,("license_tech_difference_speed"   , ("MODIFIER_LICENSE_TECH_DIFFERENCE_SPEED", MsgModifierPcPosReduced))
        ,("license_production_speed"        , ("MODIFIER_LICENSE_PRODUCTION_SPEED", MsgModifierPcPosReduced))
        ,("license_armor_purchase_cost"     , ("MODIFIER_LICENSE_ARMOR_PURCHASE_COST", MsgModifierPcNegReduced))
        ,("license_air_purchase_cost"       , ("MODIFIER_LICENSE_AIR_PURCHASE_COST", MsgModifierPcNegReduced))
        ,("license_naval_purchase_cost"     , ("MODIFIER_LICENSE_NAVAL_PURCHASE_COST", MsgModifierPcNegReduced))
        ,("production_factory_efficiency_gain_factor" , ("MODIFIER_PRODUCTION_FACTORY_EFFICIENCY_GAIN_FACTOR", MsgModifierPcPosReduced))
        ,("production_factory_max_efficiency_factor" , ("MODIFIER_PRODUCTION_FACTORY_MAX_EFFICIENCY_FACTOR", MsgModifierPcPosReduced))
        ,("production_factory_start_efficiency_factor" , ("MODIFIER_PRODUCTION_FACTORY_START_EFFICIENCY_FACTOR", MsgModifierPcPosReduced))
        ,("production_lack_of_resource_penalty_factor" , ("MODIFIER_PRODUCTION_LACK_OF_RESOURCE_PENALTY_FACTOR", MsgModifierPcNegReduced))
        ,("refit_speed"                     , ("MODIFIER_INDUSTRIAL_REFIT_SPEED_FACTOR", MsgModifierPcPosReduced))

            -- Military outside of combat
        ,("command_power_gain"              , ("MODIFIER_COMMAND_POWER_GAIN", MsgModifierColourPos))
        ,("command_power_gain_mult"         , ("MODIFIER_COMMAND_POWER_GAIN_MULT", MsgModifierPcPosReduced))
        ,("conscription"                    , ("MODIFIER_CONSCRIPTION_FACTOR", MsgModifierPcReducedSignMin)) --yellow
        ,("conscription_factor"             , ("MODIFIER_CONSCRIPTION_TOTAL_FACTOR", MsgModifierPcPosReduced))
        ,("dig_in_speed_factor"             , ("MODIFIER_DIG_IN_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("experience_gain_air"             , ("MODIFIER_XP_GAIN_AIR", MsgModifierColourPos))
        ,("experience_gain_air_factor"      , ("MODIFIER_XP_GAIN_AIR_FACTOR", MsgModifierPcPosReduced))
        ,("experience_gain_army"            , ("MODIFIER_XP_GAIN_ARMY", MsgModifierColourPos))
        ,("experience_gain_army_factor"     , ("MODIFIER_XP_GAIN_ARMY_FACTOR", MsgModifierPcPosReduced))
        ,("experience_gain_navy"            , ("MODIFIER_XP_GAIN_NAVY", MsgModifierColourPos))
        ,("experience_gain_navy_factor"     , ("MODIFIER_XP_GAIN_NAVY_FACTOR", MsgModifierPcPosReduced))
        ,("land_equipment_upgrade_xp_cost"  , ("MODIFIER_LAND_EQUIPMENT_UPGRADE_XP_COST", MsgModifierPcNegReduced)) --precision 0
        ,("land_reinforce_rate"             , ("MODIFIER_LAND_REINFORCE_RATE", MsgModifierPcPosReduced))
        ,("training_time_factor"            , ("MODIFIER_TRAINING_TIME_FACTOR", MsgModifierPcNegReduced))
        ,("minimum_training_level"          , ("MODIFIER_MINIMUM_TRAINING_LEVEL", MsgModifierPcNegReduced))
        ,("air_doctrine_cost_factor"        , ("MODIFIER_AIR_DOCTRINE_COST_FACTOR", MsgModifierPcNegReduced))
        ,("land_doctrine_cost_factor"       , ("MODIFIER_LAND_DOCTRINE_COST_FACTOR", MsgModifierPcNegReduced))
        ,("naval_doctrine_cost_factor"      , ("MODIFIER_NAVAL_DOCTRINE_COST_FACTOR", MsgModifierPcNegReduced))
        ,("max_command_power"               , ("MODIFIER_MAX_COMMAND_POWER", MsgModifierColourPos))
        ,("max_command_power_mult"          , ("MODIFIER_MAX_COMMAND_POWER_MULT", MsgModifierPcPosReduced))
        ,("training_time_army_factor"       , ("MODIFIER_TRAINING_TIME_ARMY_FACTOR", MsgModifierPcReducedSign)) --yellow
        ,("weekly_manpower"                 , ("MODIFIER_WEEKLY_MANPOWER", MsgModifierColourPos))
        ,("refit_ic_cost"                   , ("MODIFIER_INDUSTRIAL_REFIT_IC_COST_FACTOR", MsgModifierPcNegReduced)) --precision 0
        ,("air_equipment_upgrade_xp_cost"   , ("MODIFIER_AIR_EQUIPMENT_UPGRADE_XP_COST", MsgModifierPcNegReduced)) --precision 0
        ,("special_forces_training_time_factor", ("MODIFIER_SPECIAL_FORCES_TRAINING_TIME_FACTOR", MsgModifierPcNegReduced))
        ,("command_abilities_cost_factor"   , ("MODIFIER_COMMAND_ABILITIES_COST_FACTOR", MsgModifierPcNegReduced))
        ,("special_forces_cap_flat"         ,("MODIFIER_SPECIAL_FORCES_CAP_FLAT", MsgModifierColourPos))

            -- Fuel and supplies
        ,("base_fuel_gain"                  , ("MODIFIER_BASE_FUEL_GAIN_ADD", MsgModifierColourPos))
        ,("base_fuel_gain_factor"           , ("MODIFIER_BASE_FUEL_GAIN_FACTOR", MsgModifierPcPosReduced))
        ,("fuel_cost"                       , ("MODIFIER_FUEL_COST", MsgModifierColourNeg))
        ,("fuel_gain"                       , ("MODIFIER_FUEL_GAIN_ADD", MsgModifierColourPos))
        ,("fuel_gain_factor"                , ("MODIFIER_MAX_FUEL_FACTOR", MsgModifierPcPosReduced))
        ,("fuel_gain_factor_from_states"    , ("MODIFIER_FUEL_GAIN_FACTOR_FROM_STATES", MsgModifierPcPosReduced))
        ,("max_fuel"                        , ("MODIFIER_MAX_FUEL_ADD", MsgModifierColourPos))
        ,("max_fuel_factor"                 , ("MODIFIER_MAX_FUEL_FACTOR", MsgModifierPcPosReduced))
        ,("army_fuel_consumption_factor"    , ("MODIFIER_ARMY_FUEL_CONSUMPTION_FACTOR", MsgModifierPcNegReduced))
        ,("air_fuel_consumption_factor"     , ("MODIFIER_AIR_FUEL_CONSUMPTION_FACTOR", MsgModifierPcNegReduced))
        ,("navy_fuel_consumption_factor"    , ("MODIFIER_NAVY_FUEL_CONSUMPTION_FACTOR", MsgModifierPcNegReduced))
        ,("supply_factor"                   , ("MODIFIER_SUPPLY_FACTOR", MsgModifierPcPosReduced)) --precision 0
        ,("supply_combat_penalties_on_core_factor" , ("supply_combat_penalties_on_core_factor", MsgModifierPcNegReduced))
        ,("supply_consumption_factor"       , ("MODIFIER_SUPPLY_CONSUMPTION_FACTOR", MsgModifierPcNegReduced))
        ,("no_supply_grace"                 , ("MODIFIER_NO_SUPPLY_GRACE", MsgModifierColourPos))
        ,("out_of_supply_factor"            , ("MODIFIER_OUT_OF_SUPPLY_FACTOR", MsgModifierPcNegReduced))
        ,("attrition"                       , ("MODIFIER_ATTRITION", MsgModifierPcNegReduced))
        ,("naval_attrition"                 , ("MODIFIER_NAVAL_ATTRITION_FACTOR", MsgModifierPcNegReduced))
        ,("heat_attrition"                  , ("MODIFIER_HEAT_ATTRITION", MsgModifierPcNegReduced))
        ,("heat_attrition_factor"           , ("MODIFIER_HEAT_ATTRITION_FACTOR", MsgModifierPcNegReduced))
        ,("winter_attrition_factor"         , ("MODIFIER_WINTER_ATTRITION_FACTOR", MsgModifierPcNegReduced))
        ,("extra_marine_supply_grace"       , ("MODIFIER_MARINE_EXTRA_SUPPLY_GRACE", MsgModifierColourPos))
        ,("extra_paratrooper_supply_grace"  , ("MODIFIER_PARATROOPER_EXTRA_SUPPLY_GRACE", MsgModifierColourPos))
        ,("special_forces_no_supply_grace"  , ("MODIFIER_SPECIAL_FORCES_NO_SUPPLY_GRACE", MsgModifierColourPos))
        ,("special_forces_out_of_supply_factor" , ("MODIFIER_SPECIAL_FORCES_OUT_OF_SUPPLY_FACTOR", MsgModifierPcNegReduced))

            -- buildings
        ,("civilian_factory_use"            , ("MODIFIER_CIVILIAN_FACTORY_USE", MsgModifierColourNeg))
        ,("industry_free_repair_factor"     , ("MODIFIER_INDUSTRY_FREE_REPAIR_FACTOR", MsgModifierPcPosReduced))
        ,("consumer_goods_factor"           , ("MODIFIER_CONSUMER_GOODS_FACTOR", MsgModifierPcReducedSignMin))
        ,("conversion_cost_civ_to_mil_factor" , ("MODIFIER_CONVERSION_COST_CIV_TO_MIL_FACTOR", MsgModifierPcNegReduced))
        ,("conversion_cost_mil_to_civ_factor" , ("MODIFIER_CONVERSION_COST_MIL_TO_CIV_FACTOR", MsgModifierPcNegReduced))
        ,("global_building_slots"           , ("MODIFIER_GLOBAL_BUILDING_SLOTS", MsgModifierPcPosReduced))
        ,("global_building_slots_factor"    , ("MODIFIER_GLOBAL_BUILDING_SLOTS_FACTOR", MsgModifierPcPosReduced))
        ,("industrial_capacity_dockyard"    , ("MODIFIER_INDUSTRIAL_CAPACITY_DOCKYARD_FACTOR", MsgModifierPcPosReduced))
        ,("industrial_capacity_factory"     , ("MODIFIER_INDUSTRIAL_CAPACITY_FACTOR", MsgModifierPcPosReduced))
        ,("industry_air_damage_factor"      , ("MODIFIER_INDUSTRY_AIR_DAMAGE_FACTOR", MsgModifierPcNegReduced)) --precision 2
        ,("industry_repair_factor"          , ("MODIFIER_INDUSTRY_REPAIR_FACTOR", MsgModifierPcPosReduced))
        ,("line_change_production_efficiency_factor" , ("MODIFIER_LINE_CHANGE_PRODUCTION_EFFICIENCY_FACTOR", MsgModifierPcPosReduced))
        ,("production_oil_factor"           , ("MODIFIER_PRODUCTION_OIL_FACTOR", MsgModifierPcPosReduced))
        ,("production_speed_buildings_factor" , ("MODIFIER_PRODUCTION_SPEED_BUILDINGS_FACTOR", MsgModifierPcPosReduced))
        ,("supply_node_range"               , ("MODIFIER_SUPPLY_NODE_RANGE", MsgModifierPcPosReduced))
        ,("static_anti_air_damage_factor"   , ("MODIFIER_STATIC_ANTI_AIR_DAMAGE_FACTOR", MsgModifierPcPosReduced))
        ,("static_anti_air_hit_chance_factor" , ("MODIFIER_STATIC_ANTI_AIR_HIT_CHANCE_FACTOR", MsgModifierPcPosReduced))

            -- resistance and compliance
        ,("compliance_growth_on_our_occupied_states" , ("MODIFIER_COMPLIANCE_GROWTH_ON_OUR_OCCUPIED_STATES", MsgModifierPcNegReduced))
        ,("no_compliance_gain"              , ("MODIFIER_NO_COMPLIANCE_GAIN", MsgModifierNoYes))
        ,("occupation_cost"                 , ("MODIFIER_OCCUPATION_COST", MsgModifierColourNeg))
        ,("required_garrison_factor"        , ("MODIFIER_REQUIRED_GARRISON_FACTOR", MsgModifierPcNegReduced))
        ,("resistance_activity"             , ("MODIFIER_RESISTANCE_ACTIVITY_FACTOR", MsgModifierPcNegReduced))
        ,("resistance_damage_to_garrison_on_our_occupied_states" , ("MODIFIER_RESISTANCE_DAMAGE_TO_GARRISONS_ON_OUR_OCCUPIED_STATES", MsgModifierPcPosReduced))
        ,("resistance_decay_on_our_occupied_states" , ("MODIFIER_RESISTANCE_DECAY_ON_OUR_OCCUPIED_STATES", MsgModifierPcNegReduced))
        ,("resistance_growth_on_our_occupied_states" , ("MODIFIER_RESISTANCE_GROWTH_ON_OUR_OCCUPIED_STATES", MsgModifierPcPosReduced))
        ,("resistance_target_on_our_occupied_states" , ("MODIFIER_RESISTANCE_TARGET_ON_OUR_OCCUPIED_STATES", MsgModifierPcPosReduced))

            -- Intelligence
        ,("agency_upgrade_time"             , ("MODIFIER_AGENCY_UPGRADE_TIME", MsgModifierPcNegReduced))
        ,("decryption"                      , ("MODIFIER_DECRYPTION", MsgModifierColourPos))
        ,("decryption_factor"               , ("MODIFIER_DECRYPTION_FACTOR", MsgModifierPcPosReduced))
        ,("encryption"                      , ("MODIFIER_ENCRYPTION", MsgModifierColourPos))
        ,("encryption_factor"               , ("MODIFIER_ENCRYPTION_FACTOR", MsgModifierPcPosReduced))
        ,("civilian_intel_factor"           , ("MODIFIER_CIVILIAN_INTEL_FACTOR", MsgModifierPcPosReduced))
        ,("army_intel_factor"               , ("MODIFIER_ARMY_INTEL_FACTOR", MsgModifierPcPosReduced))
        ,("navy_intel_factor"               , ("MODIFIER_NAVY_INTEL_FACTOR", MsgModifierPcPosReduced))
        ,("airforce_intel_factor"           , ("MODIFIER_AIRFORCE_INTEL_FACTOR", MsgModifierPcPosReduced))
        ,("civilian_intel_to_others"        , ("MODIFIER_CIVILIAN_INTEL_TO_OTHERS", MsgModifierPcNeg))
        ,("army_intel_to_others"            , ("MODIFIER_ARMY_INTEL_TO_OTHERS", MsgModifierPcNeg))
        ,("navy_intel_to_others"            , ("MODIFIER_NAVY_INTEL_TO_OTHERS", MsgModifierPcNeg))
        ,("airforce_intel_to_others"        , ("MODIFIER_AIRFORCE_INTEL_TO_OTHERS", MsgModifierPcNeg))
        ,("intel_network_gain"              , ("MODIFIER_INTEL_NETWORK_GAIN", MsgModifierColourPos))
        ,("intel_network_gain_factor"       , ("MODIFIER_INTEL_NETWORK_GAIN_FACTOR", MsgModifierPcPosReduced))
        ,("subversive_activites_upkeep"     , ("MODIFIER_SUBVERSIVE_ACTIVITES_UPKEEP", MsgModifierPcNegReduced))
        ,("target_sabotage_risk"            , ("target_sabotage_risk", MsgModifierPcNegReduced))
        ,("target_sabotage_cost"            , ("target_sabotage_cost", MsgModifierPcNegReduced))
        ,("diplomatic_pressure_mission_factor" , ("MODIFIER_DIPLOMATIC_PRESSURE_MISSION_FACTOR", MsgModifierPcPosReduced))
        ,("control_trade_mission_factor"    , ("MODIFIER_CONTROL_TRADE_MISSION_FACTOR", MsgModifierPcPosReduced))
        ,("boost_ideology_mission_factor"   , ("MODIFIER_BOOST_IDEOLOGY_MISSION_FACTOR", MsgModifierPcPosReduced))
        ,("boost_resistance_factor"         , ("MODIFIER_BOOST_RESISTANCE_FACTOR", MsgModifierPcPosReduced))
        ,("propaganda_mission_factor"       , ("MODIFIER_PROPAGANDA_MISSION_FACTOR", MsgModifierPcPosReduced))
        ,("target_sabotage_factor"          , ("MODIFIER_TARGET_SABOTAGE_FACTOR", MsgModifierPcPosReduced))
        ,("crypto_strength"                 , ("MODIFIER_CRYPTO_STRENGTH", MsgModifierColourPos))
        ,("decryption_power"                , ("MODIFIER_DECRYPTION_POWER", MsgModifierColourPos))
        ,("decryption_power_factor"         , ("MODIFIER_DECRYPTION_POWER_FACTOR", MsgModifierPcPosReduced))
        ,("intel_from_combat_factor"        , ("MODIFIER_INTEL_FROM_COMBAT_FACTOR", MsgModifierPcPosReduced))
        ,("intel_from_operatives_factor"    , ("MODIFIER_INTEL_FROM_OPERATIVES_FACTOR", MsgModifierPcPosReduced))
        ,("civilian_intel_to_others"        , ("MODIFIER_CIVILIAN_INTEL_TO_OTHERS", MsgModifierPcNeg))
        ,("foreign_subversive_activites"    , ("MODIFIER_FOREIGN_SUBVERSIVE_ACTIVITIES", MsgModifierPcNegReduced))
        ,("intelligence_agency_defense"     , ("MODIFIER_INTELLIGENCE_AGENCY_DEFENSE", MsgModifierColourPos))
        ,("root_out_resistance_effectiveness_factor", ("MODIFIER_ROOT_OUT_RESISTANCE_EFFECTIVENESS_FACTOR", MsgModifierPcPosReduced))

            -- Operatives
        ,("own_operative_detection_chance_factor" , ("MODIFIER_OWN_OPERATIVE_DETECTION_CHANCE_FACTOR", MsgModifierPcNegReduced))
        ,("enemy_operative_capture_chance_factor" , ("MODIFIER_ENEMY_OPERATIVE_CAPTURE_CHANCE_FACTOR", MsgModifierPcNegReduced))
        ,("enemy_operative_detection_chance" , ("MODIFIER_ENEMY_OPERATIVE_DETECTION_CHANCE", MsgModifierPcPos))
        ,("enemy_operative_detection_chance_factor" , ("MODIFIER_ENEMY_OPERATIVE_DETECTION_CHANCE_FACTOR", MsgModifierPcPosReduced))
        ,("enemy_operative_intel_extraction_rate" , ("MODIFIER_ENEMY_OPERATIVE_INTEL_EXTRACTION_RATE", MsgModifierPcNegReduced))
        ,("new_operative_slot_bonus"        , ("MODIFIER_NEW_OPERATIVE_SLOT_BONUS", MsgModifierColourPos))
        ,("operative_slot"                  , ("MODIFIER_OPERATIVE_SLOT", MsgModifierColourPos))

            -- AI
        ,("ai_badass_factor"                , ("MODIFIER_AI_BADASS_FACTOR", MsgModifierPcReducedSign))
        ,("ai_call_ally_desire_factor"      , ("MODIFIER_AI_GET_ALLY_DESIRE_FACTOR", MsgModifierSign))
        ,("ai_desired_divisions_factor"     , ("MODIFIER_AI_DESIRED_DIVISIONS_FACTOR", MsgModifierPcReducedSign))
        ,("ai_focus_aggressive_factor"      , ("MODIFIER_AI_FOCUS_AGGRESSIVE_FACTOR", MsgModifierPcReducedSign))
        ,("ai_focus_defense_factor"         , ("MODIFIER_AI_FOCUS_DEFENSE_FACTOR", MsgModifierPcReducedSign)) --precision 1
        ,("ai_focus_aviation_factor"        , ("MODIFIER_AI_FOCUS_AVIATION_FACTOR", MsgModifierPcReducedSign))
        ,("ai_focus_military_advancements_factor" , ("MODIFIER_AI_FOCUS_MILITARY_ADVANCEMENTS_FACTOR", MsgModifierPcReducedSign))
        ,("ai_focus_military_equipment_factor" , ("MODIFIER_AI_FOCUS_MILITARY_EQUIPMENT_FACTOR", MsgModifierPcReducedSign))
        ,("ai_focus_naval_air_factor"       , ("MODIFIER_AI_FOCUS_NAVAL_AIR_FACTOR", MsgModifierPcReducedSign))
        ,("ai_focus_naval_factor"           , ("MODIFIER_AI_FOCUS_NAVAL_FACTOR", MsgModifierPcReducedSign))
        ,("ai_focus_war_production_factor"  , ("MODIFIER_AI_FOCUS_WAR_PRODUCTION_FACTOR", MsgModifierPcReducedSign))
        ,("ai_focus_peaceful_factor"        , ("MODIFIER_AI_FOCUS_PEACEFUL_FACTOR", MsgModifierPcReducedSign)) --precision 1
        ,("ai_get_ally_desire_factor"       , ("MODIFIER_AI_GET_ALLY_DESIRE_FACTOR", MsgModifierSign))
        ,("ai_join_ally_desire_factor"      , ("MODIFIER_AI_JOIN_ALLY_DESIRE_FACTOR", MsgModifierSign))
        ,("ai_license_acceptance"           , ("MODIFIER_AI_LICENSE_ACCEPTANCE", MsgModifierSign))

            -- Unit Leaders
        ,("female_random_army_leader_chance", ("MODIFIER_FEMALE_ARMY_LEADER_CHANCE", MsgModifierPcReducedSign))
        ,("army_leader_cost_factor"         , ("MODIFIER_ARMY_LEADER_COST_FACTOR", MsgModifierPcNegReduced))
        ,("army_leader_start_level"         , ("MODIFIER_ARMY_LEADER_START_LEVEL", MsgModifierColourPos))
        ,("army_leader_start_attack_level"  , ("MODIFIER_ARMY_LEADER_START_ATTACK_LEVEL", MsgModifierColourPos))
        ,("army_leader_start_defense_level" , ("MODIFIER_ARMY_LEADER_START_DEFENSE_LEVEL", MsgModifierColourPos))
        ,("army_leader_start_logistics_level" , ("MODIFIER_ARMY_LEADER_START_LOGISTICS_LEVEL", MsgModifierColourPos))
        ,("army_leader_start_planning_level" , ("MODIFIER_ARMY_LEADER_START_PLANNING_LEVEL", MsgModifierColourPos))
        ,("military_leader_cost_factor"     , ("MODIFIER_MILITARY_LEADER_COST_FACTOR", MsgModifierPcNegReduced))
        ,("navy_leader_start_attack_level"  , ("MODIFIER_NAVY_LEADER_START_ATTACK_LEVEL", MsgModifierColourPos)) --precision 0
        ,("female_divisional_commander_chance", ("MODIFIER_FEMALE_DIVISIONAL_COMMANDER_CHANCE", MsgModifierPcReducedSign))

            -- General Combat
        ,("offence"                         , ("MODIFIER_OFFENCE", MsgModifierPcPosReduced))
        ,("defence"                         , ("MODIFIER_DEFENCE", MsgModifierPcPosReduced))

            -- Land Combat
        ,("acclimatization_cold_climate_gain_factor", ("MODIFIER_ACCLIMATIZATION_COLD_CLIMATE_GAIN_FACTOR", MsgModifierPcPosReduced))
        ,("acclimatization_hot_climate_gain_factor", ("MODIFIER_ACCLIMATIZATION_HOT_CLIMATE_GAIN_FACTOR", MsgModifierPcPosReduced))
        ,("air_superiority_bonus_in_combat" , ("MODIFIER_AIR_SUPERIORITY_BONUS_IN_COMBAT", MsgModifierPcPosReduced))
        ,("army_attack_factor"              , ("MODIFIERS_ARMY_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("army_core_attack_factor"         , ("MODIFIERS_ARMY_CORE_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("army_attack_against_major_factor", ("MODIFIERS_ARMY_ATTACK_AGAINST_MAJOR_FACTOR", MsgModifierPcPosReduced))
        ,("army_attack_against_minor_factor", ("MODIFIERS_ARMY_ATTACK_AGAINST_MINOR_FACTOR", MsgModifierPcPosReduced))
        ,("army_attack_speed_factor"        , ("MODIFIER_ARMY_ATTACK_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("army_breakthrough_against_major_factor", ("MODIFIERS_ARMY_BREAKTHROUGH_AGAINST_MAJOR_FACTOR", MsgModifierPcPosReduced))
        ,("army_breakthrough_against_minor_factor", ("MODIFIERS_ARMY_BREAKTHROUGH_AGAINST_MINOR_FACTOR", MsgModifierPcPosReduced))
        ,("army_defence_factor"             , ("MODIFIERS_ARMY_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("army_core_defence_factor"        , ("MODIFIERS_ARMY_CORE_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("army_strength_factor"            , ("MODIFIERS_ARMY_STRENGTH", MsgModifierPcPosReduced)) --precision 2
        ,("army_infantry_attack_factor"     , ("MODIFIER_ARMY_INFANTRY_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("army_infantry_defence_factor"    , ("MODIFIER_ARMY_INFANTRY_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("army_armor_attack_factor"        , ("MODIFIER_ARMY_ARMOR_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("army_armor_defence_factor"       , ("MODIFIER_ARMY_ARMOR_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("army_artillery_attack_factor"    , ("MODIFIER_ARMY_ARTILLERY_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("army_artillery_defence_factor"   , ("MODIFIER_ARMY_ARTILLERY_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("special_forces_attack_factor"    , ("MODIFIER_SPECIAL_FORCES_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("special_forces_defence_factor"   , ("MODIFIER_SPECIAL_FORCES_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("motorized_attack_factor"         , ("MODIFIER_MOTORIZED_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("motorized_defence_factor"        , ("MODIFIER_MOTORIZED_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("mechanized_attack_factor"        , ("MODIFIER_MECHANIZED_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("mechanized_defence_factor"       , ("MODIFIER_MECHANIZED_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("cavalry_attack_factor"           , ("MODIFIER_CAVALRY_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("cavalry_defence_factor"          , ("MODIFIER_CAVALRY_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("army_speed_factor"               , ("MODIFIER_ARMY_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("army_armor_speed_factor"         , ("MODIFIER_ARMY_ARMOR_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("army_morale_factor"              , ("MODIFIER_ARMY_MORALE_FACTOR", MsgModifierPcPosReduced))
        ,("army_org"                        , ("MODIFIER_ARMY_ORG", MsgModifierColourPos))
        ,("army_org_factor"                 , ("MODIFIER_ARMY_ORG_FACTOR", MsgModifierPcPosReduced))
        ,("army_org_regain"                 , ("MODIFIER_ARMY_ORG_REGAIN", MsgModifierPcPosReduced))
        ,("breakthrough_factor"             , ("MODIFIER_BREAKTHROUGH", MsgModifierPcPosReduced))
        ,("cas_damage_reduction"            , ("MODIFIER_CAS_DAMAGE_REDUCTION", MsgModifierPcPosReduced))
        ,("combat_width_factor"             , ("MODIFIER_COMBAT_WIDTH_FACTOR", MsgModifierPcNegReduced))
        ,("coordination_bonus"              , ("MODIFIER_COORDINATION_BONUS", MsgModifierPcPosReduced))
        ,("dig_in_speed"                    , ("MODIFIER_DIG_IN_SPEED", MsgModifierColourPos))
        ,("dig_in_speed_factor"             , ("MODIFIER_DIG_IN_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("experience_gain_army_unit_factor" , ("MODIFIER_XP_GAIN_ARMY_UNIT_FACTOR", MsgModifierPcPosReduced)) --precision 1
        ,("experience_loss_factor"          , ("MODIFIER_EXPERIENCE_LOSS_FACTOR", MsgModifierPcNegReduced))
        ,("initiative_factor"               , ("MODIFIER_INITIATIVE_FACTOR", MsgModifierPcPosReduced)) --precision 1
        ,("land_night_attack"               , ("MODIFIER_LAND_NIGHT_ATTACK", MsgModifierPcPosReduced))
        ,("max_dig_in"                      , ("MODIFIER_MAX_DIG_IN", MsgModifierColourPos))
        ,("max_dig_in_factor"               , ("MODIFIER_MAX_DIG_IN_FACTOR", MsgModifierPcPosReduced))
        ,("max_planning"                    , ("MODIFIER_MAX_PLANNING", MsgModifierPcPosReduced))
        ,("max_planning_factor"             , ("MODIFIER_MAX_PLANNING_FACTOR", MsgModifierPcPosReduced))
        ,("pocket_penalty"                  , ("MODIFIER_POCKET_PENALTY", MsgModifierPcNegReduced))
        ,("recon_factor"                    , ("MODIFIER_RECON_FACTOR", MsgModifierPcPosReduced))
        ,("recon_factor_while_entrenched"   , ("MODIFIER_RECON_FACTOR_WHILE_ENTRENCHED", MsgModifierPcPosReduced))
        ,("special_forces_cap"              , ("MODIFIER_SPECIAL_FORCES_CAP", MsgModifierPcPosReduced))
        ,("special_forces_min"              , ("MODIFIER_SPECIAL_FORCES_MIN", MsgModifierColourPos))
        ,("terrain_penalty_reduction"       , ("MODIFIER_TERRAIN_PENALTY_REDUCTION", MsgModifierPcPosReduced))
        ,("org_loss_when_moving"            , ("MODIFIER_ORG_LOSS_WHEN_MOVING", MsgModifierPcNegReduced))
        ,("planning_speed"                  , ("MODIFIER_PLANNING_SPEED", MsgModifierPcPosReduced))

            -- naval invasions
        ,("naval_invasion_prep_speed"       , ("MODIFIER_NAVAL_INVASION_PREPARATION_SPEED", MsgModifierPcPosReduced)) --precision 1
        ,("naval_invasion_capacity"         , ("MODIFIER_NAVAL_INVASION_CAPACITY", MsgModifierColourPos)) --precision 0
        ,("amphibious_invasion"             , ("MODIFIER_AMPHIBIOUS_INVASION", MsgModifierPcPosReduced))
        ,("amphibious_invasion_defence"     , ("MODIFIER_NAVAL_INVASION_DEFENSE", MsgModifierPcPosReduced))
        ,("invasion_preparation"            , ("MODIFIER_NAVAL_INVASION_PREPARATION", MsgModifierPcNegReduced))

            -- Naval combat
        ,("convoy_escort_efficiency"        , ("MODIFIER_MISSION_CONVOY_ESCORT_EFFICIENCY", MsgModifierPcPosReduced))
        ,("convoy_raiding_efficiency_factor" , ("MODIFIER_CONVOY_RAIDING_EFFICIENCY_FACTOR", MsgModifierPcPosReduced))
        ,("convoy_retreat_speed"            , ("MODIFIER_CONVOY_RETREAT_SPEED", MsgModifierPcPosReduced))
        ,("critical_receive_chance"         , ("MODIFIER_NAVAL_CRITICAL_RECEIVE_CHANCE_FACTOR", MsgModifierPcNegReduced))
        ,("experience_gain_navy_unit_factor" , ("MODIFIER_XP_GAIN_NAVY_UNIT_FACTOR", MsgModifierPcPosReduced))
        ,("mines_planting_by_fleets_factor" , ("MODIFIER_MINES_PLANTING_BY_FLEETS_FACTOR", MsgModifierPcPosReduced))
        ,("mines_sweeping_by_fleets_factor" , ("MODIFIER_MINES_SWEEPING_BY_FLEETS_FACTOR", MsgModifierPcPosReduced))
        ,("navy_anti_air_attack_factor"     , ("MODIFIER_NAVY_ANTI_AIR_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("naval_coordination"              , ("MODIFIER_NAVAL_COORDINATION", MsgModifierPcPosReduced))
        ,("naval_critical_effect_factor"    , ("MODIFIER_NAVAL_CRITICAL_EFFECT_FACTOR", MsgModifierPcNegReduced))
        ,("naval_critical_score_chance_factor" , ("MODIFIER_NAVAL_CRITICAL_SCORE_CHANCE_FACTOR", MsgModifierPcPosReduced))
        ,("naval_damage_factor"             , ("MODIFIER_NAVAL_DAMAGE_FACTOR", MsgModifierPcPosReduced))
        ,("naval_defense_factor"            , ("MODIFIER_NAVAL_DEFENSE_FACTOR", MsgModifierPcPosReduced))
        ,("naval_detection"                 , ("MODIFIER_NAVAL_DETECTION", MsgModifierPcPosReduced))
        ,("naval_enemy_fleet_size_ratio_penalty_factor" , ("MODIFIER_NAVAL_ENEMY_FLEET_SIZE_RATIO_PENALTY_FACTOR", MsgModifierPcPosReduced))
        ,("naval_enemy_retreat_chance"      , ("MODIFIER_NAVAL_ENEMY_RETREAT_CHANCE", MsgModifierPcNegReduced))
        ,("naval_has_potf_in_combat_attack" , ("MODIFIER_NAVAL_HAS_POTF_IN_COMBAT_ATTACK", MsgModifierPcPosReduced))
        ,("naval_has_potf_in_combat_defense" , ("MODIFIER_NAVAL_HAS_POTF_IN_COMBAT_DEFENSE", MsgModifierPcPosReduced))
        ,("naval_hit_chance"                , ("MODIFIER_NAVAL_HIT_CHANCE", MsgModifierPcPosReduced))
        ,("naval_mines_effect_reduction"    , ("MODIFIER_NAVAL_MINES_EFFECT_REDUCTION", MsgModifierPcPosReduced))
        ,("naval_morale_factor"             , ("MODIFIER_NAVAL_MORALE_FACTOR", MsgModifierPcPosReduced))
        ,("naval_retreat_chance"            , ("MODIFIER_NAVAL_RETREAT_CHANCE", MsgModifierPcPosReduced))
        ,("naval_retreat_speed"             , ("MODIFIER_NAVAL_RETREAT_SPEED", MsgModifierPcPosReduced))
        ,("navy_org"                        , ("MODIFIER_NAVY_ORG", MsgModifierColourPos))
        ,("navy_org_factor"                 , ("MODIFIER_NAVY_ORG_FACTOR", MsgModifierPcPosReduced))
        ,("navy_max_range_factor"           , ("MODIFIER_NAVY_MAX_RANGE_FACTOR", MsgModifierPcPosReduced))
        ,("naval_torpedo_cooldown_factor"   , ("MODIFIER_NAVAL_TORPEDO_COOLDOWN_FACTOR", MsgModifierPcNegReduced))
        ,("naval_torpedo_hit_chance_factor" , ("MODIFIER_NAVAL_TORPEDO_HIT_CHANCE_FACTOR", MsgModifierPcPosReduced))
        ,("naval_torpedo_reveal_chance_factor" , ("MODIFIER_NAVAL_TORPEDO_REVEAL_CHANCE_FACTOR", MsgModifierPcNegReduced))
        ,("naval_torpedo_screen_penetration_factor" , ("MODIFIER_NAVAL_TORPEDO_SCREEN_PENETRATION_FACTOR", MsgModifierPcPosReduced))
        ,("navy_capital_ship_attack_factor" , ("MODIFIER_NAVY_CAPITAL_SHIP_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("navy_capital_ship_defence_factor" , ("MODIFIER_NAVY_CAPITAL_SHIP_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("navy_screen_attack_factor"       , ("MODIFIER_NAVY_SCREEN_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("navy_screen_defence_factor"      , ("MODIFIER_NAVY_SCREEN_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("naval_speed_factor"              , ("MODIFIER_NAVAL_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("navy_visibility"                 , ("MODIFIER_NAVAL_VISIBILITY_FACTOR", MsgModifierPcNegReduced))
        ,("navy_submarine_attack_factor"    , ("MODIFIER_NAVY_SUBMARINE_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("navy_submarine_defence_factor"   , ("MODIFIER_NAVY_SUBMARINE_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("navy_submarine_detection_factor" , ("MODIFIERS_SUBMARINE_DETECTION_FACTOR", MsgModifierPcPosReduced))
        ,("positioning"                     , ("MODIFIER_POSITIONING", MsgModifierPcPosReduced))
        ,("repair_speed_factor"             , ("MODIFIER_REPAIR_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("screening_efficiency"            , ("MODIFIER_SCREENING_EFFICIENCY", MsgModifierPcPosReduced))
        ,("screening_without_screens"       , ("MODIFIER_SCREENING_WITHOUT_SCREENS", MsgModifierPcPosReduced))
        ,("ships_at_battle_start"           , ("MODIFIER_SHIPS_AT_BATTLE_START_FACTOR", MsgModifierPcPosReduced))
        ,("spotting_chance"                 , ("MODIFIER_SPOTTING_CHANCE", MsgModifierPcPosReduced))
        ,("strike_force_movement_org_loss"  , ("MODIFIER_STRIKE_FORCE_MOVING_ORG", MsgModifierPcNegReduced))--precision 2
        ,("sub_retreat_speed"               , ("MODIFIER_SUB_RETREAT_SPEED", MsgModifierPcPosReduced)) --precision 0

            -- carriers and their planes
        ,("navy_carrier_air_agility_factor" , ("MODIFIER_NAVAL_CARRIER_AIR_AGILITY_FACTOR", MsgModifierPcPosReduced))
        ,("navy_carrier_air_attack_factor"  , ("MODIFIER_NAVAL_CARRIER_AIR_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("navy_carrier_air_targetting_factor" , ("MODIFIER_NAVAL_CARRIER_AIR_TARGETTING_FACTOR", MsgModifierPcPosReduced))
        ,("air_carrier_night_penalty_reduction_factor" , ("MODIFIER_AIR_CARRIER_NIGHT_PENALTY_REDUCTION_FACTOR", MsgModifierPcPosReduced)) --precision 2
        ,("sortie_efficiency"               , ("MODIFIER_STAT_CARRIER_SORTIE_EFFICIENCY", MsgModifierPcPosReduced))
        ,("fighter_sortie_efficiency"       , ("MODIFIER_CARRIER_FIGHTER_SORTIE_EFFICIENCY_FACTOR", MsgModifierPcPosReduced))

            -- Air combat
        ,("air_accidents_factor"            , ("MODIFIER_AIR_ACCIDENTS_FACTOR", MsgModifierPcNegReduced))
        ,("air_ace_generation_chance_factor" , ("MODIFIER_AIR_ACE_GENERATION_CHANCE_FACTOR", MsgModifierPcPosReduced))
        ,("air_agility_factor"              , ("MODIFIER_AIR_AGILITY_FACTOR", MsgModifierPcPosReduced))
        ,("air_attack_factor"               , ("MODIFIER_AIR_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("air_defence_factor"              , ("MODIFIER_AIR_DEFENCE_FACTOR", MsgModifierPcPosReduced))

        ,("air_close_air_support_agility_factor" , ("MODIFIER_CAS_AGILITY_FACTOR", MsgModifierPcPosReduced))
        ,("air_close_air_support_attack_factor" , ("MODIFIER_CAS_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("air_close_air_support_defence_factor" , ("MODIFIER_CAS_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("air_air_superiority_agility_factor", ("MODIFIER_AIR_SUPERIORITY_AGILITY_FACTOR", MsgModifierPcPosReduced))
        ,("air_air_superiority_attack_factor", ("MODIFIER_AIR_SUPERIORITY_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("air_air_superiority_defence_factor", ("MODIFIER_AIR_SUPERIORITY_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("air_interception_agility_factor"  , ("MODIFIER_INTERCEPTION_AGILITY_FACTOR", MsgModifierPcPosReduced))
        ,("air_interception_attack_factor"  , ("MODIFIER_INTERCEPTION_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("air_interception_defence_factor" , ("MODIFIER_INTERCEPTION_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("air_strategic_bomber_agility_factor" , ("MODIFIER_STRATEGIC_BOMBER_AGILITY_FACTOR", MsgModifierPcPosReduced))
        ,("air_strategic_bomber_attack_factor" , ("MODIFIER_STRATEGIC_BOMBER_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("air_strategic_bomber_defence_factor" , ("MODIFIER_STRATEGIC_BOMBER_DEFENCE_FACTOR", MsgModifierPcPosReduced))
        ,("naval_strike_agility_factor"     , ("MODIFIER_NAVAL_STRIKE_AGILITY_FACTOR", MsgModifierPcPosReduced))
        ,("naval_strike_attack_factor"      , ("MODIFIER_NAVAL_STRIKE_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("air_paradrop_attack_factor"      , ("MODIFIER_PARADROP_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("air_paradrop_agility_factor"     , ("MODIFIER_AIR_SUPERIORITY_AGILITY_FACTOR", MsgModifierPcPosReduced))
        ,("air_paradrop_defence_factor"     , ("MODIFIER_PARADROP_DEFENCE_FACTOR", MsgModifierPcPosReduced))

        ,("naval_strike_targetting_factor"  , ("MODIFIER_NAVAL_STRIKE_TARGETTING_FACTOR", MsgModifierPcPosReduced))
        ,("air_bombing_targetting"          , ("MODIFIER_AIR_BOMBING_TARGETTING", MsgModifierPcPosReduced))
        ,("air_cas_efficiency"              , ("MODIFIER_AIR_CAS_EFFICIENCY", MsgModifierPcPosReduced))
        ,("air_cas_present_factor"          , ("MODIFIER_AIR_CAS_PRESENT_FACTOR", MsgModifierPcPosReduced))
        ,("air_intercept_efficiency"        , ("MODIFIER_AIR_INTERCEPT_EFFICIENCY", MsgModifierPcPosReduced))
        ,("air_maximum_speed_factor"        , ("MODIFIER_AIR_MAX_SPEED_FACTOR", MsgModifierPcPosReduced))
        ,("air_mission_efficiency"          , ("MODIFIER_AIR_MISSION_EFFICIENCY", MsgModifierPcPosReduced))
        ,("air_mission_xp_gain_factor"      , ("MODIFIER_AIR_MISSION_XP_FACTOR", MsgModifierPcPosReduced)) --precision 0
        ,("air_nav_efficiency"              , ("MODIFIER_AIR_NAV_EFFICIENCY", MsgModifierPcPosReduced)) --precison 0
        ,("air_night_penalty"               , ("MODIFIER_AIR_NIGHT_PENALTY", MsgModifierPcNegReduced))
        ,("air_range_factor"                , ("MODIFIER_AIR_RANGE_FACTOR", MsgModifierPcPosReduced))
        ,("air_strategic_bomber_bombing_factor" , ("MODIFIER_STRATEGIC_BOMBER_BOMBING_FACTOR", MsgModifierPcPosReduced))
        ,("air_strategic_bomber_night_penalty" , ("MODIFIER_AIR_STRAT_BOMBER_NIGHT_PENALTY", MsgModifierPcNegReduced)) --precision 2
        ,("air_superiority_efficiency"      , ("MODIFIER_AIR_SUPERIORITY_EFFICIENCY", MsgModifierPcPosReduced)) --precision 0
        ,("air_training_xp_gain_factor"     , ("MODIFIER_AIR_TRAINING_XP_FACTOR", MsgModifierPcPosReduced))
        ,("air_weather_penalty"             , ("MODIFIER_AIR_WEATHER_PENALTY", MsgModifierPcNegReduced))
        ,("air_wing_xp_loss_when_killed_factor" , ("MODIFIER_AIR_WING_XP_LOSS_WHEN_KILLED_FACTOR", MsgModifierPcNegReduced)) --precision 0
        ,("army_bonus_air_superiority_factor" , ("MODIFIER_ARMY_BONUS_AIR_SUPERIORITY_FACTOR", MsgModifierPcPosReduced))
        ,("enemy_army_bonus_air_superiority_factor" , ("MODIFIER_ENEMY_ARMY_BONUS_AIR_SUPERIORITY_FACTOR", MsgModifierPcNegReduced))
        ,("ground_attack_factor"            , ("MODIFIER_GROUND_ATTACK_FACTOR", MsgModifierPcPosReduced)) --precision 1
        ,("mines_planting_by_air_factor"    , ("MODIFIER_MINES_PLANTING_BY_AIR_FACTOR", MsgModifierPcPosReduced))
        ,("strategic_bomb_visibility"       , ("MODIFIER_STRAT_BOMBING_VISIBILITY", MsgModifierPcNegReduced)) --precison 0

            -- targeted
        ,("extra_trade_to_target_factor"    , ("MODIFIER_TRADE_TO_TARGET_FACTOR", MsgModifierPcPosReduced))
        ,("trade_cost_for_target_factor"    , ("MODIFIER_TRADE_COST_TO_TARGET_FACTOR", MsgModifierPcNegReduced))
        ,("generate_wargoal_tension_against" , ("MODIFIER_GENERATE_WARGOAL_TENSION_LIMIT_AGAINST_COUNTRY",  MsgModifierPcReducedSign))
        ,("attack_bonus_against"            , ("MODIFIER_ATTACK_BONUS_AGAINST_A_COUNTRY", MsgModifierPcPosReduced))
        ,("attack_bonus_against_cores"      , ("MODIFIER_ATTACK_BONUS_AGAINST_A_COUNTRY_ON_ITS_CORES", MsgModifierPcPosReduced))
        ,("cic_to_target_factor"            , ("MODIFIER_CIC_TO_TARGET_FACTOR", MsgModifierPcNegReduced))
        ,("mic_to_target_factor"            , ("MODIFIER_MIC_TO_TARGET_FACTOR", MsgModifierPcNegReduced))
        ,("targeted_legitimacy_daily"       , ("MODIFIER_TARGETED_LEGITIMACY_DAILY", MsgModifierColourPos))
        ,("breakthrough_bonus_against"      , ("MODIFIER_BREAKTHROUGH_BONUS_AGAINST_A_COUNTRY", MsgModifierPcPosReduced))
        ,("defense_bonus_against"           , ("MODIFIER_DEFENSE_BONUS_AGAINST_A_COUNTRY", MsgModifierPcPosReduced))

        -- State Scope
        ,("army_speed_factor_for_controller" , ("MODIFIER_ARMY_SPEED_FACTOR_FOR_CONTROLLER", MsgModifierPcPosReduced))
        ,("attrition_for_controller"        , ("MODIFIER_ATTRITION_FOR_CONTROLLER", MsgModifierPcNegReduced)) --precision 1
        ,("compliance_gain"                 , ("MODIFIER_COMPLIANCE_GAIN_ADD", MsgModifierPcPos))
        ,("compliance_growth"               , ("MODIFIER_COMPLIANCE_GROWTH", MsgModifierPcPosReduced))
        ,("disable_strategic_redeployment"  , ("MODIFIER_STRATEGIC_REDEPLOYMENT_DISABLED", MsgModifierNoYes))
        ,("enemy_intel_network_gain_factor_over_occupied_tag" , ("MODIFIER_ENEMY_INTEL_NETWORK_GAIN_FACTOR_OVER_OCCUPIED_TAG", MsgModifierPcNegReduced))
        ,("local_building_slots"            , ("MODIFIER_LOCAL_BUILDING_SLOTS", MsgModifierPcPos))
        ,("local_building_slots_factor"     , ("MODIFIER_LOCAL_BUILDING_SLOTS_FACTOR", MsgModifierPcPosReduced))
        ,("local_factories"                 , ("MODIFIER_LOCAL_FACTORIES", MsgModifierPcPosReduced))
        ,("local_factory_sabotage"         , ("MODIFIER_LOCAL_FACTORY_SABOTAGE", MsgModifierPcNegReduced)) --precision 0
        ,("local_intel_to_enemies"          , ("MODIFIER_LOCAL_INTEL_TO_ENEMIES", MsgModifierPcNegReduced))
        ,("local_manpower"                  , ("MODIFIER_LOCAL_MANPOWER", MsgModifierPcPosReduced))
        ,("local_non_core_manpower"         , ("MODIFIER_LOCAL_NON_CORE_MANPOWER", MsgModifierPcPosReduced))
        ,("local_org_regain"                , ("MODIFIER_LOCAL_ORG_REGAIN", MsgModifierPcPosReduced))
        ,("local_resources"                 , ("MODIFIER_LOCAL_RESOURCES", MsgModifierPcPosReduced))
        ,("local_supplies"                  , ("MODIFIER_LOCAL_SUPPLIES", MsgModifierPcPosReduced))
        ,("local_supplies_for_controller"   , ("MODIFIER_LOCAL_SUPPLIES_FOR_CONTROLLER", MsgModifierPcPosReduced)) --precision 0
        ,("local_supply_impact_factor"      , ("MODIFIER_LOCAL_SUPPLY_IMPACT", MsgModifierPcNegReduced)) --precision 0
        ,("local_non_core_supply_impact_factor" , ("MODIFIER_LOCAL_NON_CORE_SUPPLY_IMPACT", MsgModifierPcNegReduced)) --precision 0
        ,("mobilization_speed"              , ("MODIFIER_MOBILIZATION_SPEED", MsgModifierPcPosReduced))
        ,("non_core_manpower"               , ("MODIFIER_GLOBAL_NON_CORE_MANPOWER", MsgModifierPcPosReduced))
        ,("non_core_manpower"               , ("MODIFIER_GLOBAL_NON_CORE_MANPOWER", MsgModifierPcPosReduced))
        ,("recruitable_population_factor"   , ("MODIFIER_RECRUITABLE_POPULATION_FACTOR", MsgModifierPcPosReduced))
        ,("resistance_damage_to_garrison"   , ("MODIFIER_RESISTANCE_DAMAGE_TO_GARRISONS", MsgModifierPcNegReduced))
        ,("resistance_decay"                , ("MODIFIER_RESISTANCE_DECAY", MsgModifierPcPosReduced))
        ,("resistance_garrison_penetration_chance" , ("MODIFIER_RESISTANCE_GARRISON_PENETRATION_CHANCE", MsgModifierPcNegReduced))
        ,("resistance_growth"               , ("MODIFIER_RESISTANCE_GROWTH", MsgModifierPcNegReduced))
        ,("resistance_target"               , ("MODIFIER_RESISTANCE_TARGET", MsgModifierPcNegReduced))
        ,("starting_compliance"             , ("MODIFIER_COMPLIANCE_STARTING_VALUE", MsgModifierPcPosReduced))
        ,("state_resources_factor"          , ("MODIFIER_STATE_RESOURCES_FACTOR", MsgModifierPcPosReduced))
        ,("state_production_speed_buildings_factor" , ("MODIFIER_STATE_PRODUCTION_SPEED_BUILDINGS_FACTOR", MsgModifierPcPosReduced))
        ,("enemy_operative_detection_chance_factor_over_occupied_tag" , ("MODIFIER_ENEMY_OPERATIVE_DETECTION_CHANCE_FACTOR_OVER_OCCUPIED_TAG", MsgModifierPcPosReduced)) --precision 0

        -- Unit Leader Scope
        ,("cannot_use_abilities"            , ("MODIFIER_CANNOT_USE_ABILITIES", MsgModifierNoYes))
        ,("dont_lose_dig_in_on_attack"      , ("MsgMODIFIER_DONT_LOSE_DIGIN_ON_ATTACK_MOVE", MsgModifierYesNo))
        ,("exiled_divisions_attack_factor"  , ("MODIFIER_EXILED_DIVISIONS_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("exiled_divisions_defense_factor" , ("MODIFIER_EXILED_DIVISIONS_DEFENSE_FACTOR", MsgModifierPcPosReduced))
        ,("own_exiled_divisions_attack_factor" , ("MODIFIER_OWN_EXILED_DIVISIONS_ATTACK_FACTOR", MsgModifierPcPosReduced))
        ,("own_exiled_divisions_defense_factor" , ("MODIFIER_OWN_EXILED_DIVISIONS_DEFENSE_FACTOR", MsgModifierPcPosReduced))
        ,("experience_gain_factor"          , ("MODIFIER_XP_GAIN_FACTOR", MsgModifierPcPosReduced))
        ,("fortification_collateral_chance" , ("MODIFIER_FORTIFICATION_COLLATERAL_CHANCE", MsgModifierPcPosReduced))
        ,("max_commander_army_size"         , ("MODIFIER_ARMY_LEADER_MAX_ARMY_SIZE", MsgModifierColourPos))
        ,("max_army_group_size"             , ("MODIFIER_ARMY_LEADER_MAX_ARMY_GROUP_SIZE", MsgModifierColourPos))
        ,("promote_cost_factor"             , ("MODIFIER_UNIT_LEADER_PROMOTE_COST_FACTOR", MsgModifierPcNegReduced))
        ,("reassignment_duration_factor"    , ("MODIFIER_REASSIGNMENT_DURATION_FACTOR", MsgModifierPcNegReduced))
        ,("sickness_chance"                 , ("MODIFIER_SICKNESS_CHANCE", MsgModifierPcNegReduced))
        ,("skill_bonus_factor"              , ("MODIFIER_UNIT_LEADER_SKILL_BONUS_FACTOR", MsgModifierPcPosReduced))
        ,("terrain_trait_xp_gain_factor"    , ("MODIFIER_TERRAIN_TRAIT_XP_GAIN_FACTOR", MsgModifierPcPosReduced)) --precision 2
        ,("wounded_chance_factor"           , ("MODIFIER_WOUNDED_CHANCE_FACTOR", MsgModifierPcNegReduced))
        ,("shore_bombardment_bonus"         , ("MODIFIER_SHORE_BOMBARDMENT", MsgModifierPcPosReduced))

        -- Strategic region scope
        ,("air_accidents"                   , ("MODIFIER_AIR_ACCIDENTS", MsgModifierPcNegReduced))
        ,("air_detection"                   , ("MODIFIER_AIR_DETECTION", MsgModifierPcPosReduced))

        -- equipment/stats
        ,("build_cost_ic"           , ("STAT_COMMON_BUILD_COST_IC", MsgModifierPcNegReduced))
        ,("reliability"             , ("STAT_COMMON_RELIABILITY", MsgModifierPcPosReduced))
        ,("armor_value"             , ("STAT_COMMON_ARMOR", MsgModifierPcPosReduced))
        ,("maximum_speed"           , ("STAT_COMMON_MAXIMUM_SPEED", MsgModifierPcPosReduced))
        ,("fuel_consumption"        , ("STAT_COMMON_FUEL_CONSUMPTION", MsgModifierPcNegReduced))
        ,("ap_attack"               , ("STAT_COMMON_PIERCING", MsgModifierPcPosReduced))
        ,("max_strength"            , ("STAT_COMMON_MAX_STRENGTH", MsgModifierPcPosReduced))

        ,("attack"                  , ("STAT_ADJUSTER_ATTACK", MsgModifierPcPosReduced))
        ,("defense"                 , ("STAT_ADJUSTER_DEFENCE", MsgModifierPcPosReduced))
        ,("movement"                , ("STAT_ADJUSTER_MOVEMENT", MsgModifierPcPosReduced))

        ,("breakthrough"            , ("STAT_ARMY_BREAKTHROUGH", MsgModifierPcPosReduced))
        ,("hardness"                , ("STAT_ARMY_HARDNESS", MsgModifierPcPosReduced))
        ,("supply_consumption"      , ("STAT_ARMY_SUPPLY_CONSUMPTION", MsgModifierPcPosReduced)) --precision 0
        ,("soft_attack"             , ("STAT_ARMY_SOFT_ATTACK", MsgModifierPcPosReduced))
        ,("hard_attack"             , ("STAT_ARMY_HARD_ATTACK", MsgModifierPcPosReduced))

        ,("air_agility"             , ("STAT_AIR_AGILITY", MsgModifierPcPosReduced))
        ,("air_attack"              , ("STAT_AIR_ATTACK", MsgModifierPcPosReduced))
        ,("air_range"               , ("STAT_AIR_RANGE", MsgModifierPcPosReduced))
        ,("air_defence"             , ("STAT_AIR_DEFENCE", MsgModifierPcPosReduced))
        ,("air_ground_attack"       , ("STAT_AIR_GROUND_ATTACK", MsgModifierPcPosReduced))
        ,("air_bombing"             , ("STAT_AIR_BOMBING", MsgModifierPcPosReduced))
        ,("naval_strike_attack"     , ("STAT_AIR_NAVAL_STRIKE_ATTACK", MsgModifierPcPosReduced))

        ,("surface_detection"       , ("STAT_NAVY_SURFACE_DETECTION", MsgModifierPcPosReduced))
        ,("sub_detection"           , ("STAT_NAVY_SUB_DETECTION", MsgModifierPcPosReduced))
        ,("sub_visibility"          , ("STAT_NAVY_SUB_VISIBILITY", MsgModifierPcNegReduced))
        ,("anti_air_attack"         , ("STAT_NAVY_ANTI_AIR_ATTACK", MsgModifierPcPosReduced))
        ,("surface_visibility"      , ("STAT_NAVY_SURFACE_VISIBILITY", MsgModifierPcNegReduced))
        ,("naval_speed"             , ("STAT_NAVY_MAXIMUM_SPEED", MsgModifierPcPosReduced))
        ,("naval_range"             , ("STAT_NAVY_RANGE", MsgModifierPcPosReduced))
        ,("lg_attack"               , ("STAT_NAVY_LG_ATTACK", MsgModifierPcPosReduced))
        ,("hg_attack"               , ("STAT_NAVY_HG_ATTACK", MsgModifierPcPosReduced))
        ,("carrier_size"            , ("STAT_CARRIER_SIZE", MsgModifierPcPosReduced))
        ,("torpedo_attack"          , ("STAT_NAVY_TORPEDO_ATTACK", MsgModifierPcPosReduced))
        ]

-------------------------------------------------
-- Handler for add_dynamic_modifier --
-------------------------------------------------
data AddDynamicModifier = AddDynamicModifier
    { adm_modifier :: Text
    , adm_scope :: Either Text (Text, Text)
    , adm_days :: Maybe Double
    }
newADM :: AddDynamicModifier
newADM = AddDynamicModifier undefined (Left "THIS") Nothing
addDynamicModifier :: forall g m. (HOI4Info g, Monad m) => StatementHandler g m
addDynamicModifier stmt@[pdx| %_ = @scr |] =
    pp_adm (foldl' addLine newADM scr)
    where
        addLine adm [pdx| modifier = $mod |] = adm { adm_modifier = mod }
        addLine adm [pdx| scope = $tag |] = adm { adm_scope = Left tag }
        addLine adm [pdx| scope = $vartag:$var |] = adm { adm_scope = Right (vartag, var) }
        addLine adm [pdx| days = !amt |] = adm { adm_days = Just amt }
        addLine adm stmt = trace ("Unknown in add_dynamic_modifier: " ++ show stmt) adm
        pp_adm adm = do
            let days = maybe "" formatDays (adm_days adm)
            mmod <- HM.lookup (adm_modifier adm) <$> getDynamicModifiers
            thescope <- getCurrentScope
            dynflag <- case thescope of
                Just HOI4Country -> eflag (Just HOI4Country) $ adm_scope adm
                Just HOI4ScopeState -> eGetState $ adm_scope adm
                Just HOI4From -> return $ Just "FROM"
                _ -> return $ Just "<!-- check script -->"
            let dynflagd = fromMaybe "<!-- check script -->" dynflag
            case mmod of
                Just mod -> withCurrentIndent $ \i -> do
                    effect <- fold <$> indentUp (traverse (modifierMSG False "") (dmodEffects mod))
                    trigger <- indentUp $ ppMany (dmodEnable mod)
                    let name = dmodLocName mod
                        locName = maybe ("<tt>" <> adm_modifier adm <> "</tt>") (Doc.doc2text . iquotes) name
                    return $ ((i, MsgAddDynamicModifier locName dynflagd days) : effect) ++ (if null trigger then [] else (i+1, MsgLimit) : trigger)
                Nothing -> trace ("add_dynamic_modifier: Modifier " ++ T.unpack (adm_modifier adm) ++ " not found") $ preStatement stmt
addDynamicModifier stmt = trace ("Not handled in addDynamicModifier: " ++ show stmt) $ preStatement stmt

removeDynamicModifier :: (HOI4Info g, Monad m) => StatementHandler g m
removeDynamicModifier stmt@[pdx| %_ = $txt |] = withLocAtom MsgRemoveDynamicMod stmt
removeDynamicModifier stmt@[pdx| %_ = @dyn |] = do
    case dyn of
        [stmtd@[pdx| %_ = $txt |]] ->  withLocAtom MsgRemoveDynamicMod stmtd
        _-> preStatement stmt
removeDynamicModifier stmt = preStatement stmt

flagTextMaybe :: (HOI4Info g, Monad m) => Text -> PPT g m (Maybe Text)
flagTextMaybe txt = eflag (Just HOI4Country) (Left txt)

hasDynamicModifier :: (HOI4Info g, Monad m) => StatementHandler g m
hasDynamicModifier stmt@[pdx| %_ = @dyn |] = if length dyn == 2
    then textAtom "scope" "modifier" MsgHasDynamicModFlag flagTextMaybe stmt
    else case dyn of
        [stmtd@[pdx| %_ = $txt |]] ->  withLocAtom MsgHasDynamicMod stmtd
        _-> preStatement stmt
hasDynamicModifier stmt = preStatement stmt

--------------------------------------------
-- Handler for add_power_balance_modifier --
--------------------------------------------

addPowerBalanceModifier :: forall g m. (HOI4Info g, Monad m) => StatementHandler g m
addPowerBalanceModifier stmt@[pdx| %_ = @scr |] =
    pp_ta (parseTA "id" "modifier" scr)
    where
        pp_ta :: TextAtom -> PPT g m IndentedMessages
        pp_ta ta = case (ta_what ta, ta_atom ta) of
            (Just idpob, Just modi) -> do
                mmod <- HM.lookup modi <$> getModifiers
                midpob_loc <- getGameL10nIfPresent idpob
                let idpob_loc = fromMaybe ("<tt>" <> idpob <> "</tt>") midpob_loc
                case mmod of
                    Just mod -> withCurrentIndent $ \i -> do
                        effect <- fold <$> indentUp (traverse (modifierMSG False "") (modEffects mod))
                        let name = modLocName mod
                            locName = maybe ("<tt>" <> modi <> "</tt>") (Doc.doc2text . iquotes) name
                        return ((i, MsgAddPowerBalanceModifier idpob_loc idpob locName modi) : effect)
                    _ -> trace ("add_power_balance_modifier: Modifier " ++ T.unpack modi ++ " not found") $ preStatement stmt
            _-> preStatement stmt
addPowerBalanceModifier stmt = trace ("Not handled in addPowerBalanceModifier: " ++ show stmt) $ preStatement stmt


----------------
-- characters --
----------------

addFieldMarshalRole :: (Monad m, HOI4Info g) => (Text -> ScriptMessage) -> StatementHandler g m
addFieldMarshalRole msg stmt@[pdx| %_ = @scr |] = do
        let (name, _) = extractStmt (matchLhsText "character") scr
        nameloc <- case name of
            Just [pdx| character = ?id |] -> getCharacterName id
            _ -> case extractStmt (matchLhsText "name") scr of
                (Just [pdx| name = ?id |],_) -> getCharacterName id
                _-> return ""
        msgToPP $ msg nameloc
addFieldMarshalRole _ stmt = preStatement stmt

setCharacterName :: forall g m. (HOI4Info g, Monad m) => StatementHandler g m
setCharacterName stmt@[pdx| %_ = ?txt |] = withLocAtom MsgSetCharacterName stmt
setCharacterName stmt@[pdx| %_ = @scr |] = case scr of
    [[pdx| $who = $name |]] -> do
        whochar <- getCharacterName who
        nameloc <- getGameL10n name
        msgToPP $ MsgSetCharacterNameType whochar nameloc
    _ -> preStatement stmt
setCharacterName stmt = preStatement stmt

removeAdvisorRole :: forall g m. (HOI4Info g, Monad m) => StatementHandler g m
removeAdvisorRole stmt@[pdx| %_ = @scr |] =
    if length scr == 2
    then textAtom "character" "slot" MsgRemoveAdvisorRole getGameL10nIfPresent stmt
    else do
        let (mslot,_) = extractStmt (matchLhsText "slot") scr
        slot <- case mslot of
            Just [pdx| %_ = $slottype |] -> getGameL10n slottype
            _-> return "<!-- Check Script -->"
        msgToPP $ MsgRemoveAdvisorRole "" "" slot
removeAdvisorRole stmt = preStatement stmt

withCharacter :: (HOI4Info g, Monad m) => (Text -> ScriptMessage) -> StatementHandler g m
withCharacter msg stmt@[pdx| %_ = ?txt |] = do
    chaname <- getCharacterName txt
    msgToPP $ msg chaname
withCharacter _ stmt = preStatement stmt

addAdvisorRole :: (Monad m, HOI4Info g) => StatementHandler g m
addAdvisorRole stmt@[pdx| %_ = @scr |] = do
        let (name, rest) = extractStmt (matchLhsText "character") scr
            (advisor, rest') = extractStmt (matchLhsText "advisor") rest
            (activate, _) = extractStmt (matchLhsText "activate") rest'
        activate <- maybe (return False) (\case
            [pdx| %_ = yes |] -> return True
            _-> return False) activate
        nameloc <- case name of
            Just [pdx| character = $id |] -> getCharacterName id
            _ -> return ""
        case advisor of
            Just advisorj -> do
                (slotloc, traitmsg) <- parseAdvisor advisorj
                basemsg <- msgToPP $ MsgAddAdvisorRole nameloc slotloc
                (if activate
                then do
                    hiremsg <- msgToPP MsgAndIsHired
                    return $ basemsg ++ traitmsg ++ hiremsg
                else return $ basemsg ++ traitmsg)
            _-> preStatement stmt
addAdvisorRole stmt = preStatement stmt

parseAdvisor :: (Monad m, HOI4Info g) =>
    GenericStatement -> PPT g m (Text, [IndentedMessage])
parseAdvisor stmt@[pdx| %_ = @scr |] = do
    let (slot, rest) = extractStmt (matchLhsText "slot") scr
        (traits, modrest) = extractStmt (matchLhsText "traits") rest
        (modifier, bonusrest) = extractStmt (matchLhsText "modifier") modrest
        (resbonus, _) = extractStmt (matchLhsText "research_bonus") bonusrest
    modmsg <- maybe (return []) (indentUp . handleModifier) modifier
    resmsg <- maybe (return []) (indentUp . handleResearchBonus) resbonus
    traitmsg <- case traits of
        Just [pdx| %_ = @arr |] -> do
            let traitbare = mapMaybe getbaretraits arr
            concatMapM (indentUp . getLeaderTraits) traitbare
        _-> return []
    slotloc <- maybe (return "") (\case
        [pdx| %_ = $slottype|] -> getGameL10n slottype
        _->return "<!-- Check Script -->") slot

    return (slotloc, traitmsg ++ modmsg ++ resmsg)
parseAdvisor stmt = return ("<!-- Check Script -->", [])

addLeaderRole :: (Monad m, HOI4Info g) => StatementHandler g m
addLeaderRole stmt@[pdx| %_ = @scr |] = do
        let (name, rest) = extractStmt (matchLhsText "character") scr
            (leader, rest') = extractStmt (matchLhsText "country_leader") rest
            (promote, _) = extractStmt (matchLhsText "promote_leader") rest'
        promoted <- maybe (return False) (\case
            [pdx| %_ = yes |] -> return True
            _-> return False) promote
        nameloc <- case name of
            Just [pdx| character = $id |] -> getCharacterName id
            _ -> return ""
        case leader of
            Just leaderj -> do
                (ideoloc, traitmsg) <- parseLeader leaderj
                basemsg <- if promoted
                    then msgToPP $ MsgAddCountryLeaderRolePromoted nameloc ideoloc
                    else msgToPP $ MsgAddCountryLeaderRole nameloc ideoloc
                return $ basemsg ++ traitmsg
            _-> preStatement stmt
addLeaderRole stmt = preStatement stmt

parseLeader :: (Monad m, HOI4Info g) =>
    GenericStatement -> PPT g m (Text, [IndentedMessage])
parseLeader stmt@[pdx| %_ = @scr |] = do
    let (ideo, rest) = extractStmt (matchLhsText "ideology") scr
        (traits, _) = extractStmt (matchLhsText "traits") rest
    traitmsg <- case traits of
        Just [pdx| %_ = @arr |] -> do
            let traitbare = mapMaybe getbaretraits arr
            concatMapM ppHt traitbare
        _-> return []
    ideoloc <- maybe (return "") (\case
        [pdx| %_ = $ideotype|] -> do
            subideos <- getIdeology
            case HM.lookup ideotype subideos of
                Just ideo -> getGameL10n ideo
                _-> return "<!-- Check Script -->"
        _->return "<!-- Check Script -->") ideo
    return (ideoloc, traitmsg)
parseLeader stmt = return ("<!-- Check Script -->", [])


createLeader :: (Monad m, HOI4Info g) => StatementHandler g m
createLeader stmt@[pdx| %_ = @scr |] = do
        let (name, rest) = extractStmt (matchLhsText "name") scr
            (ideo, rest') = extractStmt (matchLhsText "ideology") rest
            (traits, _) = extractStmt (matchLhsText "traits") rest'
        nameloc <- case name of
            Just [pdx| %_ = ?id |] -> getCharacterName id
            _ -> return ""
        traitmsg <- case traits of
            Just [pdx| %_ = @arr |] -> do
                let traitbare = mapMaybe getbaretraits arr
                concatMapM ppHt traitbare
            _-> return []
        ideoloc <- maybe (return "") (\case
            [pdx| %_ = $ideotype|] -> do
                subideos <- getIdeology
                case HM.lookup ideotype subideos of
                    Just ideo -> getGameL10n ideo
                    _-> return "<!-- Check Script -->"
            _-> return "<!-- Check Script -->") ideo
        basemsg <- msgToPP $ MsgAddCountryLeaderRole nameloc ideoloc
        return $ basemsg ++ traitmsg
createLeader stmt = preStatement stmt

promoteCharacter :: (Monad m, HOI4Info g) => StatementHandler g m
promoteCharacter stmt@[pdx| %_ = @scr |] =
    ppPC (parseTA "character" "ideology" scr)
    where
        ppPC ta = case (ta_what ta, ta_atom ta) of
            (Just what, Just atom) -> promomessage what atom stmt
            (_, Just atom) -> promomessage "" atom stmt
            _ -> preStatement stmt
promoteCharacter stmt@[pdx| %_ = $txt |]
    | txt == "yes" = msgToPP $ MsgPromoteCharacter ""
    | otherwise = do
        chas <- getCharacters
        subideos <- getIdeology
        case HM.lookup txt subideos of
            Just ideo -> promomessage "" txt stmt
            _-> case HM.lookup txt chas of
                Just ccha -> promomessage txt "" stmt
                _-> preStatement stmt
promoteCharacter stmt = preStatement stmt

promomessage :: (Monad m, HOI4Info g) => Text
    -> Text-> StatementHandler g m
promomessage what atom stmt = do
    chas <- getCharacters
    subideos <- getIdeology
    ideoloc <- maybe (return "") getGameL10n (HM.lookup atom subideos)
    case HM.lookup what chas of
        Just ccha -> do
            let nameloc = cha_loc_name ccha
                ideolocd = if T.null ideoloc
                    then fromMaybe "" (cha_leader_ideology ccha)
                    else ideoloc
            traitmsg <- case cha_leader_traits ccha of
                Just trts -> do
                    concatMapM ppHt trts
                _-> return []
            basemsg <- if not (T.null ideoloc)
                then msgToPP $ MsgAddCountryLeaderRolePromoted nameloc ideolocd
                else msgToPP $ MsgPromoteCharacter nameloc
            return $ basemsg ++ traitmsg
        _-> if not (T.null what)
            then preStatement stmt
            else msgToPP $ MsgAddCountryLeaderRolePromoted "" ideoloc

ppHt :: (Monad m, HOI4Info g) => Text -> PPT g m IndentedMessages
ppHt trait = do
    traitloc <- getGameL10n trait
    namemsg <- indentUp $ plainMsg' ("'''" <> traitloc <> "'''")
    traitmsg' <- indentUp $ indentUp $ getLeaderTraits trait
    return $ namemsg : traitmsg'

getbaretraits :: GenericStatement -> Maybe Text
getbaretraits (StatementBare (GenericLhs trait [])) = Just trait
getbaretraits stmt = Nothing

getCharacterName :: (Monad m, HOI4Info g) =>
    Text -> PPT g m Text
getCharacterName idn = do
    characters <- getCharacters
    case HM.lookup idn characters of
        Just charid -> return $ cha_loc_name charid
        _ -> getGameL10n idn

-- operatives

data CreateOperative = CreateOperative
        {   co_bypass_recruitment :: Bool
        ,   co_name :: Text
        ,   co_traits :: Maybe [Text]
        ,   co_nationalities :: Maybe [Text]
        ,   co_available_to_spy_master :: Bool
        }

newCO :: CreateOperative
newCO = CreateOperative False "" Nothing Nothing False

createOperativeLeader :: forall g m. (HOI4Info g, Monad m) => StatementHandler g m
createOperativeLeader stmt@[pdx| %_ = @scr |]
    = ppCO (foldl' addLine newCO scr)
    where
        addLine :: CreateOperative -> GenericStatement -> CreateOperative
        addLine co [pdx| bypass_recruitment = %rhs |]
            | GenericRhs "yes" [] <- rhs = co { co_bypass_recruitment = True }
            | GenericRhs "no" [] <- rhs = co { co_bypass_recruitment = False }
        addLine co [pdx| name = ?txt |] = co {co_name = txt}
        addLine co [pdx| traits = @arr |] =
            let traits = mapMaybe getbaretraits arr
            in co {co_traits = Just traits}
        addLine co [pdx| nationalities = @arr |] =
            let nats = mapMaybe getbaretraits arr
            in co {co_nationalities = Just nats}
        addLine co [pdx| available_to_spy_master = %rhs |]
            | GenericRhs "yes" [] <- rhs = co { co_available_to_spy_master = True }
            | otherwise = co
        addLine co stmt = co

        ppCO co = do
            natmsg <- case co_nationalities co of
                    Just nats -> do
                        flagged <- mapM (flagText (Just HOI4Country)) nats
                        return $ T.intercalate ", " flagged
                    _ -> return ""
            basemsg <- msgToPP $ MsgCreateOperativeLeader (co_name co) natmsg (co_bypass_recruitment co) (co_available_to_spy_master co)
            traitsmsg <- case co_traits co of
                Just traits -> concatMapM (\t -> do
                    namemsg <- indentUp $ plainMsg' ("'''" <> t <> "'''")
                    traitmsg <- indentUp $ indentUp $ getUnitTraits t
                    return $ namemsg : traitmsg
                    ) traits
                _ -> return []
            return $ basemsg ++ traitsmsg
createOperativeLeader stmt = preStatement stmt

------------
-- traits --
------------
data HandleTrait = HandleTrait
    { ht_trait :: Text
    , ht_character :: Maybe Text
    , ht_ideology :: Maybe Text
    }

newHT :: HandleTrait
newHT = HandleTrait undefined Nothing Nothing

handleTrait :: forall g m. (HOI4Info g, Monad m) => Bool -> StatementHandler g m
handleTrait addremove stmt@[pdx| %_ = @scr |] =
    pp_ht addremove (foldl' addLine newHT scr)
    where
        addLine ht [pdx| trait = $txt |] = ht { ht_trait = txt }
        addLine ht [pdx| character = $txt |] = ht { ht_character = Just txt }
        addLine ht [pdx| ideology = $txt |] = ht { ht_ideology = Just txt }
        addLine ht [pdx| slot = %_ |] = ht
        addLine ht stmt = trace ("Unknown in handleTrait: " ++ show stmt) ht
        pp_ht addremove ht = do
            traitloc <- getGameL10n $ ht_trait ht
            namemsg <- indentUp $ plainMsg' ("'''" <> traitloc <> "'''")
            traitmsg' <- indentUp $ indentUp $ getLeaderTraits (ht_trait ht)
            let traitmsg = namemsg : traitmsg'
            case (ht_character ht, ht_ideology ht) of
                (Just char, Just ideo) -> do
                    charloc <- getCharacterName char
                    ideoloc <- getGameL10n ideo
                    baseMsg <- msgToPP $ MsgTraitCharIdeo charloc addremove ideoloc
                    return $ baseMsg ++ traitmsg
                (Just char, _) -> do
                    charloc <- getCharacterName char
                    baseMsg <- msgToPP $ MsgTraitChar charloc addremove
                    return $ baseMsg ++ traitmsg
                (_, Just ideo) -> do
                    ideoloc <- getGameL10n ideo
                    baseMsg <- msgToPP $ MsgTraitIdeo addremove ideoloc
                    return $ baseMsg ++ traitmsg
                _ -> do
                    baseMsg <- msgToPP $ MsgTrait addremove
                    return $ baseMsg ++ traitmsg
handleTrait _ stmt = preStatement stmt

addRemoveLeaderTrait :: (Monad m, HOI4Info g) => ScriptMessage -> StatementHandler g m
addRemoveLeaderTrait msg stmt@[pdx| %_ = $trait |] = do
    traitloc <- getGameL10n trait
    namemsg <- indentUp $ plainMsg' ("'''" <> traitloc <> "'''")
    traitmsg' <- indentUp $ indentUp $ getLeaderTraits trait
    let traitmsg = namemsg : traitmsg'
    baseMsg <- msgToPP msg
    return $ baseMsg ++ traitmsg
addRemoveLeaderTrait _ stmt = preStatement stmt

addRemoveUnitTrait :: (Monad m, HOI4Info g) => ScriptMessage -> StatementHandler g m
addRemoveUnitTrait msg stmt@[pdx| %_ = $trait |] = do
    traitloc <- getGameL10n trait
    namemsg <- indentUp $ plainMsg' ("'''" <> traitloc <> "'''")
    traitmsg' <- indentUp $ indentUp $ getUnitTraits trait
    let traitmsg = namemsg : traitmsg'
    baseMsg <- msgToPP msg
    return $ baseMsg ++ traitmsg
addRemoveUnitTrait _ stmt = preStatement stmt

data AddTimedTrait = AddTimedTrait
    { adt_trait :: Text
    , adt_days :: Maybe Double
    , adt_daysvar :: Maybe Text
    }

newADT :: AddTimedTrait
newADT = AddTimedTrait undefined Nothing Nothing
addTimedTrait ::  (Monad m, HOI4Info g) => GenericStatement -> PPT g m IndentedMessages
addTimedTrait stmt@[pdx| %_ = @scr |] =
    ppADT (foldl' addLine newADT scr)

    where
        addLine adt [pdx| trait = $txt |] = adt { adt_trait = txt }
        addLine adt [pdx| days = !num |] = adt { adt_days = Just num }
        addLine adt [pdx| days = $txt |] = adt { adt_daysvar = Just txt }
        addLine adt stmt = trace ("Unknown in addTimedTrait: " ++ show stmt) adt
        ppADT adt = do
            traitloc <- getGameL10n (adt_trait adt)
            traitmsg <- indentUp $ getUnitTraits (adt_trait adt)
            baseMsg <- case (adt_days adt, adt_daysvar adt) of
                (Just days,_)-> msgToPP $ MsgAddTimedUnitLeaderTrait traitloc days
                (_, Just daysvar)->msgToPP $ MsgAddTimedUnitLeaderTraitVar traitloc daysvar
                _-> msgToPP $ MsgAddTimedUnitLeaderTraitVar traitloc "<!-- Check Script -->"
            return $ baseMsg ++ traitmsg
addTimedTrait stmt = preStatement stmt


data SwapTrait = SwapTrait
    { st_add :: Text
    , st_remove :: Text
    }

newST :: SwapTrait
newST = SwapTrait undefined undefined
swapLeaderTrait ::  (Monad m, HOI4Info g) => GenericStatement -> PPT g m IndentedMessages
swapLeaderTrait stmt@[pdx| %_ = @scr |] =
    ppST (foldl' addLine newST scr)

    where
        addLine st [pdx| add = $txt |] = st { st_add = txt }
        addLine st [pdx| remove = $txt |] = st { st_remove = txt }
        addLine st stmt = trace ("Unknown in swapTrait: " ++ show stmt) st
        ppST st = do
            traitaddloc <- getGameL10n (st_add st)
            traitremoveloc <- getGameL10n (st_remove st)
            let same = traitaddloc == traitremoveloc
            namemsg <- indentUp $ plainMsg' ("'''" <> traitaddloc <> "'''")
            traitmsg' <- indentUp $ indentUp $ getLeaderTraits (st_add st)
            let traitmsg = namemsg : traitmsg'
            baseMsg <- if same
                then msgToPP MsgModifyCountryLeaderTrait
                else msgToPP $ MsgReplaceCountryLeaderTrait traitremoveloc
            return $ baseMsg ++ traitmsg
swapLeaderTrait stmt = preStatement stmt

getLeaderTraits :: (Monad m, HOI4Info g) => Text -> PPT g m IndentedMessages
getLeaderTraits trait = do
    traits <- getCountryLeaderTraits
    case HM.lookup trait traits of
        Just clt-> do
            mod <- maybe (return []) (\ml -> fmap fold $ traverse (modifierMSG False "") =<< sortmod ml) (clt_modifier clt)
            equipmod <- maybe (return []) handleEquipmentBonus (clt_equipment_bonus clt)
            tarmod <- maybe (return []) (concatMapM handleTargetedModifier) (clt_targeted_modifier clt)
            hidmod <- maybe (return []) handleModifier (clt_hidden_modifier clt)
            return ( mod ++ hidmod ++ tarmod ++ equipmod )
        Nothing -> getUnitTraits trait
    where
        sortmod scr = sortmods scr =<< getModKeys

getUnitTraits :: (Monad m, HOI4Info g) => Text-> PPT g m IndentedMessages
getUnitTraits trait = do
    traits <- getUnitLeaderTraits
    case HM.lookup trait traits of
        Just ult-> do
            attack <- maybe (return []) (msgToPP . MsgAddSkill "Attack") (ult_attack_skill ult)
            defense <- maybe (return []) (msgToPP . MsgAddSkill "Defense") (ult_defense_skill ult)
            planning <- maybe (return []) (msgToPP . MsgAddSkill "Planning") (ult_planning_skill ult)
            logistics <- maybe (return []) (msgToPP . MsgAddSkill "Logistics") (ult_logistics_skill ult)
            maneuvering <- maybe (return []) (msgToPP . MsgAddSkill "Maneuvering") (ult_maneuvering_skill ult)
            coordination <- maybe (return []) (msgToPP . MsgAddSkill "Coordination") (ult_coordination_skill ult)
            let skillmsg = attack ++ defense ++ planning ++ logistics ++ maneuvering ++ coordination
                mod = getscript (ult_modifier ult)
                nsmod = getscript (ult_non_shared_modifier ult)
                ccmod = getscript (ult_corps_commander_modifier ult)
                fmmod = getscript (ult_field_marshal_modifier ult)
            trtxp <- maybe (return []) handleModifier (ult_trait_xp_factor ult)
            mods <- do
                let mods' = mod ++ nsmod ++ ccmod ++ fmmod
                keys <- getModKeys
                sm <- sortmods mods' keys
                fold <$> traverse (modifierMSG False "") sm
            sumod <- maybe (return []) handleEquipmentBonus (ult_sub_unit_modifiers ult)

            return (trtxp ++ mods ++ sumod ++ skillmsg)
        Nothing -> return []
    where
        getscript stmt = case stmt of
            Just [pdx| %_ = @scr|] -> scr
            _ -> []
