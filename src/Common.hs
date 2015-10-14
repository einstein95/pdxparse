{-# LANGUAGE OverloadedStrings, PatternGuards #-}
module Common where

import Debug.Trace

import Data.Char
import Data.List
import Data.Maybe
import Data.Monoid

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL

import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM

import Data.Set (Set)
import qualified Data.Set as S

import Text.PrettyPrint.Leijen.Text hiding ((<>), (<$>), int, double)
import qualified Text.PrettyPrint.Leijen.Text as PP

import Abstract
import Localization

isTag :: Text -> Bool
isTag s = T.length s == 3 && T.all isUpper s

isPronoun :: Text -> Bool
isPronoun s = T.map toLower s `S.member` pronouns where
    pronouns = S.fromList
        ["root"
        ,"prev"
        ,"owner"
        ,"controller"
        ]

strictText :: Text -> Doc
strictText = text . TL.fromStrict

pp_script :: Int -> L10n -> GenericScript -> Doc
pp_script indent l10n script
    = hcat . punctuate line
        . map ((mconcat (replicate indent "*" ++ [" "]) <>)
                . pp_statement' indent l10n
              ) $ script

-- Pretty-print a number, putting a + sign in front if it's not negative.
-- Assumes the passed-in formatting function does add a minus sign.
pp_signed :: (Ord n, Num n) => (n -> Doc) -> n -> Doc
pp_signed pp_num n = (if signum n >= 0 then "+" else mempty) <> pp_num n

-- Pretty-print a number, adding wiki formatting:
-- * {{green}} if good
-- * {{red}} if bad
-- * '''boldface''' if neutral
-- What is good or bad is determined by the first argument:
-- * if True, positive is good and negative is bad (e.g. stability)
-- * if False, negative is good and positive is bad (e.g. inflation)
-- * Either way, zero is neutral.
pp_hl_num :: (Ord n, PPSep n) => Bool -> (n -> Doc) -> n -> Doc
pp_hl_num pos pp_num n =
    let sign = signum n
        positivity = if pos then sign else negate sign
        n_pp'd = pp_signed pp_num n
    in case positivity of
        -1 -> template "red" n_pp'd
        0 ->  bold n_pp'd
        1 ->  template "green" n_pp'd

-- Pretty-print a Double. If it's a whole number, display it without a decimal.
pp_float :: Double -> Doc
pp_float n =
    let trunc = floor n
    in if fromIntegral trunc == n
        then PP.int (fromIntegral trunc)
        else PP.double n

-- Pretty-print a Double, as Text.
pp_float_t :: Double -> Text
pp_float_t = TL.toStrict . displayT . renderCompact . pp_float

-- Pretty-print a number, adding &#8239; (U+202F NARROW NO-BREAK SPACE) at
-- every power of 1000.
class Num a => PPSep a where
    pp_num_sep :: a -> Doc

group3 :: [a] -> [[a]]
group3 = unfoldr (\cs -> if null cs then Nothing else Just (splitAt 3 cs))

instance PPSep Integer where
    pp_num_sep n = strictText . T.pack $
            (if n < 0 then "-" else "") <> pp_int_sep' (abs n)
        where pp_int_sep' = concat . reverse
                            . intersperse "&#8239;"
                            . map reverse 
                            . group3 
                            . reverse
                            . show

instance PPSep Int where
    pp_num_sep = pp_num_sep . toInteger

instance PPSep Double where
    pp_num_sep n = (if n < 0 then "-" else "")
                    <> int_pp'd <> decimal <> frac_pp'd
        where (intPart, fracPart) = properFraction n
              int_pp'd = pp_num_sep (intPart::Integer)
              frac_raw = drop 2 . show . abs $ fracPart -- drop "0."
              decimal = if fracPart == 0 then "" else "."
              frac_pp'd = if fracPart == 0 then ""
                            else strictText . T.pack
                                    . mconcat . intersperse "&#8239;"
                                    . group3 $ frac_raw

-- Simple template (one arg).
-- NB: This does not perform escaping of pipes (i.e. replacing them with
-- {{!}}), because I don't know how to do that with Docs.
template :: Text -> Doc -> Doc
template name content = hcat ["{{", strictText name, "|", content, "}}"]

-- Emit flag template if the argument is a tag.
flag :: Text -> Doc
flag name = let name' = strictText name
    in if isTag name
        then template "flag" name'
        else name'

-- Emit icon template.
icon :: Text -> Doc
icon what = template "icon" (strictText what)

-- Set doc in italics.
italic :: Doc -> Doc
italic content = enclose "''" "''" content

-- Set doc in boldface.
bold :: Doc -> Doc
bold content = enclose "'''" "'''" content

-- Emit an icon template followed by some text, separated by space.
labelIcon :: Doc -> Doc -> Doc
labelIcon label content = hsep [template "icon" label, content]

-- Surround a doc in a <pre> element.
pre_statement :: GenericStatement -> Doc
pre_statement stmt = "<pre>" <> genericStatement2doc stmt <> "</pre>"

-- Pretty-print a statement, preceding it with a single layer of bullets.
-- Most statements are expected to be of a particular form. If they're not, we
-- just echo the statement instead of failing. This is also what we do with
-- unrecognized statements.
pp_statement :: L10n -> GenericStatement -> Doc
pp_statement = pp_statement' 1

-- Pretty-print a statement, preceding it with the given number of bullets.
pp_statement' :: Int -> L10n -> GenericStatement -> Doc
pp_statement' indent l10n stmt@(Statement lhs rhs) =
    let defaultdoc = pre_statement stmt
        compound = generic_compound defaultdoc indent l10n
        -- not computed if not needed, thanks to laziness
    in case lhs of
        GenericLhs label -> case label of
            -- Gain/lose
            "add_adm_power" -> gain Nothing True (Just "adm") "administrative power" stmt
            "add_dip_power" -> gain Nothing True (Just "dip") "diplomatic power" stmt
            "add_mil_power" -> gain Nothing True (Just "mil") "military power" stmt
            "add_army_tradition" -> gain Nothing True (Just "army tradition") "army tradition" stmt
            "add_prestige" -> gain Nothing True (Just "prestige") "prestige" stmt
            "add_stability" -> gain Nothing True (Just "stability") "stability" stmt
            "add_inflation" -> gain Nothing False (Just "inflation") "inflation" stmt
            "add_base_tax" -> gain Nothing False (Just "base tax") "base tax" stmt
            "add_heir_claim" -> gain (Just "Heir") True Nothing "claim strength" stmt
            "add_legitimacy" -> gain Nothing False (Just "legitimacy") "legitimacy" stmt
            "add_local_autonomy" -> gain Nothing False (Just "local autonomy") "local autonomy" stmt
            "add_war_exhaustion" -> gain Nothing False (Just "war exhaustion") "war exhaustion" stmt
            "change_adm" -> gain (Just "Ruler") True (Just "adm") "administrative skill" stmt
            "change_dip" -> gain (Just "Ruler") True (Just "dip") "diplomatic skill" stmt
            "change_mil" -> gain (Just "Ruler") True (Just "mil") "military skill" stmt
            "change_siege" -> gain Nothing True Nothing "siege progress" stmt
            "add_manpower" -> gain_manpower stmt
            -- Modifiers
            "add_province_modifier" -> add_modifier "province" l10n stmt
            "add_permanent_province_modifier" -> add_modifier "permanent province" l10n stmt
            "add_country_modifier" -> add_modifier "country" l10n stmt
            "has_province_modifier" -> has_modifier "province" l10n stmt
            "has_country_modifier" -> has_modifier "country" l10n stmt
            "remove_province_modifier" -> remove_modifier "province" l10n stmt
            "remove_country_modifier" -> remove_modifier "country" l10n stmt
            -- Simple compound statements
            -- Note that "any" can mean "all" or "one or more" depending on context.
            "every_province" -> compound "Every province in the world" stmt
            "random_province" -> compound "One random province" stmt
            "any_owned_province" -> compound "Owned province(s)" stmt
            "every_owned_province" -> compound "Every owned province" stmt
            "random_owned_province" -> compound "One random owned province" stmt
            "any_known_country" -> compound "Known country/countries" stmt
            "every_known_country" -> compound "Every known country" stmt
            "any_neighbor_province" -> compound "Neighboring province(s)" stmt
            "any_neighbor_country" -> compound "Neighboring country/countries" stmt
            "any_rival_country" -> compound "Rival(s)" stmt
            "random_neighbor_province" -> compound "One random neighboring province" stmt
            "random_neighbor_country" -> compound "One random neighboring country" stmt
            "random_list" -> compound "One of the following at random" stmt
            "owner" -> compound "Province owner" stmt
            "controller" -> compound "Province controller" stmt
            "limit" -> compound "Limited to" stmt
            "hidden_effect" -> compound "Hidden effect" stmt
            "NOT" -> compound "None of" stmt
            "AND" -> compound "All of" stmt
            "OR" -> compound "At least one of" stmt
            "FROM" ->
                -- This is ugly, but without further analysis we can't know
                -- what it means.
                compound "FROM" stmt
            "if" -> compound "If" stmt
            -- Simple generic statements
            "continent"         -> simple_generic l10n "Continent is" stmt mempty
            "culture"           -> simple_generic l10n "Culture is" stmt mempty
            "government"        -> simple_generic l10n "Government is" stmt mempty
            "change_government" -> simple_generic l10n "Change government to" stmt mempty
            "region"            -> simple_generic l10n "Is in region" stmt mempty
            "kill_advisor"      -> simple_generic l10n mempty stmt "dies"
            "remove_advisor"    -> simple_generic l10n mempty stmt "leaves the country's court"
            "infantry"          -> simple_generic l10n "An infantry regiment spawns in" stmt mempty
            -- Simple generic statements (typewriter face)
            "set_country_flag"  -> simple_generic_tt "Set country flag" stmt
            "set_province_flag" -> simple_generic_tt "Set province flag" stmt
            "has_province_flag" -> simple_generic_tt "Has province flag" stmt
            "clr_country_flag"  -> simple_generic_tt "Clear country flag" stmt
            "clr_province_flag" -> simple_generic_tt "Clear province flag" stmt
            -- Simple generic statements with icon
            "trade_goods"       -> generic_icon l10n "Produces" stmt
            "advisor"           -> generic_icon l10n "Has" stmt
            -- Simple generic statements with flag
            "has_discovered"    -> generic_tag l10n "Has discovered" stmt
            "is_core"           -> generic_tag l10n "Is core of" stmt
            "owned_by"          -> generic_tag l10n "Is owned by" stmt
            "controlled_by"     -> generic_tag l10n "Is controlled by" stmt
            "sieged_by"         -> generic_tag l10n "Is under siege by" stmt
            "war_with"          -> generic_tag l10n "Is at war with" stmt
            "defensive_war_with" -> generic_tag l10n "Is in a defensive war against" stmt
            "offensive_war_with" -> generic_tag l10n "Is in an offensive war against" stmt
            -- Statements that may be an icon, a flag, or a pronoun (such as ROOT)
            "religion"          -> generic_icon_or_country l10n "Religion is" stmt
            "religion_group"    -> generic_icon_or_country l10n "Religion group is" stmt
            "change_religion"   -> generic_icon_or_country l10n "Change religion to" stmt
            -- Boolean statements
            "has_port"              -> has "a port" stmt
            "is_reformation_center" -> is Nothing "a center of reformation" stmt
            "is_capital"            -> is Nothing "capital" stmt
            "is_looted"             -> is Nothing "looted" stmt
            "is_at_war"             -> is Nothing "at war" stmt
            "kill_ruler"            -> {- assume yes -} "Ruler dies"
            "is_lesser_in_union"    -> is Nothing "the junior partner in a personal union" stmt
            "is_monarch_leader"     -> is (Just "Monarch") "a military leader" stmt
            "has_siege"             -> is Nothing "under siege" stmt
            -- Numeric statements
            "base_tax" -> simple_numeric "Base tax is at least" stmt mempty
            "num_of_mercenaries" -> simple_numeric "Has at least" stmt "mercenary regiment(s)"
            "manpower_percentage" -> manpower_percentage stmt
            "had_recent_war" -> simple_numeric "Was at war within the last" stmt "months(?)"
            "heir_age" -> simple_numeric "Heir is at least" stmt "years old"
            -- Signed numeric statements
            "stability" -> simple_numeric_signed "Stability is at least" stmt mempty
            "war_score" -> simple_numeric_signed "Warscore is at least" stmt mempty
            "tolerance_to_this" -> simple_numeric_signed "Tolerance to this religion is at least" stmt mempty
            -- Statements of numeric quantities with icons
            "war_exhaustion" -> numeric_icon "Has at least" Nothing "war exhaustion" stmt
            "adm_tech" -> numeric_icon "Has at least" Nothing "administrative technology" stmt
            "dip_tech" -> numeric_icon "Has at least" Nothing "diplomatic technology" stmt
            "mil_tech" -> numeric_icon "Has at least" Nothing "military technology" stmt
            "adm" -> numeric_icon "Has at least" (Just "adm") "administrative skill" stmt
            "dip" -> numeric_icon "Has at least" (Just "dip") "diplomatic skill" stmt
            "mil" -> numeric_icon "Has at least" (Just "mil") "military skill" stmt
            -- Complex statements
            "add_faction_influence" -> faction_influence stmt
            "add_opinion" -> opinion l10n "Add" stmt
            "has_opinion_modifier" -> opinion l10n "Has" stmt
            "add_years_of_income" -> add_years_of_income stmt
            "province_event"    -> trigger_event l10n "province" stmt
            "country_event"    -> trigger_event l10n "country" stmt
            "add_casus_belli" -> add_casus_belli l10n False stmt
            "reverse_add_casus_belli" -> add_casus_belli l10n False stmt
            -- Rebels
            "create_revolt" -> spawn_rebels l10n Nothing stmt
            "spawn_rebels" -> spawn_rebels l10n Nothing stmt
            "nationalist_rebels" -> spawn_rebels l10n (Just "Nationalist") stmt
            -- Special
            "add_core"          -> add_core l10n stmt
            -- Ignored
            "tooltip" -> "(explanatory tooltip - delete this line)"
            "custom_tooltip" -> "(custom tooltip - delete this line)"
            -- default
            _ -> if isTag label
                 then case rhs of
                    CompoundRhs scr ->
                        flag (HM.lookupDefault label label l10n)
                        <> ":"
                        <> line <> pp_script (succ indent) l10n scr
                    _ -> defaultdoc
                 else defaultdoc
        IntLhs n -> case rhs of -- Treat as a province tag
            CompoundRhs scr ->
                let provN = T.pack (show n)
                in hcat
                    ["Province"
                    ,space
                    ,strictText (HM.lookupDefault ("Province " <> provN) ("PROV" <> provN) l10n)
                    ,":"
                    ,line
                    ,pp_script (succ indent) l10n scr
                    ]
            _ -> defaultdoc


------------------------------------------------------------------------
-- Script handlers that should be used directly, not via pp_statement --
------------------------------------------------------------------------

data MTTH = MTTH
        {   years :: Maybe Int
        ,   months :: Maybe Int
        ,   days :: Maybe Int
--        ,   factors :: [GenericStatement] -- TODO
        } deriving Show
newMTTH = MTTH Nothing Nothing Nothing --[]
addField mtth _ = mtth -- unrecognized
pp_mtth :: L10n -> GenericScript -> Doc
pp_mtth l10n scr
    = pp_mtth $ foldl' addField newMTTH scr
    where
        addField mtth (Statement (GenericLhs "years") (IntRhs n))
            = mtth { years = Just n }
        addField mtth (Statement (GenericLhs "years") (FloatRhs n))
            = mtth { years = Just (floor n) }
        addField mtth (Statement (GenericLhs "months") (IntRhs n))
            = mtth { months = Just n }
        addField mtth (Statement (GenericLhs "months") (FloatRhs n))
            = mtth { months = Just (floor n) }
        addField mtth (Statement (GenericLhs "days") (IntRhs n))
            = mtth { days = Just n }
        addField mtth (Statement (GenericLhs "days") (FloatRhs n))
            = mtth { days = Just (floor n) }
        addField mtth (Statement (GenericLhs "modifier") (CompoundRhs rhs))
        --            = addFactor mtth rhs
            = mtth -- TODO
        pp_mtth mtth@(MTTH years months days) =
            let hasYears = isJust years
                hasMonths = isJust months
                hasDays = isJust days
            in mconcat $
                ((if hasYears then
                    [PP.int (fromJust years), space, "years"]
                    ++
                    if hasMonths && hasDays then [",", space]
                    else if hasMonths || hasDays then ["and", space]
                    else []
                 else [])
                ++
                (if hasMonths then
                    [PP.int (fromJust months), space, "months"]
                 else [])
                ++
                (if hasDays then
                    (if hasYears && hasMonths then ["and", space]
                     else []) -- if years but no months, already added "and"
                    ++
                    [PP.int (fromJust days), space, "days"]
                 else []))

--------------------------------
-- General statement handlers --
--------------------------------

generic_compound :: Doc -> Int -> L10n -> Text -> GenericStatement -> Doc
generic_compound _ indent l10n header (Statement _ (CompoundRhs scr))
        = hcat
            [strictText header, ":"
            ,line
            ,pp_script (succ indent) l10n scr
            ]
generic_compound defaultdoc _ _ _ _ = defaultdoc

-- Statement with generic on both sides translating to the form
--  <string> <l10n value>
simple_generic :: L10n -> Text -> GenericStatement -> Text -> Doc
simple_generic l10n premsg (Statement _ (GenericRhs name)) postmsg
    = hsep
        [strictText premsg
        ,strictText $ HM.lookupDefault name name l10n
        ,strictText postmsg
        ]
simple_generic _ _ stmt _ = pre_statement stmt

-- As simple_generic but definitely no l10n. Set the RHS in typewriter face
simple_generic_tt :: Text -> GenericStatement -> Doc
simple_generic_tt premsg (Statement _ (GenericRhs name))
    = mconcat [strictText $ premsg, space, "<tt>", strictText name, "</tt>"]
simple_generic_tt _ stmt = pre_statement stmt

-- Table of script atom -> icon key. Only ones that are different are listed.
scriptIconTable :: HashMap Text Text
scriptIconTable = HM.fromList
    [("master_of_mint", "master of mint")
    ,("natural_scientist", "natural scientist")
    ,("colonial_governor", "colonial governor")
    ,("diplomat", "diplomat_adv")
    ,("naval_reformer", "naval reformer")
    ,("army_organizer", "army organizer")
    ,("army_reformer", "army reformer")
    ,("grand_captain", "grand captain")
    ,("master_recruiter", "master recruiter")
    ,("military_engineer", "military engineer")
    ]

-- As simple_generic but also add an appropriate icon before the value.
generic_icon :: L10n -> Text -> GenericStatement -> Doc
generic_icon l10n premsg (Statement (GenericLhs category) (GenericRhs name))
    = hsep
        [strictText $ premsg
        ,icon (HM.lookupDefault name name scriptIconTable)
        ,strictText $ HM.lookupDefault name name l10n]
generic_icon _ _ stmt = pre_statement stmt

-- As generic_icon but say "same as <foo>" if foo refers to a country
-- (in which case, add a flag if it's a specific country).
generic_icon_or_country :: L10n -> Text -> GenericStatement -> Doc
generic_icon_or_country l10n premsg (Statement (GenericLhs category) (GenericRhs name))
    = hsep $ strictText premsg :
          if isTag name || isPronoun name
            then ["same", "as", flag name]
            else [icon (HM.lookupDefault name name scriptIconTable)
                 ,strictText $ HM.lookupDefault name name l10n]
generic_icon_or_country _ _ stmt = pre_statement stmt

-- Numeric statement. Allow additional text on both sides.
simple_numeric :: Text -> GenericStatement -> Text -> Doc
simple_numeric premsg (Statement _ rhs) postmsg
    = let n = case rhs of
                IntRhs n' -> fromIntegral n'
                FloatRhs n' -> n'
      in hsep
            [strictText premsg
            ,pp_float n
            ,strictText postmsg
            ]
simple_numeric _ stmt _ = pre_statement stmt

simple_numeric_signed :: Text -> GenericStatement -> Text -> Doc
simple_numeric_signed premsg (Statement _ rhs) postmsg
    = let n = case rhs of
                IntRhs n' -> fromIntegral n'
                FloatRhs n' -> n'
      in hsep
            [strictText premsg
            ,pp_signed pp_float n
            ,strictText postmsg
            ]

-- "Has <something>"
has :: Text -> GenericStatement -> Doc
has what (Statement _ (GenericRhs yn)) | yn `elem` ["yes","no"]
    = hsep
        [if yn == "yes" then "Has" else "Does NOT have"
        ,strictText what
        ]
has _ stmt = pre_statement stmt

-- "Is <something>" (or "<Someone> is <something>")
is :: Maybe Text -> Text -> GenericStatement -> Doc
is who what (Statement _ (GenericRhs yn)) | yn `elem` ["yes","no"]
    = let know_who = isJust who
          no = yn == "no"
      in hsep $
            (if know_who
                then [strictText (fromJust who), "is"]
                else ["Is"]) ++
            (if no then ["NOT"] else []) ++
            [strictText what]
is _ _ stmt = pre_statement stmt

-- Generic statement referring to a country. Use a flag.
generic_tag :: L10n -> Text -> GenericStatement -> Doc
generic_tag l10n prefix (Statement _ (GenericRhs who))
    = hsep
        [strictText prefix
        ,flag $ HM.lookupDefault who who l10n
        ]
generic_tag _ _ stmt = pre_statement stmt

numeric_icon :: Text -> Maybe Text -> Text -> GenericStatement -> Doc
numeric_icon premsg micon what (Statement _ rhs)
    = let amt = case rhs of
            IntRhs n -> fromIntegral n
            FloatRhs n -> n
          the_icon = maybe what id micon
      in hsep
            [strictText premsg
            ,icon the_icon
            ,pp_float amt
            ,strictText what
            ]

---------------------------------
-- Specific statement handlers --
---------------------------------

data FactionInfluence = FactionInfluence {
        faction :: Maybe Text
    ,   influence :: Maybe Double
    }
newInfluence = FactionInfluence Nothing Nothing
faction_influence :: GenericStatement -> Doc
faction_influence stmt@(Statement _ (CompoundRhs scr))
    = pp_influence $ foldl' addField newInfluence scr
    where
        pp_influence inf =
            if isJust (faction inf) && isJust (influence inf)
            then
                let fac = case fromJust (faction inf) of
                            -- Celestial empire
                            "enuchs" {- sic -} -> "eunuchs influence"
                            "temples" -> "temples influence"
                            "bureaucrats" -> "bureaucrats influence"
                            -- Merchant republic
                            "mr_aristocrats" -> "aristocrats influence"
                            "mr_guilds" -> "guilds influence"
                            "mr_traders" -> "traders influence"
                in hsep
                    [icon fac
                    -- Influence can be good or bad depending on the country's
                    -- situation, so leave it neutral.
                    ,bold (pp_signed pp_float . fromJust $ influence inf)
                    ,text ((\(Just (c,cs)) -> TL.fromStrict $ T.cons (toUpper c) cs) $ T.uncons fac)
                    ]
            else pre_statement stmt
        addField :: FactionInfluence -> GenericStatement -> FactionInfluence
        addField inf (Statement (GenericLhs "faction") (GenericRhs fac)) = inf { faction = Just fac }
        addField inf (Statement (GenericLhs "influence") (FloatRhs amt)) = inf { influence = Just amt }
        addField inf (Statement (GenericLhs "influence") (IntRhs amt)) = inf { influence = Just (fromIntegral amt) }
        addField inf _ = inf -- unknown statement

add_years_of_income :: GenericStatement -> Doc
add_years_of_income stmt
    | Statement _ (IntRhs n)   <- stmt = add_years_of_income' (fromIntegral n)
    | Statement _ (FloatRhs n) <- stmt = add_years_of_income' n
    where
        add_years_of_income' howmuch = hsep
            [if howmuch < 0 then "Lose" else "Gain"
            ,icon "ducats"
            ,"ducats", "equal", "to"
            ,pp_float (abs howmuch)
            ,if abs howmuch == 1 then "year" else "years"
            ,"of", "income"
            ]

-- "Gain" or "Lose" simple numbers, e.g. army tradition.
-- First text argument is the icon key (or Nothing if none available).
-- Second text argument is text to show after it.
-- Bool is whether a gain is good.
gain :: Maybe Text -> Bool -> Maybe Text -> Text -> GenericStatement -> Doc
gain mwho good iconkey what stmt
    | Statement _ (IntRhs n)   <- stmt = gain' (fromIntegral n)
    | Statement _ (FloatRhs n) <- stmt = gain' n
    where
        know_who = isJust mwho
        who = fromJust mwho
        gain' :: Double -> Doc
        gain' howmuch = hsep $
            (if know_who then [strictText who] else [])
            ++
            [gain_or_lose]
            ++ (if isJust iconkey then [icon (fromJust iconkey)] else [])
            ++
            [pp_hl_num good pp_num_sep howmuch
            ,strictText what
            ]
            where
                gain_or_lose =
                    if know_who
                        then if howmuch < 0 then "loses" else "gains"
                        else if howmuch < 0 then "Lose" else "Gain"

data AddModifier = AddModifier {
        name :: Maybe Text
    ,   duration :: Maybe Double
    } deriving Show
newAddModifier = AddModifier Nothing Nothing

add_modifier :: Text -> L10n -> GenericStatement -> Doc
add_modifier kind l10n stmt@(Statement _ (CompoundRhs scr))
    = pp_add_modifier $ foldl' addLine newAddModifier scr
    where
        addLine :: AddModifier -> GenericStatement -> AddModifier 
        addLine apm (Statement (GenericLhs "name") (GenericRhs name)) = apm { name = Just name }
        addLine apm (Statement (GenericLhs "name") (StringRhs name)) = apm { name = Just name }
        addLine apm (Statement (GenericLhs "duration") (FloatRhs duration)) = apm { duration = Just duration }
        addLine apm _ = apm -- e.g. hidden = yes
        pp_add_modifier :: AddModifier -> Doc
        pp_add_modifier apm
            = if isJust (name apm) then
                let dur = fromJust (duration apm)
                in hsep $
                    ["Add", strictText kind, "modifier"
                    ,dquotes (strictText $
                        let key = fromJust . name $ apm
                        in  HM.lookupDefault key key l10n)
                    ]
                    ++ if isJust (duration apm) then
                        if dur < 0 then ["indefinitely"] else
                        ["for"
                        ,pp_float dur
                        ,"days"
                        ]
                    else []
              else pre_statement stmt
add_modifier _ _ stmt = pre_statement stmt

has_modifier :: Text -> L10n -> GenericStatement -> Doc
has_modifier kind l10n (Statement _ (GenericRhs label))
    = hsep
        ["Has", strictText kind, "modifier"
        ,dquotes (strictText $ HM.lookupDefault label label l10n)
        ]
has_modifier _ _ stmt = pre_statement stmt

remove_modifier :: Text -> L10n -> GenericStatement -> Doc
remove_modifier kind l10n (Statement _ (GenericRhs label))
    = hsep
        ["Remove", strictText kind, "modifier"
        ,dquotes (strictText $ HM.lookupDefault label label l10n)
        ]
remove_modifier _ _ stmt = pre_statement stmt

-- "add_core = <n>" in country scope means "Gain core on <localize PROVn>"
-- "add_core = <tag>" in province scope means "<localize tag> gains core"
add_core :: L10n -> GenericStatement -> Doc
add_core l10n (Statement _ (GenericRhs tag)) -- tag
    = hsep [flag $ HM.lookupDefault tag tag l10n, "gains", "core"]
add_core l10n (Statement _ (IntRhs num)) -- province
    = hsep ["Gain", "core", "on", "province", strictText $ HM.lookupDefault provKey provKey l10n]
    where provKey = "PROV" <> T.pack (show num)
add_core l10n (Statement _ (FloatRhs num)) -- province
    = hsep ["Gain", "core", "on", "province", strictText $ HM.lookupDefault provKey provKey l10n]
    where provKey = "PROV" <> T.pack (showFloat num)
add_core _ stmt = trace ("province: fallback: " ++ show stmt) $ pre_statement stmt

-- Add an opinion modifier towards someone (for a number of years).
data AddOpinion = AddOpinion {
        who :: Maybe Text
    ,   modifier :: Maybe Text
    ,   op_years :: Maybe Double
    } deriving Show
newAddOpinion = AddOpinion Nothing Nothing Nothing

opinion :: L10n -> Text -> GenericStatement -> Doc
opinion l10n verb stmt@(Statement _ (CompoundRhs scr))
    = pp_add_opinion $ foldl' addLine newAddOpinion scr
    where
        addLine :: AddOpinion -> GenericStatement -> AddOpinion
        addLine op (Statement (GenericLhs "who") (GenericRhs tag))
            = op { who = Just tag }
        addLine op (Statement (GenericLhs "modifier") (GenericRhs label))
            = op { modifier = Just label }
        addLine op (Statement (GenericLhs "years") (FloatRhs n))
            = op { op_years = Just n }
        addLine op (Statement (GenericLhs "years") (IntRhs n))
            = op { op_years = Just (fromIntegral n) }
        addLine op _ = op
        pp_add_opinion op
            = if isJust (who op) && isJust (modifier op) then
                let whom = fromJust (who op)
                    mod = fromJust (modifier op)
                in hsep $
                    [strictText verb
                    ,"opinion modifier"
                    ,dquotes $ strictText (HM.lookupDefault mod mod l10n)
                    ,"towards"
                    ,flag $ HM.lookupDefault whom whom l10n
                    ]
                    ++ if isNothing (op_years op) then [] else
                    ["for"
                    ,pp_float (fromJust (op_years op))
                    ,"years"
                    ]
              else pre_statement stmt
add_opinion _ stmt = pre_statement stmt

-- Spawn a rebel stack.
data SpawnRebels = SpawnRebels {
        rebelType :: Maybe Text
    ,   rebelSize :: Maybe Double
    ,   friend :: Maybe Text
    ,   win :: Maybe Bool
    ,   unrest :: Maybe Double -- rebel faction progress
    } deriving Show
newSpawnRebels = SpawnRebels Nothing Nothing Nothing Nothing Nothing

spawn_rebels :: L10n -> Maybe Text -> GenericStatement  -> Doc
spawn_rebels l10n mtype stmt = spawn_rebels' mtype stmt where
    spawn_rebels' Nothing stmt@(Statement _ (CompoundRhs scr))
        = pp_spawn_rebels $ foldl' addLine newSpawnRebels scr
    spawn_rebels' rtype stmt@(Statement _ (IntRhs size))
        = pp_spawn_rebels $ newSpawnRebels { rebelType = rtype, rebelSize = Just (fromIntegral size) }
    spawn_rebels' rtype stmt@(Statement _ (FloatRhs size))
        = pp_spawn_rebels $ newSpawnRebels { rebelType = rtype, rebelSize = Just size }

    addLine :: SpawnRebels -> GenericStatement -> SpawnRebels
    addLine op (Statement (GenericLhs "type") (GenericRhs tag))
        = op { rebelType = Just tag }
    addLine op (Statement (GenericLhs "size") (FloatRhs n))
        = op { rebelSize = Just n }
    addLine op (Statement (GenericLhs "friend") (GenericRhs tag))
        = op { friend = Just tag }
    addLine op (Statement (GenericLhs "win") (GenericRhs "yes"))
        = op { win = Just True }
    addLine op (Statement (GenericLhs "unrest") (FloatRhs n))
        = op { unrest = Just n }
    addLine op _ = op

    pp_spawn_rebels :: SpawnRebels -> Doc
    pp_spawn_rebels reb
        = if isJust (rebelType reb) && isJust (rebelSize reb) then
            let hasType = isJust (rebelType reb)
                rtype = fromJust (rebelType reb)
                rsize = fromJust (rebelSize reb)
                friendlyTo = fromJust (friend reb) -- not evaluated if Nothing
                reb_unrest = fromJust (unrest reb)
            in (hsep $
                   (if hasType
                        then [strictText (HM.lookupDefault rtype (rtype <> "_title") l10n), "rebels"]
                        else ["Rebels"])
                   ++
                   [PP.parens $ hsep ["size", pp_float (fromJust (rebelSize reb))]]
                   ++ if isJust (friend reb) then
                   [PP.parens $ hsep ["friendly", "to",
                                        strictText (HM.lookupDefault friendlyTo friendlyTo l10n)]
                   ] else []
                   ++
                   ["rise in revolt"
                   ] ++ if isJust (win reb) && fromJust (win reb) then
                   [hsep ["and", "occupy", "the", "province"]
                   ] else []
                ) <> if isJust (unrest reb) then
                hsep
                   [","
                   ,"gaining"
                   ,pp_float reb_unrest
                   ,hsep ["progress","towards","the","next","uprising"]
                   ]
                else mempty
        else pre_statement stmt

manpower_percentage :: GenericStatement -> Doc
manpower_percentage (Statement _ rhs)
    = let pc = case rhs of
            IntRhs n -> fromIntegral n -- unlikely, but could be 1
            FloatRhs n -> n
      in hsep
            ["Available manpower is at least"
            ,pp_float (pc * 100) <> "%"
            ,"of maximum"
            ]

data TriggerEvent = TriggerEvent
        { e_id :: Maybe Text
        , e_title_loc :: Maybe Text
        , e_days :: Maybe Int
        }
newTriggerEvent = TriggerEvent Nothing Nothing Nothing
trigger_event :: L10n -> Text -> GenericStatement -> Doc
trigger_event l10n category stmt@(Statement _ (CompoundRhs scr))
    = pp_trigger_event $ foldl' addLine newTriggerEvent scr
    where
        addLine :: TriggerEvent -> GenericStatement -> TriggerEvent
        addLine evt (Statement (GenericLhs "id") (GenericRhs id))
            = evt { e_id = Just id, e_title_loc = HM.lookup (id <> ".t") l10n }
        addLine evt (Statement (GenericLhs "days") rhs) = case rhs of
            IntRhs n -> evt { e_days = Just n }
            FloatRhs n -> evt { e_days = Just (round n) }
        addLine evt _ = evt
        pp_trigger_event evt
            = let have_loc = isJust (e_title_loc evt)
                  have_days = isJust (e_days evt)
                  mid = e_id evt
                  loc = e_title_loc evt
                  days = e_days evt
              in if isJust mid then hsep $
                    ["Trigger"
                    ,strictText category
                    ,"event"
                    ,dquotes (strictText (if have_loc then fromJust loc else fromJust mid))
                    ] ++ if have_days then
                        ["in"
                        ,PP.int (fromJust days)
                        ,"day(s)"
                        ]
                    else []
                 else pre_statement stmt

gain_manpower :: GenericStatement -> Doc
gain_manpower (Statement _ rhs) =
    let amt = case rhs of
            IntRhs n -> fromIntegral n
            FloatRhs n -> n
        gain_or_lose = if amt < 0 then "Lose" else "Gain"
    in hsep
        [gain_or_lose
        ,icon "manpower"
        ,pp_hl_num True pp_float amt
        ,"months worth of manpower"
        ]


data AddCB = AddCB
    {   acb_target :: Maybe Text
    ,   acb_target_loc :: Maybe Text
    ,   acb_type :: Maybe Text
    ,   acb_type_loc :: Maybe Text
    ,   acb_months :: Maybe Double
    }
newAddCB = AddCB Nothing Nothing Nothing Nothing Nothing
-- "direct" is False for reverse_add_casus_belli
add_casus_belli :: L10n -> Bool -> GenericStatement -> Doc
add_casus_belli l10n direct stmt@(Statement _ (CompoundRhs scr))
    = pp_add_cb $ foldl' addLine newAddCB scr where
        addLine :: AddCB -> GenericStatement -> AddCB
        addLine acb (Statement (GenericLhs "target") (GenericRhs target))
            = acb { acb_target = Just target
                  , acb_target_loc = HM.lookup target l10n }
        addLine acb (Statement (GenericLhs "type") (GenericRhs cbtype))
            = acb { acb_type = Just cbtype
                  , acb_type_loc = HM.lookup cbtype l10n }
        addLine acb (Statement (GenericLhs "months") rhs)
            = acb { acb_months = Just months }
            where months = case rhs of
                    IntRhs n -> fromIntegral n
                    FloatRhs n -> n
        pp_add_cb :: AddCB -> Doc
        pp_add_cb acb
            = let has_target = isJust (acb_target acb)
                  has_type = isJust (acb_type acb)
                  has_months = isJust (acb_months acb)
                  target_loc = maybe (fromJust (acb_target acb)) id (acb_target_loc acb)
                  type_loc = maybe (fromJust (acb_type acb)) id (acb_type_loc acb)
                  months = fromJust (acb_months acb)
              in if has_target && has_type
                 then hsep $
                       (if direct then
                            ["Gain"
                            ,dquotes (strictText type_loc)
                            ,"casus belli against"
                            ,strictText target_loc
                            ]
                        else
                            [strictText target_loc
                            ,"gains"
                            ,dquotes (strictText type_loc)
                            ,"casus belli"
                            ]
                        ) ++
                        if has_months then
                            ["for"
                            ,pp_float months
                            ,"months"
                            ]
                        else []
                 else pre_statement stmt
