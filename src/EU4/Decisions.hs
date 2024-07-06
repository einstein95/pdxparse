{-
Module      : EU4.Decisions
Description : Feature handler for Europa Universalis IV decisions
-}
module EU4.Decisions (
        parseEU4Decisions
    ,   writeEU4Decisions
    ,   findEstateActions
    ) where

import Debug.Trace (trace, traceM)

import Control.Arrow ((&&&))
import Control.Monad (foldM, forM)
import Control.Monad.Except (ExceptT (..), MonadError (..))
import Control.Monad.State (MonadState (..), gets)
import Control.Monad.Trans (MonadIO (..))

import Data.List (foldl')
import Data.Maybe (catMaybes)
import Data.Monoid ((<>))

import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.Text (Text)
import qualified Data.Text as T
import Text.PrettyPrint.Leijen.Text (Doc)
import qualified Text.PrettyPrint.Leijen.Text as PP
import Text.Regex.TDFA (Regex)
import qualified Text.Regex.TDFA as RE

import Abstract -- everything
import qualified Doc
import FileIO (Feature (..), writeFeatures, readScriptFromText)
import Messages -- everything
import QQ (pdx)
import SettingsTypes ( PPT, Settings (..), Game (..)
                     , IsGame (..), IsGameData (..), IsGameState (..)
                     , getGameL10n, getGameL10nIfPresent
                     , setCurrentFile, withCurrentFile
                     , hoistExceptions)
import EU4.Common -- everything

-- | Empty decision. Starts off Nothing/empty everywhere, except id and name
-- (which should get filled in immediately).
newDecision :: EU4Decision
newDecision = EU4Decision undefined undefined Nothing [] [] [] Nothing Nothing

-- | Take the decisions scripts from game data and parse them into decision
-- data structures.
parseEU4Decisions :: (IsGameData (GameData g),
                      IsGameState (GameState g),
                      Monad m) =>
    HashMap String GenericScript -> PPT g m (HashMap Text EU4Decision)
parseEU4Decisions scripts = do
    tryParse <- hoistExceptions . flip HM.traverseWithKey scripts $ \f script ->
                    setCurrentFile f (concat <$> mapM parseEU4DecisionGroup script)
    case tryParse of
        Left err -> do
            -- TODO: use logging instead of trace
            traceM $ "Completely failed parsing decisions: " ++ T.unpack err
            return HM.empty
        Right files -> fmap (HM.unions . HM.elems) . flip HM.traverseWithKey files $
            \sourceFile edecs ->
                    fmap (HM.fromList . map (dec_name &&& id) . catMaybes)
                        . forM edecs $ \case
                Left err -> do
                    -- TODO: use logging instead of trace
                    traceM $ "Error parsing " ++ sourceFile
                             ++ ": " ++ T.unpack err
                    return Nothing
                Right dec -> return (Just dec)

--parseEU4Event :: MonadError Text m => FilePath -> GenericStatement -> PPT g m (Either Text (Maybe EU4Event))

-- | Parse one file's decision scripts into decision data structures.
parseEU4DecisionGroup :: (IsGameData (GameData g),
                          IsGameState (GameState g),
                          Monad m) =>
    GenericStatement -> PPT g (ExceptT Text m) [Either Text EU4Decision]
parseEU4DecisionGroup [pdx| $left = @scr |]
    | left `elem` ["country_decisions", "religion_decisions"]
    = forM scr $ \stmt -> (Right <$> parseEU4Decision stmt)
                            `catchError` (return . Left)
    | otherwise = throwError "unrecognized form for decision block (LHS)"
parseEU4DecisionGroup [pdx| $_ = %_ |]
    = throwError "unrecognized form for decision block (RHS)"
parseEU4DecisionGroup _ = throwError "unrecognized form for decision block (LHS)"

-- | Parse one decision script into a decision data structure.
parseEU4Decision :: (IsGameData (GameData g),
                     IsGameState (GameState g),
                     Monad m) =>
    GenericStatement -> PPT g (ExceptT Text m) EU4Decision
parseEU4Decision [pdx| $decName = %rhs |] = case rhs of
    CompoundRhs parts -> do
        decName_loc <- getGameL10n (decName <> "_title")
        decText <- getGameL10nIfPresent (decName <> "_desc")
        withCurrentFile $ \sourcePath ->
            foldM decisionAddSection
                  newDecision { dec_name = decName
                              , dec_name_loc = decName_loc
                              , dec_text = decText
                              , dec_path = Just sourcePath }
                  parts
    _ -> throwError "unrecognized form for decision (RHS)"
parseEU4Decision _ = throwError "unrecognized form for decision (LHS)"

-- | Add a sub-clause of the decision script to the data structure.
decisionAddSection :: (IsGameState (GameState g), Monad m) =>
    EU4Decision -> GenericStatement -> PPT g m EU4Decision
decisionAddSection dec [pdx| potential        = @scr |] = return dec { dec_potential = scr }
decisionAddSection dec [pdx| allow            = @scr |] = return dec { dec_allow = scr }
decisionAddSection dec [pdx| effect           = @scr |] = return dec { dec_effect = scr }
decisionAddSection dec [pdx| ai_will_do       = @scr |] = return dec { dec_ai_will_do = Just (aiWillDo scr) }
decisionAddSection dec [pdx| do_not_integrate = %_   |] = return dec -- maybe mention this in AI notes
decisionAddSection dec [pdx| do_not_core      = %_   |] = return dec -- maybe mention this in AI notes
decisionAddSection dec [pdx| major            = %_   |] = return dec -- currently no field in the template for this
decisionAddSection dec [pdx| provinces_to_highlight = %_   |] = return dec -- not interesting
decisionAddSection dec [pdx| color            = %_   |] = return dec -- not interesting
decisionAddSection dec [pdx| ai_importance    = %_   |]
            -- TODO: use logging instead of trace
        = -- trace "notice: ai_importance not yet implemented" $ -- TODO: Ignored for now
          return dec
decisionAddSection dec stmt = withCurrentFile $ \file -> do
    -- TODO: use logging instead of trace
    traceM ("warning: unrecognized decision section in " ++ file ++ ": " ++ show stmt)
    return dec

-- | Present the parsed decisions as wiki text and write them to the
-- appropriate files.
writeEU4Decisions :: (EU4Info g, MonadIO m) => PPT g m ()
writeEU4Decisions = do
    decisions <- getDecisions
    let pathedDecisions :: [Feature EU4Decision]
        pathedDecisions = map (\dec -> Feature {
                                        featurePath = dec_path dec
                                    ,   featureId = Just (dec_name dec)
                                    ,   theFeature = Right dec })
                              (HM.elems decisions)
    writeFeatures "decisions"
                  pathedDecisions
                  pp_decision

-- | Present a parsed decision.
pp_decision :: (EU4Info g, Monad m) => EU4Decision -> PPT g m Doc
pp_decision dec = do
    version <- gets (gameVersion . getSettings)
    pot_pp'd    <- scope EU4Country (ppScript (dec_potential dec))
    allow_pp'd  <- scope EU4Country (ppScript (dec_allow dec))
    effect_pp'd <- setIsInEffect True (scope EU4Country (ppScript (dec_effect dec)))
    mawd_pp'd   <- mapM ((imsg2doc =<<) . ppAiWillDo) (dec_ai_will_do dec)
    let name = dec_name dec
        nameD = Doc.strictText name
    name_loc <- getGameL10n (name <> "_title")
    return . mconcat $
        ["<section begin=", nameD, "/>"
        ,"{{Decision", PP.line
        ,"| version = ", Doc.strictText version, PP.line
        ,"| decision_id = ", nameD, PP.line
        ,"| decision_name = ", Doc.strictText name_loc, PP.line
        ,maybe mempty
               (\txt -> mconcat ["| decision_text = ", Doc.strictText txt, PP.line])
               (dec_text dec)
        ,"| potential = ", PP.line, pot_pp'd, PP.line
        ,"| allow = ", PP.line, allow_pp'd, PP.line
        ,"| effect = ", PP.line, effect_pp'd, PP.line
        ] ++
        flip (maybe []) mawd_pp'd (\awd_pp'd ->
            ["| comment = AI decision factors:", PP.line
            ,awd_pp'd, PP.line]) ++
        ["}}" -- no line, causes unwanted extra space
        ,"<section end=", nameD, "/>"
        ]

findInStmt :: Text -> GenericStatement -> [Text]
findInStmt effect stmt@[pdx| $lhs = @scr |] | lhs == effect = case getId scr of
    Just actionId -> [actionId]
    _ -> trace ("Unrecognized estate action id: " ++ show stmt) []
    where
        getId :: [GenericStatement] -> Maybe Text
        getId [] = Nothing
        getId (stmt@[pdx| estate_action = ?!id |] : _) = case id of
            Just (Left n) -> Just $ T.pack (show (n :: Int))
            Just (Right t) -> Just t
            _ -> trace ("Invalid estate action statement: " ++ show stmt) Nothing
        getId (_ : ss) = getId ss

findInStmt effect [pdx| %_ = @scr |] = findInStmts effect scr
findInStmt _ _ = []

findInStmts :: Text -> [GenericStatement] -> [Text]
findInStmts effect = concatMap (findInStmt effect)

-- | find decisions which enact estate actions and the privileges which enable the estate actions
findEstateActions :: [EU4Decision] -> GenericScript -> Text -> HashMap Text EU4EstateAction
findEstateActions evts privilegeScripts scriptedEffectsForEstates = addScripts (findInPrivileges (HM.fromList (concatMap findInDecision evts)) privilegeScripts) scriptedEffectsForEstates
    where
        findInDecision :: EU4Decision -> [(Text, EU4EstateAction)]
        findInDecision dec = map (\actionName -> (actionName, EU4EstateAction actionName dec "" [])) (findInStmts "estate_action" (dec_effect dec))

        findInPrivileges :: HashMap Text EU4EstateAction -> GenericScript -> HashMap Text EU4EstateAction
        findInPrivileges allActions scr = foldl' findInPrivilege allActions scr

        findInPrivilege :: HashMap Text EU4EstateAction -> GenericStatement -> HashMap Text EU4EstateAction
        findInPrivilege allActions stmt@[pdx| $lhs = @scr |] = addPrivileges allActions lhs (findInStmts "enable_estate_action" scr)
        findInPrivilege allActions _ = allActions

        addPrivileges :: HashMap Text EU4EstateAction -> Text -> [Text] -> HashMap Text EU4EstateAction
        addPrivileges allActions privilege unlockedActions = foldl' (addPrivilege privilege) allActions unlockedActions

        addPrivilege :: Text -> HashMap Text EU4EstateAction -> Text -> HashMap Text EU4EstateAction
        addPrivilege privilege allActions unlockedAction = HM.adjust (\ action -> action { eaPrivilege = privilege}) unlockedAction allActions

        addScripts :: HashMap Text EU4EstateAction -> Text -> HashMap Text EU4EstateAction
        addScripts allActions scriptedEffectsForEstates = HM.mapWithKey (addScript scriptedEffectsForEstates) allActions

        addScript :: Text -> Text -> EU4EstateAction -> EU4EstateAction
        addScript scriptedEffectsForEstates name action = action { eaScript = getScript ("estate_action_" <> name) scriptedEffectsForEstates}

        getScript :: Text -> Text -> GenericScript
        getScript effectName scriptedEffectsForEstates = do
            let regex = RE.makeRegexOpts RE.defaultCompOpt{RE.multiline=False} RE.defaultExecOpt (effectName <> " = {((\r?\n[^}][^\n\r]*)*)\r?\n}")
                (_before, match, after, effectText:_othersubmatches) = RE.match regex scriptedEffectsForEstates :: (Text, Text, Text, [Text])
            readScriptFromText effectText
