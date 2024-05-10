{-|
Module      : HOI4.Settings
Description : Interface for Hearts of Iron IV backend
-}
module HOI4.Settings (
        HOI4 (..)
    ,   module HOI4.Types
    ) where

import Debug.Trace (trace)

import Control.Monad (join, when, forM, filterM, void, unless)
import Control.Monad.Trans (MonadIO (..), liftIO)
import Control.Monad.Reader (MonadReader (..), ReaderT (..), asks)
import Control.Monad.State (MonadState (..), StateT (..), modify, gets)

import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM

import Data.Maybe (listToMaybe)

import System.Directory (getDirectoryContents, doesFileExist, doesDirectoryExist)
import System.FilePath ((</>), isExtensionOf)
import System.IO (hPutStrLn, stderr)

import Abstract -- everything
import FileIO (buildPath, readScript)
import SettingsTypes ( PPT, Settings (..), L10nScheme (..)
                     , IsGame (..), IsGameData (..), IsGameState (..)
                     , getGameL10nIfPresent
                     , safeIndex, safeLast)
import HOI4.Types -- everything
import Yaml (LocEntry (..))

-- Handlers
import HOI4.Decisions (parseHOI4Decisioncats, writeHOI4DecisionCats
                      ,parseHOI4Decisions, writeHOI4Decisions
                      ,findActivatedDecisionsInEvents, findActivatedDecisionsInDecisions
                      ,findActivatedDecisionsInOnActions, findActivatedDecisionsInNationalFocus
                      ,findActivatedDecisionsInIdeas, findActivatedDecisionsInCharacters
                      ,findActivatedDecisionsInScriptedEffects
                      ,findActivatedDecisionsInBops)
import HOI4.Ideas (parseHOI4Ideas
    --, writeHOI4Ideas
    )
import HOI4.Modifiers (
                      parseHOI4OpinionModifiers, writeHOI4OpinionModifiers, writeHOI4OpinionModifiers'
                    , parseHOI4DynamicModifiers, writeHOI4DynamicModifiers
                    , parseHOI4Modifiers)
import HOI4.NationalFocus(parseHOI4NationalFocuses, writeHOI4NationalFocuses)
import HOI4.Events (parseHOI4Events, writeHOI4Events
                   , findTriggeredEventsInEvents, findTriggeredEventsInDecisions
                   , findTriggeredEventsInOnActions, findTriggeredEventsInNationalFocus
                   , findTriggeredEventsInIdeas, findTriggeredEventsInCharacters
                   , findTriggeredEventsInScriptedEffects
                   , findTriggeredEventsInBops)
import HOI4.CharactersAndTraits (parseHOI4Characters, parseHOI4CountryLeaderTraits, parseHOI4UnitLeaderTraits)

import HOI4.TechAndEquipment (parseHOI4TechnologiesPath, writeHOI4Technologies, parseHOI4UnitTags, parseHOI4Units)
import HOI4.Misc (parseHOI4CountryHistory
                 , parseHOI4Terrain, parseHOI4Ideology
                 , parseHOI4Effects, parseHOI4Triggers
                 , parseHOI4BopRanges, parseHOI4ModifierDefinitions
                 , parseHOI4LocKeys)

-- | Temporary (?) fix for CHI and PRC both localizing to "China"
-- Can be extended/removed as necessary
fixLocalization :: Settings -> Settings
fixLocalization s =
    let
        lan  = language s
        l10n = gameL10n s
        l10nForLan = HM.findWithDefault HM.empty lan l10n
        findKey key = content $ HM.findWithDefault (LocEntry 0 key) key l10nForLan
        chiLoc = findKey "CHI"
        newHavLoc = chiLoc <> " (CHI)"
        newL10n = HM.insert "CHI" (LocEntry 0 newHavLoc) l10nForLan
    in
        if chiLoc == findKey "PRC" then
            trace ("Note: Applying localization fix for CHI/PRC: " ++ show chiLoc ++ " -> " ++ show newHavLoc) $
                s { gameL10n = HM.insert lan newL10n l10n }
        else
            trace "Warning: fixLocalization hack for CHI/PRC in HOI4/Settings.hs no longer needed!" s

-- | HOI4 game type. This is only interesting for its instances.
data HOI4 = HOI4
instance IsGame HOI4 where
    locScheme _  = L10nQYAML
    readScripts  = readHOI4Scripts
    parseScripts = parseHOI4Scripts
    writeScripts = writeHOI4Scripts
    data GameData HOI4 = HOI4D { hoi4d :: HOI4Data }
    data GameState HOI4 = HOI4S { hoi4s :: HOI4State }
    runWithInitState HOI4 settings st =
        void (runReaderT
                (runStateT st (HOI4D $ HOI4Data {
                    hoi4settings = fixLocalization settings
                ,   hoi4events = HM.empty
                ,   hoi4eventScripts = HM.empty
                ,   hoi4decisioncatScripts = HM.empty
                ,   hoi4decisioncats = HM.empty
                ,   hoi4decisions = HM.empty
                ,   hoi4decisionScripts = HM.empty
                ,   hoi4ideas = HM.empty
                ,   hoi4ideaScripts = HM.empty
                ,   hoi4opmods = HM.empty
                ,   hoi4opmodScripts = HM.empty
                ,   hoi4eventTriggers = HM.empty
                ,   hoi4decisionTriggers = HM.empty
                ,   hoi4onactionsScripts = HM.empty
                ,   hoi4dynamicmodifiers = HM.empty
                ,   hoi4dynamicmodifierScripts = HM.empty
                ,   hoi4modifiers = HM.empty
                ,   hoi4modifierScripts = HM.empty
                ,   hoi4nationalfocusScripts = HM.empty
                ,   hoi4nationalfocus = HM.empty
                ,   hoi4countryHistory = HM.empty
                ,   hoi4countryHistoryScripts = HM.empty
                ,   hoi4characterScripts = HM.empty
                ,   hoi4characters = HM.empty
                ,   hoi4countryleadertraitScripts = HM.empty
                ,   hoi4countryleadertraits = HM.empty
                ,   hoi4unitleadertraitScripts = HM.empty
                ,   hoi4unitleadertraits = HM.empty
                ,   hoi4terrainScripts = HM.empty
                ,   hoi4terrain = []
                ,   hoi4unittagScripts = HM.empty
                ,   hoi4unittag = []
                ,   hoi4unitScripts = HM.empty
                ,   hoi4unit = []
                ,   hoi4ideologyScripts = HM.empty
                ,   hoi4ideology = HM.empty
                ,   hoi4chartoken = HM.empty

                ,   hoi4scriptedeffectScripts = HM.empty
                ,   hoi4scriptedeffects = HM.empty
                ,   hoi4scriptedtriggerScripts = HM.empty
                ,   hoi4scriptedtriggers = HM.empty
                ,   hoi4modifierdefinitionScripts = HM.empty
                ,   hoi4modifierdefinitions = HM.empty
                ,   hoi4bopScripts = HM.empty
                ,   hoi4bops = HM.empty
                ,   hoi4techScripts = HM.empty
                ,   hoi4techs = HM.empty
                ,   hoi4lockeys = []
                ,   hoi4modkeys = []

                -- unused
                ,   hoi4extraScripts = HM.empty
                ,   hoi4extraScriptsCountryScope = HM.empty
                ,   hoi4extraScriptsProvinceScope = HM.empty
                ,   hoi4extraScriptsModifier = HM.empty
                }))
                (HOI4S $ HOI4State {
                    hoi4currentFile = Nothing
                ,   hoi4currentIndent = Nothing
                ,   hoi4scopeStack = []
                ,   hoi4IsInEffect = False
                }))
    type Scope HOI4 = HOI4Scope
    scope s = local $ \(HOI4S st) -> HOI4S $
        st { hoi4scopeStack = s : hoi4scopeStack st }
    getCurrentScope = asks $ listToMaybe . hoi4scopeStack . hoi4s
    getPrevScope = asks $ safeIndex 1 . hoi4scopeStack . hoi4s
    getPrevScopeCustom i = asks $ safeIndex i . hoi4scopeStack . hoi4s
    getRootScope = asks $ safeLast . hoi4scopeStack . hoi4s
    getScopeStack = asks $ hoi4scopeStack . hoi4s
    getIsInEffect = asks $ hoi4IsInEffect . hoi4s
    setIsInEffect b = local $ \(HOI4S st) -> HOI4S $ st { hoi4IsInEffect = b }

instance HOI4Info HOI4 where
    getEventTitle eid = do
        HOI4D ed <- get
        let evts = hoi4events ed
            mevt = HM.lookup eid evts
        case mevt of
            Nothing -> return Nothing
            Just evt -> case hoi4evt_title evt of
                [] -> return Nothing
                [HOI4EvtTitleSimple key] -> getGameL10nIfPresent key
                _titles -> return Nothing
    getEventScripts = do
        HOI4D ed <- get
        return (hoi4eventScripts ed)
    setEventScripts scr = modify $ \(HOI4D ed) -> HOI4D $ ed {
            hoi4eventScripts = scr
        }
    getEvents = do
        HOI4D ed <- get
        return (hoi4events ed)
    getIdeaScripts = do
        HOI4D ed <- get
        return (hoi4ideaScripts ed)
    getIdeas = do
        HOI4D ed <- get
        return (hoi4ideas ed)
    getDecisioncatScripts = do
        HOI4D ed <- get
        return (hoi4decisioncatScripts ed)
    getDecisionScripts = do
        HOI4D ed <- get
        return (hoi4decisionScripts ed)
    getDecisioncats = do
        HOI4D ed <- get
        return (hoi4decisioncats ed)
    getDecisions = do
        HOI4D ed <- get
        return (hoi4decisions ed)
    getOpinionModifierScripts = do
        HOI4D ed <- get
        return (hoi4opmodScripts ed)
    getOpinionModifiers = do
        HOI4D ed <- get
        return (hoi4opmods ed)
    getEventTriggers = do
        HOI4D ed <- get
        return (hoi4eventTriggers ed)
    getDecisionTriggers = do
        HOI4D ed <- get
        return (hoi4decisionTriggers ed)
    getOnActionsScripts = do
        HOI4D ed <- get
        return (hoi4onactionsScripts ed)
    getDynamicModifierScripts = do
        HOI4D ed <- get
        return (hoi4dynamicmodifierScripts ed)
    getDynamicModifiers = do
        HOI4D ed <- get
        return (hoi4dynamicmodifiers ed)
    getModifierScripts = do
        HOI4D ed <- get
        return (hoi4modifierScripts ed)
    getModifiers = do
        HOI4D ed <- get
        return (hoi4modifiers ed)
    getNationalFocusScripts = do
        HOI4D ed <- get
        return (hoi4nationalfocusScripts ed)
    getNationalFocus = do
        HOI4D ed <- get
        return (hoi4nationalfocus ed)

    getCountryHistoryScripts = do
        HOI4D ed <- get
        return (hoi4countryHistoryScripts ed)
    getCountryHistory = do
        HOI4D ed <- get
        return (hoi4countryHistory ed)
    getCharacterScripts = do
        HOI4D ed <- get
        return (hoi4characterScripts ed)
    getCharacters = do
        HOI4D ed <- get
        return (hoi4characters ed)
    getCountryLeaderTraitScripts = do
        HOI4D ed <- get
        return (hoi4countryleadertraitScripts ed)
    getCountryLeaderTraits = do
        HOI4D ed <- get
        return (hoi4countryleadertraits ed)
    getUnitLeaderTraitScripts = do
        HOI4D ed <- get
        return (hoi4unitleadertraitScripts ed)
    getUnitLeaderTraits = do
        HOI4D ed <- get
        return (hoi4unitleadertraits ed)
    getTerrainScripts = do
        HOI4D ed <- get
        return (hoi4terrainScripts ed)
    getTerrain = do
        HOI4D ed <- get
        return (hoi4terrain ed)
    getUnitTagScripts = do
        HOI4D ed <- get
        return (hoi4unittagScripts ed)
    getUnitTag = do
        HOI4D ed <- get
        return (hoi4unittag ed)
    getUnitScripts = do
        HOI4D ed <- get
        return (hoi4unitScripts ed)
    getUnit = do
        HOI4D ed <- get
        return (hoi4unit ed)
    getIdeologyScripts = do
        HOI4D ed <- get
        return (hoi4ideologyScripts ed)
    getIdeology = do
        HOI4D ed <- get
        return (hoi4ideology ed)
    getCharToken = do
        HOI4D ed <- get
        return (hoi4chartoken ed)
    getScriptedEffectScripts = do
        HOI4D ed <- get
        return (hoi4scriptedeffectScripts ed)
    getScriptedEffects = do
        HOI4D ed <- get
        return (hoi4scriptedeffects ed)
    getScriptedTriggerScripts = do
        HOI4D ed <- get
        return (hoi4scriptedtriggerScripts ed)
    getScriptedTriggers = do
        HOI4D ed <- get
        return (hoi4scriptedtriggers ed)
    getModifierDefintionScripts = do
        HOI4D ed <- get
        return (hoi4modifierdefinitionScripts ed)
    getModifierDefinitions = do
        HOI4D ed <- get
        return (hoi4modifierdefinitions ed)
    getBopScripts = do
        HOI4D ed <- get
        return (hoi4bopScripts ed)
    getBops = do
        HOI4D ed <- get
        return (hoi4bops ed)
    getTechnologyScripts = do
        HOI4D ed <- get
        return (hoi4techScripts ed)
    getTechnologies = do
        HOI4D ed <- get
        return (hoi4techs ed)
    getLocKeys = do
        HOI4D ed <- get
        return (hoi4lockeys ed)
    getModKeys = do
        HOI4D ed <- get
        return (hoi4modkeys ed)
-- unused
    getExtraScripts = do
        HOI4D ed <- get
        return (hoi4extraScripts ed)
    getExtraScriptsCountryScope = do
        HOI4D ed <- get
        return (hoi4extraScriptsCountryScope ed)
    getExtraScriptsProvinceScope = do
        HOI4D ed <- get
        return (hoi4extraScriptsProvinceScope ed)
    getExtraScriptsModifier = do
        HOI4D ed <- get
        return (hoi4extraScriptsModifier ed)

instance IsGameData (GameData HOI4) where
    getSettings (HOI4D ed) = hoi4settings ed

instance IsGameState (GameState HOI4) where
    currentFile (HOI4S es) = hoi4currentFile es
    modifyCurrentFile cf (HOI4S es) = HOI4S $ es {
            hoi4currentFile = cf
        }
    currentIndent (HOI4S es) = hoi4currentIndent es
    modifyCurrentIndent ci (HOI4S es) = HOI4S $ es {
            hoi4currentIndent = ci
        }

-- | Read all scripts in a directory.
--
-- Return: for each file, its path relative to the game root and the parsed
--         script.
readHOI4Scripts :: forall m. MonadIO m => PPT HOI4 m ()
readHOI4Scripts = do
    settings <- gets getSettings
    let readOneScript :: String -> String -> PPT HOI4 m (String, GenericScript)
        readOneScript category target = do
            content <- liftIO $ readScript settings target
            --traceM (show target)
            when (null content) $
                liftIO $ hPutStrLn stderr $
                    "Warning: " ++ target
                        ++ " contains no scripts - failed parse? Expected feature type "
                        ++ category
            return (target, content)

        readHOI4Script :: String -> PPT HOI4 m (HashMap String GenericScript)
        readHOI4Script category = do
            let sourceSubdir = case category of
                    "ideas" -> "common" </> "ideas"
                    "opinion_modifiers" -> "common" </> "opinion_modifiers"
                    "on_actions" -> "common" </> "on_actions"
                    "dynamic_modifiers" -> "common" </> "dynamic_modifiers"
                    "modifiers" -> "common" </> "modifiers"
                    "decisions" -> "common" </> "decisions"
                    "decisioncats" -> "common" </> "decisions" </> "categories"
                    "national_focus" -> "common" </> "national_focus"

                    "country_history" -> "history" </> "countries"
                    "characters" -> "common" </> "characters"
                    "country_leader_trait" -> "common" </> "country_leader"
                    "unit_leader_trait" -> "common" </> "unit_leader"
                    "terrain" -> "common" </> "terrain"
                    "unit_tags" -> "common" </> "unit_tags"
                    "units" -> "common" </> "units"
                    "ideology" -> "common" </> "ideologies"
                    "scripted_effect" -> "common" </> "scripted_effects"
                    "scripted_trigger" -> "common" </> "scripted_triggers"
                    "modifier_definitions" -> "common" </> "modifier_definitions"
                    "bop" -> "common" </> "bop"
                    "technologies" -> "common" </> "technologies"
                    _          -> category
                sourceDir = buildPath settings sourceSubdir
            direxist <- liftIO $ doesDirectoryExist sourceDir
            if direxist
            then do
                files <- liftIO (filterM (doesFileExist . buildPath settings . (sourceSubdir </>))
                                    =<< filterM (pure . isExtensionOf ".txt")
                                     =<< getDirectoryContents sourceDir)
                results <- forM files $ \filename -> readOneScript category (sourceSubdir </> filename)
                return $ foldl (flip (uncurry HM.insert)) HM.empty results
            else return $ trace ("WARNING: Unable to find " ++ show sourceDir) HM.empty
    ideasScripts <- readHOI4Script "ideas"
    decisioncats <- readHOI4Script "decisioncats"
    decisions <- readHOI4Script "decisions"
    events <- readHOI4Script "events"
    opinion_modifiers <- readHOI4Script "opinion_modifiers"
    on_actions <- readHOI4Script "on_actions"
    dynamic_modifiers <- readHOI4Script "dynamic_modifiers"
    modifiers <- readHOI4Script "modifiers"
    national_focus <- readHOI4Script "national_focus"

    country_history <- readHOI4Script "country_history"
    characterScripts <- readHOI4Script "characters"
    countryleadertraitScripts <- readHOI4Script "country_leader_trait"
    unitleadertraitScripts <- readHOI4Script "unit_leader_trait"

    terrainScripts <- readHOI4Script "terrain"
    unittagScripts <- readHOI4Script "unit_tags"
    unitScripts <- readHOI4Script "units"
    ideologyScripts <- readHOI4Script "ideology"

    scripted_effects <- readHOI4Script "scripted_effect"
    scripted_triggers <- readHOI4Script "scripted_trigger"

    moddefs <- readHOI4Script "modifier_definitions"
    bopscript <- readHOI4Script "bop"
    techscript <- readHOI4Script "technologies"
    lockeys <- gets (gameL10nKeys . getSettings)

    modify $ \(HOI4D s) -> HOI4D $ s {
            hoi4ideaScripts = ideasScripts
        ,   hoi4decisioncatScripts = decisioncats
        ,   hoi4decisionScripts = decisions
        ,   hoi4eventScripts = events
        ,   hoi4opmodScripts = opinion_modifiers
        ,   hoi4onactionsScripts = on_actions
        ,   hoi4dynamicmodifierScripts = dynamic_modifiers
        ,   hoi4modifierScripts = modifiers
        ,   hoi4countryHistoryScripts = country_history

        ,   hoi4nationalfocusScripts = national_focus
        ,   hoi4characterScripts = characterScripts
        ,   hoi4countryleadertraitScripts = countryleadertraitScripts
        ,   hoi4unitleadertraitScripts = unitleadertraitScripts

        ,   hoi4terrainScripts = terrainScripts
        ,   hoi4unittagScripts = unittagScripts
        ,   hoi4unitScripts = unitScripts
        ,   hoi4ideologyScripts = ideologyScripts

        ,   hoi4scriptedeffectScripts = scripted_effects
        ,   hoi4scriptedtriggerScripts = scripted_triggers

        ,   hoi4modifierdefinitionScripts = moddefs

        ,   hoi4bopScripts = bopscript
        ,   hoi4techScripts = techscript
        ,   hoi4lockeys = lockeys
        }


-- | Interpret the script ASTs as usable data.
parseHOI4Scripts :: Monad m => PPT HOI4 m ()
parseHOI4Scripts = do
    -- Need idea groups and modifiers before everything else
    ideas <- parseHOI4Ideas =<< getIdeaScripts
    opinionModifiers <- parseHOI4OpinionModifiers =<< getOpinionModifierScripts
    dynamicModifiers <- parseHOI4DynamicModifiers =<< getDynamicModifierScripts
    modifiers <- parseHOI4Modifiers =<< getModifierScripts
    decisioncats <- parseHOI4Decisioncats =<< getDecisioncatScripts
    decisions <- parseHOI4Decisions =<< getDecisionScripts
    events <- parseHOI4Events =<< getEventScripts
    on_actions <- getOnActionsScripts
    nationalFocus <- parseHOI4NationalFocuses =<< getNationalFocusScripts

    countryHistory <- parseHOI4CountryHistory =<< getCountryHistoryScripts
    (characters, chartoken) <- parseHOI4Characters =<< getCharacterScripts
    countryleadertraits <- parseHOI4CountryLeaderTraits =<< getCountryLeaderTraitScripts
    unitleadertraits <- parseHOI4UnitLeaderTraits =<< getUnitLeaderTraitScripts
    terrain <- parseHOI4Terrain =<< getTerrainScripts
    unittag <- parseHOI4UnitTags =<< getUnitTagScripts
    unit <- parseHOI4Units =<< getUnitScripts
    ideology <- parseHOI4Ideology =<< getIdeologyScripts
    scriptedeffects <- parseHOI4Effects =<< getScriptedEffectScripts
    scriptedtriggers <- parseHOI4Triggers =<< getScriptedTriggerScripts
    moddef <- parseHOI4ModifierDefinitions =<< getModifierDefintionScripts
    bops <- parseHOI4BopRanges =<< getBopScripts
    techspathed <- parseHOI4TechnologiesPath =<< getTechnologyScripts
    modkeys <- parseHOI4LocKeys =<< getLocKeys

    let te1 = findTriggeredEventsInEvents HM.empty (HM.elems events)
        te2 = findTriggeredEventsInDecisions te1 (HM.elems decisions)
        te3 = findTriggeredEventsInOnActions te2 (concat (HM.elems on_actions))
        te4 = findTriggeredEventsInNationalFocus te3 (HM.elems nationalFocus)
        te5 = findTriggeredEventsInIdeas te4 (HM.elems ideas)
        te6 = findTriggeredEventsInCharacters te5 (HM.elems chartoken)
        te7 = findTriggeredEventsInScriptedEffects te6 (HM.elems scriptedeffects)
        te8 = findTriggeredEventsInBops te7 (HM.elems bops)
    let td1 = findActivatedDecisionsInEvents HM.empty (HM.elems events)
        td2 = findActivatedDecisionsInDecisions td1 (HM.elems decisions)
        td3 = findActivatedDecisionsInOnActions td2 (concat (HM.elems on_actions))
        td4 = findActivatedDecisionsInNationalFocus td3 (HM.elems nationalFocus)
        td5 = findActivatedDecisionsInIdeas td4 (HM.elems ideas)
        td6 = findActivatedDecisionsInCharacters td5 (HM.elems chartoken)
        td7 = findActivatedDecisionsInScriptedEffects td6 (HM.elems scriptedeffects)
        td8 = findActivatedDecisionsInBops td7 (HM.elems bops)
    modify $ \(HOI4D s) -> HOI4D $
            s { hoi4events = events
            ,   hoi4decisioncats = decisioncats
            ,   hoi4decisions = decisions
            ,   hoi4ideas = ideas
            ,   hoi4opmods = opinionModifiers
            ,   hoi4nationalfocus = nationalFocus
            ,   hoi4eventTriggers = te8
            ,   hoi4decisionTriggers = td8
            ,   hoi4dynamicmodifiers = dynamicModifiers
            ,   hoi4modifiers = modifiers

            ,   hoi4countryHistory = countryHistory
            ,   hoi4characters = characters
            ,   hoi4countryleadertraits = countryleadertraits
            ,   hoi4unitleadertraits = unitleadertraits
            ,   hoi4chartoken = chartoken

            ,   hoi4terrain = terrain
            ,   hoi4unittag = unittag
            ,   hoi4unit = unit
            ,   hoi4ideology = ideology

            ,   hoi4scriptedeffects = scriptedeffects
            ,   hoi4scriptedtriggers = scriptedtriggers

            ,   hoi4modifierdefinitions = moddef
            ,   hoi4bops = bops
            ,   hoi4techs = techspathed
            ,   hoi4modkeys = modkeys
            }

-- | Output the game data as wiki text.
writeHOI4Scripts :: (HOI4Info g, MonadIO m) => PPT g m ()
writeHOI4Scripts = do
--        liftIO $ putStrLn "Writing ideas."
--        writeHOI4Ideas
        liftIO $ putStrLn "Writing events."
        writeHOI4Events
        liftIO $ putStrLn "Writing decision categories."
        writeHOI4DecisionCats
        liftIO $ putStrLn "Writing decisions."
        writeHOI4Decisions
        liftIO $ putStrLn "Writing national focuses."
        writeHOI4NationalFocuses
        liftIO $ putStrLn "Writing technologies."
        writeHOI4Technologies
        liftIO $ putStrLn "Writing opinion modifiers."
        writeHOI4OpinionModifiers
--        writeHOI4OpinionModifiers'
        liftIO $ putStrLn "Writing dynamic modifiers."
        writeHOI4DynamicModifiers
