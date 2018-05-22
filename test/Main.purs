module Test.Main where

import Test.Unit.Main (runTest)
import Test.Unit.Console (TESTOUTPUT)

import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Ref (REF)
import Control.Monad.Eff.Random (RANDOM)
import Control.Monad.Eff.Exception (EXCEPTION)
import Control.Monad.Eff.Console (CONSOLE)
import Control.Monad.Eff.Now (NOW)
import Control.Monad.Aff.AVar (AVAR)

import DOM (DOM)
import DOM.JSDOM (JSDOM)
import Graphics.Canvas (CANVAS)

import Test.Elm.TextTest as TextTest
import Test.Elm.Graphics.StaticElementTest as StaticElementTest

import Prelude (Unit, discard)


main :: Eff
    ( testOutput :: TESTOUTPUT
    , avar :: AVAR
    , random :: RANDOM
    , exception :: EXCEPTION
    , err :: EXCEPTION
    , console :: CONSOLE
    , ref :: REF
    , now :: NOW
    , canvas :: CANVAS
    , dom :: DOM
    , jsdom :: JSDOM
    ) Unit

main =
    runTest do
        TextTest.tests
        StaticElementTest.tests
