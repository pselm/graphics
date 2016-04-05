module Examples.Time.Every where


import Elm.Signal (DELAY, setup, runSignal)
import Elm.Time (every)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (log)
import Control.Monad.Eff.Ref (REF)
import Control.Monad.Eff.Console (CONSOLE)
import DOM.Timer (Timer)
import Data.Date (Now)
import Prelude (show, bind, Unit)


main :: forall e. Eff (ref :: REF, now :: Now, delay :: DELAY, console :: CONSOLE, timer :: Timer | e) Unit
main =
    setup do
        let
            logger time =
                log (show time)

        timer <- every 5000.0
        runner <- Elm.Signal.map logger timer
        runSignal runner


