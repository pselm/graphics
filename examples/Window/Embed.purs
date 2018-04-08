module Examples.Window.Embed where


import Elm.Window
import Elm.Signal (DELAY, Signal, setup, runSignal, map)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (class MonadEff, liftEff)
import Control.Monad.Eff.Ref (REF)
import Control.Monad.Eff.Console (CONSOLE, log)
import Control.Monad.Except (runExcept)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Eff.Now (NOW)
import DOM.HTML (window)
import DOM.HTML.Types (htmlDocumentToNonElementParentNode, readHTMLElement)
import DOM.HTML.Window (document)
import DOM.Node.NonElementParentNode (getElementById)
import DOM.Node.Types (ElementId(..))
import DOM (DOM)
import Prelude (class Show, show, bind, discard, Unit, (<<<), (<>), ($), (>>=))
import Data.Nullable (toMaybe)
import Data.Maybe (Maybe(..))
import Partial.Unsafe (unsafeCrashWith)
import Data.Either (Either(..))
import Unsafe.Coerce (unsafeCoerce)


-- I haven't implemented HTML stuff yet, so just write things to the console.log for the moment
logWindow ::
    ∀ e m a. Show a => MonadEff (ref :: REF | e) m =>
    String -> WindowCallback m (Signal a) -> WindowCallback m Unit

logWindow label signal = do
    sig <- signal
    printer <- lift $ map (log <<< (_ <> (" <- " <> label)) <<< show) sig
    lift $ runSignal printer


main :: ∀ e. Eff (ref :: REF, now :: NOW, delay :: DELAY, console :: CONSOLE, dom :: DOM | e) Unit
main =
    setup do
        doc <- liftEff $
            window >>= document

        node <- liftEff $
            getElementById (ElementId "embed") (htmlDocumentToNonElementParentNode doc)

        case node of
            Just element ->
                case runExcept $ readHTMLElement $ unsafeCoerce element of
                    Left err ->
                        unsafeCrashWith $ show err

                    Right htmlElement ->
                        setupWindow htmlElement do
                            logWindow "width" width
                            logWindow "height" height

            Nothing ->
                unsafeCrashWith "Didn't find the 'embed' node."
