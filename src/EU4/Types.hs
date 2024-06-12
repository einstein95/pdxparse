{-|
Module      : EU4.Types
Description : Types specific to Europa Universalis IV
-}
module EU4.Types (
        -- * Parser state
        EU4Data (..), EU4State (..)
    ,   EU4Info (..)
        -- * Features
    ,   EU4EvtDesc (..), EU4Event (..), EU4Option (..)
    ,   EU4EventSource (..), EU4EventTriggers, EU4EventWeight
    ,   EU4Decision (..)
    ,   IdeaGroup (..), Idea (..), IdeaTable
    ,   EU4Modifier (..), EU4OpinionModifier (..)
    ,   EU4MissionTreeBranch (..), EU4Mission (..)
    ,   EU4ProvinceTriggeredModifier (..)
    ,   EU4EstateAction (..)
    ,   EU4Scripted (..)
        -- * Low level types
    ,   MonarchPower (..)
    ,   EU4Scope (..)
    ,   AIWillDo (..)
    ,   AIModifier (..)
    ,   EU4GeoType (..)
    ,   aiWillDo
    ,   isGeographic
    -- utilities that can't go anywhere else
    ,   getModifier
    ) where

import Data.List (foldl')
import Data.Text (Text)
import qualified Data.Text as T
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.Hashable (Hashable)
import GHC.Generics (Generic)

import Abstract -- everything
import QQ (pdx)
import SettingsTypes ( PPT, Settings
                     , IsGame (..), IsGameData (..), IsGameState (..))
--import Doc

--------------------------------------------
-- Types used by toplevel Settings module --
--------------------------------------------

-- | Settings, raw scripts, and parsed scripts.
data EU4Data = EU4Data {
        eu4settings :: Settings
    ,   eu4events :: HashMap Text EU4Event
    ,   eu4decisions :: HashMap Text EU4Decision
    ,   eu4ideaGroups :: IdeaTable
    ,   eu4modifiers :: HashMap Text EU4Modifier
    ,   eu4opmods :: HashMap Text EU4OpinionModifier
    ,   eu4missions :: HashMap Text EU4MissionTreeBranch
    ,   eu4eventTriggers :: EU4EventTriggers
    ,   eu4genericScriptsForEventTriggers :: HashMap String GenericScript
    ,   eu4geoData :: HashMap Text EU4GeoType
    ,   eu4provtrigmodifiers :: HashMap Text EU4ProvinceTriggeredModifier
    ,   eu4eventScripts :: HashMap FilePath GenericScript
    ,   eu4decisionScripts :: HashMap FilePath GenericScript
    ,   eu4ideaGroupScripts :: HashMap FilePath GenericScript
    ,   eu4modifierScripts :: HashMap FilePath GenericScript
    ,   eu4opmodScripts :: HashMap FilePath GenericScript
    ,   eu4missionScripts :: HashMap FilePath GenericScript
    ,   eu4provtrigmodifierScripts :: HashMap FilePath GenericScript
    ,   eu4scriptedEffectScripts :: HashMap FilePath GenericScript
    ,   eu4scriptedEffects :: HashMap Text EU4Scripted
    ,   eu4tradeNodes :: HashMap Int Text -- Province Id -> Non localized provice name
    ,   eu4estateActions :: HashMap Text EU4EstateAction -- the key is the internal name of an estate action (e.g. RECRUIT_MINISTER_BRAHMINS)
    ,   eu4scriptedEffectsForEstates :: Text -- the contents of common/scripted_effects/01_scripted_effects_for_estates.txt
    ,   eu4extraScripts :: HashMap FilePath GenericScript -- Extra scripts parsed on the command line
    ,   eu4extraScriptsCountryScope :: HashMap FilePath GenericScript -- Extra scripts parsed on the command line
    ,   eu4extraScriptsProvinceScope :: HashMap FilePath GenericScript -- Extra scripts parsed on the command line
    ,   eu4extraScriptsModifier :: HashMap FilePath GenericScript -- Extra scripts parsed on the command line
    -- etc.
    }

-- | State type for EU4.
data EU4State = EU4State {
        eu4scopeStack :: [EU4Scope]
    ,   eu4currentFile :: Maybe FilePath
    ,   eu4currentIndent :: Maybe Int
    ,   eu4IsInEffect :: Bool
    } deriving (Show)

-- | Interface for EU4 feature handlers. Most of the methods just get data
-- tables from the parser state. These are empty until the relevant parsing
-- stages have been done. In order to avoid import loops, handlers don't know
-- the 'EU4.Settings.EU4' type itself, only its instances.
class (IsGame g,
       Scope g ~ EU4Scope,
       IsGameData (GameData g),
       IsGameState (GameState g)) => EU4Info g where
    -- | Get the title of an event by its ID. Only works if event scripts have
    -- been parsed.
    getEventTitle :: Monad m => Text -> PPT g m (Maybe Text)
    -- | Get the contents of all event script files.
    getEventScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    -- | Save (or amend) the contents of script event files in state.
    setEventScripts :: Monad m => HashMap FilePath GenericScript -> PPT g m ()
    -- | Get the parsed events table (keyed on event ID).
    getEvents :: Monad m => PPT g m (HashMap Text EU4Event)
    -- | Get the contents of all idea groups files.
    getIdeaGroupScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    -- | Get the parsed idea groups table (keyed on idea group ID).
    getIdeaGroups :: Monad m => PPT g m IdeaTable
    -- | Get the contents of all modifier script files.
    getModifierScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    -- | Get the parsed modifiers table (keyed on modifier ID).
    getModifiers :: Monad m => PPT g m (HashMap Text EU4Modifier)
    -- | Get the contents of all opinion modifier script files.
    getOpinionModifierScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    -- | Get the parsed opinion modifiers table (keyed on modifier ID).
    getOpinionModifiers :: Monad m => PPT g m (HashMap Text EU4OpinionModifier)
    -- | Get the contents of all decision script files.
    getDecisionScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    -- | Get the parsed decisions table (keyed on decision ID).
    getDecisions :: Monad m => PPT g m (HashMap Text EU4Decision)
    -- | Get the contents of all mission script files
    getMissionScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    -- | Get the parsed mission trees
    getMissions :: Monad m => PPT g m (HashMap Text EU4MissionTreeBranch)
    -- | Get the (known) event triggers
    getEventTriggers :: Monad m => PPT g m EU4EventTriggers
    -- | Scripts from otherwise unparsed locations which can trigger events
    getGenericScriptsForEventTriggers :: Monad m => PPT g m (HashMap String GenericScript)
    -- | Get the parsed geographic data
    getGeoData :: Monad m => PPT g m (HashMap Text EU4GeoType)
    -- | Get the contents of all province triggered modifier script files.
    getProvinceTriggeredModifierScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    -- | Get the parsed province triggered modifiers table (keyed on modifier ID).
    getProvinceTriggeredModifiers :: Monad m => PPT g m (HashMap Text EU4ProvinceTriggeredModifier)
    -- | Get the contents of all scripted effects script files.
    -- getScriptedEffectScripts :: Monad m => PPT g m (HashMap FilePath (Script Text Void))
    getScriptedEffectScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    -- | get the names of scripted effects
    getScriptedEffects :: Monad m => PPT g m (HashMap Text EU4Scripted)
    setScriptedEffects :: Monad m => HashMap Text EU4Scripted -> PPT g m ()
    -- | Get the trade nodes
    getTradeNodes :: Monad m => PPT g m (HashMap Int Text)
    -- | Get the decisions which enact estate actions
    getEstateActions :: Monad m => PPT g m (HashMap Text EU4EstateAction)
    -- | Get the contents of the file common/scripted_effects/01_scripted_effects_for_estates.txt which can't be parsed normally
    getScriptedEffectsForEstates :: Monad m => PPT g m Text
    -- | Get extra scripts parsed from command line arguments
    getExtraScripts :: Monad m => PPT g m (HashMap FilePath GenericScript)
    getExtraScriptsCountryScope :: Monad m => PPT g m (HashMap FilePath GenericScript)
    getExtraScriptsProvinceScope :: Monad m => PPT g m (HashMap FilePath GenericScript)
    getExtraScriptsModifier :: Monad m => PPT g m (HashMap FilePath GenericScript)

-------------------
-- Feature types --
-------------------

-- | Event description type. As of EU4 1.17, descriptions may be conditional.
data EU4EvtDesc
    = EU4EvtDescSimple Text  -- desc = key
    | EU4EvtDescConditional GenericScript Text
            -- desc = { text = key trigger = conditions }
    | EU4EvtDescCompound GenericScript
            -- desc = { trigger = { conditional_expressions } }
    deriving (Show)

-- | Event data.
data EU4Event = EU4Event {
    -- | Event ID
        eu4evt_id :: Maybe Text
    -- | Event title l10n key
    ,   eu4evt_title :: Maybe Text
    -- | Description
    ,   eu4evt_desc :: [EU4EvtDesc]
--  -- | Event picture
--  ,   eu4evt_picture :: Maybe Text
    -- | Type of thing the event happens to (e.g.  for a @country_event@ this
    -- is 'EU4Country'). This is used to set the top level scope for its
    -- scripts.
    ,   eu4evt_scope :: EU4Scope
    -- | What conditions allow the event to trigger.
    ,   eu4evt_trigger :: Maybe GenericScript
    -- | Whether the event is only triggered by script commands. If this is
    -- @False@ and the event also has a @mean_time_to_happen@, it can happen
    -- randomly.
    ,   eu4evt_is_triggered_only :: Maybe Bool
    -- | If this is a random event, how unlikely this event is to happen.
    ,   eu4evt_mean_time_to_happen :: Maybe GenericScript
    -- | Commands to execute as soon as the event fires.
    ,   eu4evt_immediate :: Maybe GenericScript
    -- | Whether this is a hidden event (it will have no options).
    ,   eu4evt_hide_window :: Bool
    -- | Whether this event can only happen once per campaign
    ,   eu4evt_fire_only_once :: Bool
    -- | List of options for the player/AI to choose from.
    ,   eu4evt_options :: Maybe [EU4Option]
    -- | Effects that take place after any option is selected.
    ,   eu4evt_after :: Maybe GenericScript
    -- | The event's source file.
    ,   eu4evt_path :: FilePath
    } deriving (Show)
-- | Event option data.
data EU4Option = EU4Option
    {   eu4opt_name :: Maybe Text               -- ^ Text of the option
    ,   eu4opt_trigger :: Maybe GenericScript   -- ^ Condition for the option to be available
    ,   eu4opt_ai_chance :: Maybe GenericScript -- ^ Probability that the AI will choose this option
    ,   eu4opt_effects :: Maybe GenericScript   -- ^ What happens if the player/AI chooses this option
    } deriving (Show)

type EU4EventWeight = Maybe (Integer, Integer) -- Rational reduces the number, which we don't want

data EU4EventSource =
      EU4EvtSrcImmediate Text                       -- Immediate effect of an event (arg is event ID)
    | EU4EvtSrcAfter Text                           -- After effect of an event (arg is event ID)
    | EU4EvtSrcOption Text Text                     -- Effect of choosing an event option (args are event ID and option ID)
    | EU4EvtSrcDecision Text Text                   -- Effect of taking a decision (args are id and localized decision text)
    | EU4EvtSrcOnAction Text EU4EventWeight         -- An effect from on_actions (args are the trigger and weight)
    | EU4EvtSrcDisaster Text Text EU4EventWeight    -- Effect of a disaster (args are id, trigger and weight)
    | EU4EvtSrcMission Text                         -- Effect of completing a mission (arg is the mission id)
    | EU4EvtSrcGovernmentMechanic Text Text Text    -- Effect of a government mechanic (args are id, section id, trigger)
    | EU4EvtSrcGeneric Text Text                    -- Some generic triggers (args are id and trigger)
    deriving Show

type EU4EventTriggers = HashMap Text [EU4EventSource]

-- | Table of idea groups, keyed by ID (e.g. @administrative_ideas@).
type IdeaTable = HashMap Text IdeaGroup
-- | Idea group data.
data IdeaGroup = IdeaGroup
    {   ig_name :: Text -- ^ Name of the idea group
    ,   ig_name_loc :: Text -- ^ Localized name of the idea group (in the best language)
    ,   ig_category :: Maybe MonarchPower -- ^ Which type of monarch power is used to buy these ideas
    ,   ig_start :: Maybe GenericScript -- ^ Traditions for a country idea group
    ,   ig_bonus :: Maybe GenericScript -- ^ Finisher / ambitions
    ,   ig_trigger :: Maybe GenericScript -- ^ Availability conditions if any
    ,   ig_free :: Bool -- ^ Whether this is a country idea group
    ,   ig_ideas :: [Idea] -- ^ List of ideas (there should always be 7)
    ,   ig_ai_will_do :: Maybe AIWillDo -- ^ Factors affecting whether AI will choose this group
    ,   ig_path :: Maybe FilePath -- ^ Source file
    } deriving (Show)
-- | Idea data.
data Idea = Idea
    {   idea_name :: Text -- ^ Idea ID
    ,   idea_name_loc :: Text -- ^ Localized idea name
    ,   idea_effects :: GenericScript -- ^ Idea effects (bonus scope)
    } deriving (Show)

-- | Decision data.
data EU4Decision = EU4Decision
    {   dec_name :: Text -- ^ Decision ID
    ,   dec_name_loc :: Text -- ^ Localized decision name
    ,   dec_text :: Maybe Text -- ^ Descriptive text (shown on hover)
    ,   dec_potential :: GenericScript -- ^ Conditions governing whether a
                                       --   decision shows up in the list
    ,   dec_allow :: GenericScript -- ^ Conditions that allow the player/AI to
                                   --   take the decision
    ,   dec_effect :: GenericScript -- ^ Effect on taking the decision
    ,   dec_ai_will_do :: Maybe AIWillDo -- ^ Factors affecting whether an AI
                                         --   will take the decision when available
    ,   dec_path :: Maybe FilePath -- ^ Source file
    } deriving (Show)

data EU4Modifier = EU4Modifier
    {   modName :: Text
    ,   modLocName :: Maybe Text
    ,   modPath :: FilePath
    ,   modReligious :: Bool
    ,   modEffects :: GenericScript
    } deriving (Show)

data EU4ProvinceTriggeredModifier = EU4ProvinceTriggeredModifier
    {   ptmodName :: Text
    ,   ptmodLocName :: Maybe Text
    ,   ptmodPath :: FilePath
    ,   ptmodEffects :: GenericScript        -- The modifier to apply when the triggered modifier is active
    ,   ptmodPotential :: GenericScript      -- Whether the triggered modifier is visible in the Province view window
    ,   ptmodTrigger :: GenericScript        -- Whether the triggered modifier is active
    ,   ptmodOnActivation :: GenericScript   -- Effects to execute when the triggered modifiers switches to active (province scope)
    ,   ptmodOnDeactivation :: GenericScript -- Effects to execute when the triggered modifiers switches to inactive
    } deriving (Show)

data EU4OpinionModifier = EU4OpinionModifier
    {   omodName :: Text
    ,   omodLocName :: Maybe Text
    ,   omodPath :: FilePath
    ,   omodOpinion :: Maybe Double
    ,   omodMax :: Maybe Double
    ,   omodMin :: Maybe Double
    ,   omodYearlyDecay :: Maybe Double
    ,   omodMonths :: Maybe Double
    ,   omodYears :: Maybe Double
    ,   omodMaxVassal :: Maybe Double
    ,   omodMaxInOtherDirection :: Maybe Double
    } deriving (Show)

data EU4Mission = EU4Mission
    {   eu4m_id :: Text
    ,   eu4m_icon :: Text
    ,   eu4m_slot :: Int -- Which column (1..5) does the mission tree branch appear in?
    ,   eu4m_position :: Int -- Which row the mission appears in. 1 is top.
    ,   eu4m_prerequisites :: [Text]
    ,   eu4m_trigger :: GenericScript
    ,   eu4m_effect :: GenericScript
    } deriving (Show)

data EU4MissionTreeBranch = EU4MissionTreeBranch
    {   eu4mtb_path :: FilePath
    ,   eu4mtb_id :: Text
    ,   eu4mtb_slot :: Int -- Which column (1..5) does the mission tree branch appear in?
    ,   eu4mtb_potential :: Maybe GenericScript
    ,   eu4mtb_missions :: [EU4Mission]
    } deriving (Show)

data EU4EstateAction = EU4EstateAction
    {
        eaName :: Text
    ,   eaDecision :: EU4Decision
    ,   eaPrivilege :: Text -- the (non-localised) name of the privilege which enables the estate action
    ,   eaScript :: GenericScript -- the scripted effect estate_action_
    }

data EU4Scripted = EU4Scripted
    {   scrName :: Text
    ,   scrPath :: FilePath
    ,   scrScript :: GenericScript
    ,   scrScope :: Maybe EU4Scope
    ,   scrRootScope :: Maybe EU4Scope
    } deriving (Show)

------------------------------
-- Shared lower level types --
------------------------------

-- | Types of monarch power.
data MonarchPower = Administrative
                  | Diplomatic
                  | Military
    deriving (Show, Eq, Ord, Generic)
instance Hashable MonarchPower

-- | Scopes
data EU4Scope
    = EU4Country
    | EU4Province
    | EU4TradeNode
    | EU4Geographic -- ^ Area, etc.
    | EU4Bonus
    | EU4From -- ^ Usually country or province, varies by context
    deriving (Show, Eq, Ord, Enum, Bounded)

data EU4GeoType
    = EU4GeoArea
    | EU4GeoRegion
    | EU4GeoSuperRegion
    | EU4GeoContinent
    | EU4GeoTradeCompany
    | EU4GeoColonialRegion
    -- Province groups aren't used in the base game (as of 1.30.6)
    deriving (Show)

-- | AI decision factors.
data AIWillDo = AIWillDo
    {   awd_base :: Maybe Double
    ,   awd_modifiers :: [AIModifier]
    } deriving (Show)
-- | Modifiers for AI decision factors.
data AIModifier = AIModifier
    {   aim_factor :: Maybe Double
    ,   aim_triggers :: GenericScript
    } deriving (Show)
-- | Empty decision factor.
newAIWillDo :: AIWillDo
newAIWillDo = AIWillDo Nothing []
-- | Empty modifier.
newAIModifier :: AIModifier
newAIModifier = AIModifier Nothing []

-- | Parse an @ai_will_do@ clause.
aiWillDo :: GenericScript -> AIWillDo
aiWillDo = foldl' aiWillDoAddSection newAIWillDo
aiWillDoAddSection :: AIWillDo -> GenericStatement -> AIWillDo
aiWillDoAddSection awd [pdx| $left = %right |] = case T.toLower left of
    "factor" -> case floatRhs right of
        Just fac -> awd { awd_base = Just fac }
        _        -> awd
    "modifier" -> case right of
        CompoundRhs scr -> awd { awd_modifiers = awd_modifiers awd ++ [awdModifier scr] }
        _               -> awd
    _ -> awd
aiWillDoAddSection awd _ = awd

-- | Parse a @modifier@ subclause for an @ai_will_do@ clause.
awdModifier :: GenericScript -> AIModifier
awdModifier = foldl' awdModifierAddSection newAIModifier
awdModifierAddSection :: AIModifier -> GenericStatement -> AIModifier
awdModifierAddSection aim stmt@[pdx| $left = %right |] = case T.toLower left of
    "factor" -> case floatRhs right of
        Just fac -> aim { aim_factor = Just fac }
        Nothing  -> aim
    _ -> -- the rest of the statements are just the conditions.
        aim { aim_triggers = aim_triggers aim ++ [stmt] }
awdModifierAddSection aim _ = aim

isGeographic :: EU4Scope -> Bool
isGeographic EU4Province = True
isGeographic EU4TradeNode = True
isGeographic EU4Geographic = True
isGeographic _ = False

-----------------------------
-- Miscellaneous utilities --
-----------------------------

getModifier :: (EU4Info g, Monad m) => Text -> PPT g m (Maybe EU4Modifier)
getModifier id = HM.lookup id <$> getModifiers

