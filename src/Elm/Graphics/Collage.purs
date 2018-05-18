
-- | The collage API is for freeform graphics. You can move, rotate, scale, etc.
-- | all sorts of forms including lines, shapes, images, and elements.
-- |
-- | Collages use the same coordinate system you might see in an algebra or physics
-- | problem. The origin (0,0) is at the center of the collage, not the top left
-- | corner as in some other graphics libraries. Furthermore, the y-axis points up,
-- | so moving a form 10 units in the y-axis will move it up on screen.

module Elm.Graphics.Collage
    ( Collage, makeCollage, collage, toElement
    , Form, toForm, filled, textured, gradient, outlined, traced, text, outlinedText
    , move, moveX, moveY, scale, rotate, alpha
    , group, groupTransform
    , Shape, rect, oval, square, circle, ngon, polygon
    , Path, segment, path
    , solid, dashed, dotted, LineStyle, LineCap(..), LineJoin(..), defaultLine
    ) where


import Control.Bind ((=<<), (>=>))
import Control.Comonad (extract)
import Control.Monad (when)
import Control.Monad.Eff (Eff, untilE)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (EXCEPTION)
import Control.Monad.Reader.Class (asks)
import Control.Monad.Reader.Trans (ReaderT, runReaderT)
import Control.Monad.ST (newSTRef, readSTRef, writeSTRef, runST)
import Control.Monad.State.Class (gets, modify)
import Control.Monad.State.Trans (StateT, evalStateT)
import DOM (DOM)
import DOM.HTML.Types (Window)
import DOM.Node.Element (setAttribute)
import DOM.Node.Node (nodeName, removeChild, appendChild, insertBefore, firstChild, nextSibling)
import DOM.Node.Types (Document, Node, elementToNode)
import DOM.Node.Types (Element) as DOM
import DOM.Renderable (class Renderable, AnyRenderable, Position(..), EffDOM, renderIntoDOM, toAnyRenderable)
import Data.Bifunctor (bimap)
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.List (List(..), (..), (:), snoc, toUnfoldable, head, tail, reverse)
import Data.List.Zipper (Zipper(..), down)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Nullable (toMaybe)
import Data.Traversable (traverse_)
import Data.Tuple (Tuple(..), fst, snd)
import Elm.Basics (Float)
import Elm.Color (Color, Gradient, black, toCss, toCanvasGradient)
import Elm.Graphics.Element (Element)
import Elm.Graphics.Element (fromRenderable) as Element
import Elm.Graphics.Internal (createNode, setStyle, getDimensions, measure, addTransform, documentToHtmlDocument, documentForNode, defaultView)
import Elm.Text (Text, drawCanvas)
import Elm.Transform2D (Transform2D)
import Elm.Transform2D (identity, multiply, rotation, matrix, toCSS) as T2D
import Global (isNaN)
import Graphics.Canvas (Context2D, CANVAS, CanvasElement, PatternRepeat(Repeat))
import Graphics.Canvas (LineCap(..), LineJoin(..), setLineWidth, setLineCap, setStrokeStyle, setGlobalAlpha, restore, setFillStyle, setPatternFillStyle, setGradientFillStyle, beginPath, getContext2D, lineTo, moveTo, scale, stroke, fillText, strokeText, rotate, save, transform, tryLoadImage, createPattern, fill, translate, drawImageFull, setLineJoin, setMiterLimit) as Canvas
import Math (pi, cos, sin, sqrt, (%))
import Prelude (class Eq, eq, not, (<<<), (>>>), Unit, unit, (||), bind, discard, (>>=), pure, void, (*), (/), ($), (#), map, (<$>), (<#>), (+), (-), (<>), show, (<), negate, (/=), (==))
import Unsafe.Coerce (unsafeCoerce)


-- | A visual `Form` has a shape and texture. This can be anything from a red
-- | square to a circle textured with stripes.
newtype Form = Form
    { theta :: Number
    , scale :: Number
    , x :: Number
    , y :: Number
    , alpha :: Number
    , basicForm :: BasicForm
    }


data FillStyle
    = Solid Color
    | Texture String
    | Grad Gradient

instance eqFillStyle :: Eq FillStyle where
    eq (Solid c1) (Solid c2) = eq c1 c2
    eq (Texture s1) (Texture s2) = eq s1 s2
    eq (Grad g1) (Grad g2) = eq g1 g2
    eq _ _ = false


-- | The shape of the ends of a line.
data LineCap
    = Flat
    | Round
    | Padded

instance eqLineCap :: Eq LineCap where
    eq Flat Flat = true
    eq Round Round = true
    eq Padded Padded = true
    eq _ _ = false


lineCap2Canvas :: LineCap -> Canvas.LineCap
lineCap2Canvas Flat = Canvas.Butt
lineCap2Canvas Round = Canvas.Round
lineCap2Canvas Padded = Canvas.Square


-- | The shape of the &ldquo;joints&rdquo; of a line, where each line segment
-- | meets. `Sharp` takes an argument to limit the length of the joint. This
-- | defaults to 10.
data LineJoin
    = Smooth
    | Sharp Float
    | Clipped

instance eqLineJoin :: Eq LineJoin where
    eq Smooth Smooth = true
    eq (Sharp f1) (Sharp f2) = eq f1 f2
    eq Clipped Clipped = true
    eq _ _ = false


-- | Set the current line join type.
setLineJoin :: ∀ e. LineJoin -> Context2D -> Eff (canvas :: CANVAS | e) Context2D

setLineJoin Smooth =
    Canvas.setLineJoin Canvas.RoundJoin >=>
    Canvas.setMiterLimit 10.0

setLineJoin (Sharp limit) =
    Canvas.setLineJoin Canvas.MiterJoin >=>
    Canvas.setMiterLimit limit

setLineJoin Clipped =
    Canvas.setLineJoin Canvas.BevelJoin >=>
    Canvas.setMiterLimit 10.0


-- | All of the attributes of a line style. This lets you build up a line style
-- | however you want. You can also update existing line styles with record updates.
type LineStyle =
    { color :: Color
    , width :: Float
    , cap :: LineCap
    , join :: LineJoin
    , dashing :: List Int
    , dashOffset :: Int
    }


-- | The default line style, which is solid black with flat caps and sharp joints.
-- | You can use record updates to build the line style you
-- | want. For example, to make a thicker line, you could say:
-- |
-- |     defaultLine { width = 10 }
defaultLine :: LineStyle
defaultLine =
    { color: black
    , width: 1.0
    , cap: Flat
    , join: Sharp 10.0
    , dashing: Nil
    , dashOffset: 0
    }


-- | Create a solid line style with a given color.
solid :: Color -> LineStyle
solid clr =
    defaultLine
        { color = clr }


-- | Create a dashed line style with a given color. Dashing equals `[8,4]`.
dashed :: Color -> LineStyle
dashed clr =
    defaultLine
        { color = clr
        , dashing = (8 : 4 : Nil)
        }


-- | Create a dotted line style with a given color. Dashing equals `[3,3]`.
dotted :: Color -> LineStyle
dotted clr =
    defaultLine
        { color = clr
        , dashing = (3 : 3 : Nil)
        }


type Point = Tuple Float Float


data BasicForm
    = FPath LineStyle (List Point)
    | FShape ShapeStyle (List Point)
    | FOutlinedText LineStyle Text
    | FText Text
    | FImage Int Int {top :: Int, left :: Int} String
    | FElement AnyRenderable
    | FGroup Transform2D (List Form)


data ShapeStyle
    = Line LineStyle
    | Fill FillStyle


form :: BasicForm -> Form
form f =
    Form
        { theta: 0.0
        , scale: 1.0
        , x: 0.0
        , y: 0.0
        , alpha: 1.0
        , basicForm: f
        }


fill :: FillStyle -> Shape -> Form
fill style (Shape shape) =
    form (FShape (Fill style) shape)


-- | Create a filled in shape.
filled :: Color -> Shape -> Form
filled color = fill (Solid color)


-- | Create a textured shape. The texture is described by some url and is
-- | tiled to fill the entire shape.
textured :: String -> Shape -> Form
textured src = fill (Texture src)


-- | Fill a shape with a gradient.
gradient :: Gradient -> Shape -> Form
gradient grad = fill (Grad grad)


-- | Outline a shape with a given line style.
outlined :: LineStyle -> Shape -> Form
outlined style (Shape shape) =
    form (FShape (Line style) shape)


-- | Trace a path with a given line style.
traced :: LineStyle -> Path -> Form
traced style (Path p) =
    form (FPath style p)


-- | Create a sprite from a sprite sheet. It cuts out a rectangle
-- | at a given position.
sprite :: Int -> Int -> {top :: Int, left :: Int} -> String -> Form
sprite a b c d = form $ FImage a b c d


-- | Turn any `Element` into a `Form`. This lets you use text, gifs, and video
-- | in your collage. This means you can move, rotate, and scale
-- | an `Element` however you want.
-- |
-- | In fact, this works with any `Renderable`, not just Elements.
toForm :: ∀ a. (Renderable a) => a -> Form
toForm = form <<< FElement <<< toAnyRenderable


-- | Flatten many forms into a single `Form`. This lets you move and rotate them
-- | as a single unit, making it possible to build small, modular components.
-- | Forms will be drawn in the order that they are listed, as in `collage`.
group :: List Form -> Form
group fs =
    form (FGroup T2D.identity fs)


-- | Flatten many forms into a single `Form` and then apply a matrix
-- | transformation. Forms will be drawn in the order that they are listed, as in
-- | `collage`.
groupTransform :: Transform2D -> List Form -> Form
groupTransform matrix fs =
    form (FGroup matrix fs)


-- | Move a form by the given amount (x, y). This is a relative translation so
-- | `(move (5,10) form)` would move `form` five pixels to the right and ten pixels up.
move :: Tuple Float Float -> Form -> Form
move (Tuple x y) (Form f) =
    Form $ f
        { x = f.x + x
        , y = f.y + y
        }


-- | Move a shape in the x direction. This is relative so `(moveX 10 form)` moves
-- | `form` 10 pixels to the right.
moveX :: Float -> Form -> Form
moveX x (Form f) =
    Form $
        f { x = f.x + x }


-- | Move a shape in the y direction. This is relative so `(moveY 10 form)` moves
-- | `form` upwards by 10 pixels.
moveY :: Float -> Form -> Form
moveY y (Form f) =
    Form $
        f { y = f.y + y }


-- | Scale a form by a given factor. Scaling by 2 doubles both dimensions,
-- | and quadruples the area.
scale :: Float -> Form -> Form
scale s (Form f) =
    Form $
        f { scale = f.scale * s }


-- | Rotate a form by a given angle. Rotate takes standard Elm angles (radians)
-- | and turns things counterclockwise. So to turn `form` 30&deg; to the left
-- | you would say, `(rotate (degrees 30) form)`.
rotate :: Float -> Form -> Form
rotate t (Form f) =
    Form $
        f { theta = f.theta + t }


-- | Set the alpha of a `Form`. The default is 1, and 0 is totally transparent.
alpha :: Float -> Form -> Form
alpha a (Form f) =
    Form $
        f { alpha = a }


newtype Collage = Collage
    { w :: Int
    , h :: Int
    , forms :: List Form
    }


instance renderableCollage :: Renderable Collage where
    render document a =
        elementToNode <$> render document a

    update rendered new =
        update true rendered.result new


-- | Create a `Collage` with certain dimensions and content. It takes width and height
-- | arguments to specify dimensions, and then a list of 2D forms to decribe the content.
-- |
-- | The forms are drawn in the order of the list, i.e., `collage w h (a : b : Nil)` will
-- | draw `b` on top of `a`.
-- |
-- | Note that this normally might be called `collage`, but Elm uses that for the function
-- | that actually creates an `Element`.
makeCollage :: Int -> Int -> List Form -> Collage
makeCollage w h forms = Collage {w, h, forms}


-- | Create a collage `Element` with certain dimensions and content. It takes width and height
-- | arguments to specify dimensions, and then a list of 2D forms to decribe the content.
-- |
-- | The forms are drawn in the order of the list, i.e., `collage w h (a : b : Nil)` will
-- | draw `b` on top of `a`.
-- |
-- | To make a `Collage` without immediately turning it into an `Element`, see `makeCollage`.
collage :: Int -> Int -> List Form -> Element
collage a b c = toElement (makeCollage a b c)


-- | Turn a `Collage` into an `Element`.
toElement :: Collage -> Element
toElement c@(Collage props) =
    Element.fromRenderable props.w props.h c


-- | A 2D path. Paths are a sequence of points. They do not have a color.
newtype Path = Path (List (Tuple Float Float))


-- | Create a path that follows a sequence of points.
path :: List (Tuple Float Float) -> Path
path = Path


-- | Create a path along a given line segment.
segment :: Tuple Float Float -> Tuple Float Float -> Path
segment p1 p2 =
    Path (p1 : p2 : Nil)


-- | A 2D shape. Shapes are closed polygons. They do not have a color or
-- | texture, that information can be filled in later.
newtype Shape = Shape (List (Tuple Float Float))


-- | Create an arbitrary polygon by specifying its corners in order.
-- | `polygon` will automatically close all shapes, so the given list
-- | of points does not need to start and end with the same position.
polygon :: List (Tuple Float Float) -> Shape
polygon = Shape


-- | A rectangle with a given width and height, centered on the origin.
rect :: Float -> Float -> Shape
rect w h =
    let
        hw = w / 2.0
        hh = h / 2.0

    in
        Shape
            ( Tuple (-hw) (-hh)
            : Tuple (-hw) hh
            : Tuple hw hh
            : Tuple hw (-hh)
            : Nil
            )


-- | A square with a given edge length, centred on the origin.
square :: Float -> Shape
square n = rect n n


-- | An oval with a given width and height.
oval :: Float -> Float -> Shape
oval w h =
    let
        n = 50
        t = 2.0 * pi / toNumber n
        hw = w / 2.0
        hh = h / 2.0

        f i =
            let
                ti = t * toNumber i

            in
                Tuple
                    (hw * cos ti)
                    (hh * sin ti)

    in
        Shape $
            map f (0 .. (n - 1))


-- | A circle with a given radius.
circle :: Float -> Shape
circle r = oval (2.0 * r) (2.0 * r)


-- | A regular polygon with N sides. The first argument specifies the number
-- | of sides and the second is the radius. So to create a pentagon with radius
-- | 30 you would say:
-- |
-- |     ngon 5 30
ngon :: Int -> Float -> Shape
ngon n r =
    let
        t = 2.0 * pi / (toNumber n)
        f i =
            Tuple
                (r * cos (t * (toNumber i)))
                (r * sin (t * (toNumber i)))

    in
        Shape $
            map f (0 .. (n - 1))


-- | Create some text. Details like size and color are part of the `Text` value
-- | itself, so you can mix colors and sizes and fonts easily.
text :: Text -> Form
text = form <<< FText


-- | Create some outlined text. Since we are just outlining the text, the color
-- | is taken from the `LineStyle` attribute instead of the `Text`.
outlinedText :: LineStyle -> Text -> Form
outlinedText ls t =
    form (FOutlinedText ls t)


---------
-- RENDER
---------

render :: ∀ e. Document -> Collage -> EffDOM e DOM.Element
render document model@(Collage {w, h}) = do
    div <- createNode document "div"

    setStyle "overflow" "hidden" div
    setStyle "position" "relative" div
    setStyle "width" ((show w) <> "px") div
    setStyle "height" ((show h) <> "px") div

    void $ update true (elementToNode div) model
    pure div


-- The idea is that the div is a node created by `render` ... that is, a div
-- which should contain the rendering of the collage. The div may be empty,
-- or it may have been previously rendered by a call to `update`.
--
-- The supplied collage contains possibly multiple forms, and each form might
-- itself be an `Element`, or represent a group of forms. So, there is a need
-- to deal with a bit of a tree of possibilities, you might say.
--
-- The original Javascript code does a number of clever things with a `formStepper`
-- and a `nodeStepper`. The cleverness appears to have two purposes. One is
-- to re-use existing Canvas elements that had been previously rendered, rather
-- than deleting them and creating new ones. The other is to help manage the
-- tree of possibilities ... that is, the possibility of Elements or groups of forms.
--
-- I had originally tried a more "literal" translation of some of this cleverness
-- to Purescript, but it proved to be difficult to follow (what was clever in
-- Javascript doesn't necessarily translate easily into Purescript). So, now I'm
-- trying to do something that seems equivalent in purpose, but not having quite
-- the same structure. So, ultimately I'll need to test it against example code
-- to see that it produces the same results.
update :: ∀ e. Boolean -> Node -> Collage -> EffDOM e Node
update redoWhenImageLoads parent c@(Collage {forms}) = do
    evalUpdate redoWhenImageLoads parent c $
        traverse_ renderForm forms

    pure parent


-- There are a bunch of inter-related functions used in the `update` process that all want
-- some params or state. So, we define a ReaderT and StateT to help us out. For some
-- reason, it seemed to solve some problems to make them a newtype instead of a type ...
-- I didn't make a note of exactly what the problems were.
newtype UpdateState = UpdateState
    -- The child we should currently use, or Nothing if we're at the end
    { currentChild :: Maybe Node

    -- Remember a context that we should be drawing into right now. If `Nothing`, it means
    -- that we'll need to construct a new context next time we need one. (At which point,
    -- we'll store it here).
    , context :: Maybe Context2D

    -- When we get an FGroup, we apply the group's alpha and transforms to the context
    -- before we recurse on the group (and restore our context after). This works fine
    -- when we're still using the same context. However, when we hit an FElement, we
    -- start a new div, and then if we need a new context afterwards, we start a new
    -- Canvas, rather than re-using the old one. (I'm not entirely sure why the original
    -- code does this ... perhaps to get the layering right, since if you re-used the old
    -- Canvas then you'd be in the wrong layer relative to the FElement). In any event, if we're
    -- making a new Canvas in the middle of (possibly nested) FGroups, we need to
    -- re-apply the alpha and the transforms when we create the new Canvas. So, we
    -- keep track of them here ...
    , groupSettings :: List { alpha :: Float, trans :: Transform2D }
    }


newtype UpdateEnv = UpdateEnv
    -- The original Javascript sets up callbacks that re-run the `update` function after
    -- images load. This is probably because at that time the size of the image will be
    -- known. We keep track here of whether to do that, so that we can disable it when
    -- we're doing it. That is, to avoid infinite loops. (The original Javascript presumably
    -- also avoids infinite loops, but we're using a somewhat different mechanism).
    { redoWhenImageLoads :: Boolean

    -- The collage we're working on.
    , collage :: Collage

    -- The node we're rendering into
    , parent :: Node

    -- The devicePixelRatio
    , devicePixelRatio :: Float

    -- The document we're rendering into
    , document :: Document
    }


type Update m a = ReaderT UpdateEnv (StateT UpdateState m) a
type UpdateEffects e a = Update (Eff (canvas :: CANVAS, dom :: DOM, err :: EXCEPTION | e)) a


evalUpdate :: ∀ e a. Boolean -> Node -> Collage -> UpdateEffects e a -> EffDOM e a
evalUpdate redoWhenImageLoads parent c cb = do
    document <-
        documentForNode parent

    ratio <-
        documentToHtmlDocument document
        >>= (defaultView >>> toMaybe)
        <#> devicePixelRatio
        # fromMaybe (pure 1.0)

    current <-
        liftEff $
            firstChild parent

    let
        env =
            UpdateEnv
                { redoWhenImageLoads
                , collage: c
                , parent
                , devicePixelRatio: ratio
                , document
                }

        state =
            UpdateState
                { currentChild: current
                , context: Nothing
                , groupSettings: Nil
                }

    evalStateT (runReaderT cb env) state


setStrokeStyle :: ∀ e. LineStyle -> UpdateEffects e Context2D
setStrokeStyle style = do
    ctx <- getContext

    liftEff do
        void $ Canvas.setLineWidth style.width ctx
        void $ Canvas.setLineCap (lineCap2Canvas style.cap) ctx
        void $ setLineJoin style.join ctx
        Canvas.setStrokeStyle (toCss style.color) ctx


setFillStyle :: ∀ e. FillStyle -> UpdateEffects e Context2D
setFillStyle style = do
    ctx <- getContext

    case style of
        Solid c ->
            liftEff $
                Canvas.setFillStyle (toCss c) ctx

        Texture t -> do
            texture t
            pure ctx

        Grad g ->
            liftEff do
                grad <- toCanvasGradient g ctx
                Canvas.setGradientFillStyle grad ctx


-- Note that this traces first to last, whereas Elm traces from last to
-- first. If this turns out to matter, I can reverse the list.
trace :: ∀ e. Boolean -> List Point -> UpdateEffects e Context2D
trace closed list = do
    ctx <- getContext

    liftEff
        case list of
            Cons (Tuple firstX firstY) rest -> do
                void $ Canvas.moveTo ctx firstX firstY

                for_ rest \(Tuple nextX nextY) ->
                    Canvas.lineTo ctx nextX nextY

                if closed
                    then Canvas.lineTo ctx firstX firstY
                    else pure ctx

            _ ->
                pure ctx


line :: ∀ e. LineStyle -> Boolean -> List Point -> UpdateEffects e Context2D
line style closed pointList = do
    ctx <- getContext

    case pointList of
        -- Note that elm draws from the last point to the first, whereas we're
        -- drawing from the first to the last. If this turns out to matter, we
        -- can always start by reversing the list.
        Cons firstPoint@(Tuple firstX firstY) remainingPoints -> do

            -- We have some points. So, check the dashing.
            case style.dashing of
                Cons firstDash remainingDashes ->

                    -- We have some dashing.
                    -- Note that Elm implements the Canvas `setLineDash` manually, perhaps for
                    -- back-compat with IE <11. So, we'll do it too!

                    -- The rest of this is easiest, I'm afraid, if we allow a bit of
                    -- mutation. At least, at a first approximation. I should probably
                    -- put all of this inside a state monad, but I'll try runST first.
                    -- I suppose that what's really going on here is that we're iterating
                    -- through both the points and the dashes, and each has to give up
                    -- control to the other at certain points. So, probably the right way
                    -- to do this would be with continuations. But that might be overkill.
                    liftEff $ void $ runST do

                        -- The dashes are basically a list of on/off lengths which we
                        -- want to iterate through, and then go back to the beginning.
                        -- I think this is easiest with a zipper, though in fact you
                        -- could construct something even more specific. We remember
                        -- the firstPattern so we can go back to the beginning easily.
                        let firstPattern = Zipper Nil firstDash remainingDashes
                        pattern <- newSTRef firstPattern

                        -- We also need to keep track of how much is left in the current
                        -- segment of the pattern ... that is, how much length we can
                        -- draw or skip until we should look at the next segment
                        leftInPattern <- newSTRef (toNumber firstDash)

                        -- Here we keep track of whether we're drawing or not drawing.
                        -- We start by drawing.
                        drawing <- newSTRef true

                        -- And, we'll want to track where we are
                        position <- newSTRef firstPoint

                        -- First, move to our first point
                        void $ Canvas.moveTo ctx firstX firstY

                        let
                            -- If we're closed, we add the first point to those remaining
                            points =
                                if closed
                                    then snoc remainingPoints firstPoint
                                    else remainingPoints

                        -- Now, we iterate over the points
                        for_ points \(Tuple nextX nextY) ->
                            untilE do
                                currentPosition <- readSTRef position
                                currentlyDrawing <- readSTRef drawing
                                currentSegment <- readSTRef leftInPattern

                                let
                                    dx = nextX - (fst currentPosition)
                                    dy = nextY - (snd currentPosition)
                                    distance = sqrt ((dx * dx) + (dy * dy))
                                    operation = if currentlyDrawing then Canvas.lineTo else Canvas.moveTo

                                if distance < currentSegment
                                    then do
                                        -- Aha, we'll complete this point with the current
                                        -- segment. So, first we draw or move, to our
                                        -- destination.
                                        void $ operation ctx nextX nextY

                                        -- Now, we'll remain with our current segment ... but
                                        -- we've used some of it, so we decrement
                                        void $ writeSTRef leftInPattern (currentSegment - distance)

                                        -- And record our new position
                                        void $ writeSTRef position (Tuple nextX nextY)

                                        -- And, we tell the untilE that we're done with this point,
                                        -- so move to the next destination
                                        pure true

                                    else do
                                        -- We've got more distance to travel than our current segment
                                        -- length. So, first we need to calculate what position we'll
                                        -- end up with for this segment.
                                        let
                                            nextPosition =
                                                currentPosition #
                                                    bimap
                                                        (\x -> x + (dx * currentSegment / distance))
                                                        (\y -> y + (dy * currentSegment / distance))

                                        -- So, actually do the operation
                                        void $ operation ctx (fst nextPosition) (snd nextPosition)

                                        -- And record our new position
                                        void $ writeSTRef position nextPosition

                                        -- Now, we've used up this segment, so we need to flip our
                                        -- drawing state.
                                        void $ writeSTRef drawing (not currentlyDrawing)

                                        -- And get the next pattern
                                        currentPattern <- readSTRef pattern

                                        -- We go down, and if at end back to first
                                        let nextPattern = fromMaybe firstPattern (down currentPattern)

                                        void $ writeSTRef pattern nextPattern
                                        void $ writeSTRef leftInPattern (toNumber (extract nextPattern))

                                        -- And, tell the untilE that we're not done with this destination yet
                                        pure false

                        -- We're done all the points ... just return the ctx
                        pure ctx

                _ ->
                    -- This the case where we have no dashing, so we can just trace the line
                    void $ trace closed pointList

            -- In either event, with or without dashing, we scale and stroke
            liftEff do
                void $ Canvas.scale {scaleX: 1.0, scaleY: (-1.0)} ctx
                Canvas.stroke ctx

        _ ->
            -- This is the case where we have an empty path, so there's nothing to do
            pure ctx


drawLine :: ∀ e. LineStyle -> Boolean -> List Point -> UpdateEffects e Context2D
drawLine style closed points = do
    void $ setStrokeStyle style
    line style closed points


texture :: ∀ e. String -> UpdateEffects e Unit
texture src = do
    ctx <- getContext

    liftEff $
        Canvas.tryLoadImage src \maybeSource ->
            for_ maybeSource \source -> do
                pattern <-
                    Canvas.createPattern source Repeat ctx

                void $ Canvas.setPatternFillStyle pattern ctx

    pure unit
            -- redo


drawShape :: ∀ e. FillStyle -> Boolean -> List Point -> UpdateEffects e Context2D
drawShape style closed points = do
    ctx <- getContext

    liftEff $ void $
        Canvas.scale {scaleX: 1.0, scaleY: (-1.0)} ctx

    void $ trace closed points
    void $ setFillStyle style

    liftEff $
        Canvas.fill ctx


-- TEXT RENDERING

-- Returns true if setLineDash was available, false if not.
foreign import setLineDash :: ∀ e. Array Int -> Context2D -> Eff (canvas :: CANVAS | e) Boolean


fillText :: ∀ e. Text -> UpdateEffects e Context2D
fillText t =
    getContext >>= liftEff <<< drawCanvas Canvas.fillText t


strokeText :: ∀ e. LineStyle -> Text -> UpdateEffects e Context2D
strokeText style t = do
    ctx <- getContext

    void $ setStrokeStyle style

    liftEff do
        when (style.dashing /= Nil) $ void $
            setLineDash (toUnfoldable style.dashing) ctx

        drawCanvas Canvas.strokeText t ctx


-- Should suggest adding this to Graphics.Canvas
foreign import globalAlpha :: ∀ e. Context2D -> Eff (canvas :: CANVAS | e) Number


formToMatrix :: Form -> Transform2D
formToMatrix (Form f) =
    let
        matrix =
            T2D.matrix f.scale 0.0 0.0 f.scale f.x f.y

    in
        if f.theta == 0.0
            then matrix
            else T2D.multiply matrix (T2D.rotation f.theta)


foreign import devicePixelRatio :: ∀ e. Window -> Eff (dom :: DOM | e) Number


-- So, we pull the original params to `update` out of the state, and call it again,
-- if redo was allowed. And, this time we don't allow redo ...
redo :: ∀ e. UpdateEffects e Unit
redo = do
    env <-
        asks \(UpdateEnv e) -> e

    when env.redoWhenImageLoads $
        liftEff $
            void $
                update false env.parent env.collage


drawInContext :: ∀ e a. Form -> UpdateEffects e a -> UpdateEffects e a
drawInContext (Form f) cb = do
    ctx <- getContext

    liftEff do
        void $ Canvas.save ctx

        when (f.x /= 0.0 || f.y /= 0.0) $ void $
            Canvas.translate
                { translateX: f.x
                , translateY: f.y
                }
                ctx

        when (f.theta /= 0.0) $ void $
            Canvas.rotate (f.theta % (pi * 2.0)) ctx

        when (f.scale /= 1.0) $ void $
            Canvas.scale { scaleX: f.scale, scaleY: f.scale } ctx

        when (f.alpha /= 1.0) do
            ga <- globalAlpha ctx
            void $ Canvas.setGlobalAlpha ctx (ga * f.alpha)
            pure unit

        void $ Canvas.beginPath ctx

    result <-
        cb

    liftEff $ void $
        Canvas.restore ctx

    pure result


-- Gets the alpha from our stack of group settings. Returns the first alpha, if
-- there is one, or 1.0.
getGroupAlpha :: ∀ e. UpdateEffects e Number
getGroupAlpha =
    gets \(UpdateState s) ->
        fromMaybe 1.0 (_.alpha <$> head s.groupSettings)


makeTransform :: ∀ e. {width :: Number, height :: Number} -> Form -> UpdateEffects e String
makeTransform dim f = do
    c <-
        asks \(UpdateEnv {collage: Collage c}) ->
            c

    let
        m =
            T2D.matrix
                1.0 0.0 0.0 (-1.0)
                (((toNumber c.w) - dim.width) / 2.0)
                (((toNumber c.h) - dim.height) / 2.0)

        m2 =
            T2D.multiply m (formToMatrix f)

    pure (T2D.toCSS m2)


{-
	function makeTransform(w, h, form, matrices)
	{
		var props = form.form._0._0.props;
		var m = A6( Transform.matrix, 1, 0, 0, -1,
					(w - props.width ) / 2,
					(h - props.height) / 2 );
		var len = matrices.length;
		for (var i = 0; i < len; ++i)
		{
			m = A2( Transform.multiply, m, matrices[i] );
		}
		m = A2( Transform.multiply, m, formToMatrix(form) );

		return 'matrix(' +
			str( m[0]) + ', ' + str( m[3]) + ', ' +
			str(-m[1]) + ', ' + str(-m[4]) + ', ' +
			str( m[2]) + ', ' + str( m[5]) + ')';
	}
-}


renderForm :: ∀ e. Form -> UpdateEffects e Context2D
renderForm f@(Form innerForm) = do
    ctx <- getContext
    document <- getDocument

    case innerForm.basicForm of
        FPath lineStyle points ->
            drawInContext f $
                drawLine lineStyle false points

        FImage w h pos src ->
            drawInContext f do
                liftEff $
                    Canvas.tryLoadImage src \maybeSource ->
                        for_ maybeSource \source -> do
                            void $ Canvas.scale { scaleX: 1.0, scaleY: (-1.0) } ctx
                            void $ Canvas.drawImageFull ctx source
                                (toNumber pos.top)
                                (toNumber pos.left)
                                (toNumber w)
                                (toNumber h)
                                (toNumber (-w) / 2.0)
                                (toNumber (-h) / 2.0)
                                (toNumber w)
                                (toNumber h)

                            pure unit
                            -- redo
                pure ctx

        FShape shapeStyle points ->
            drawInContext f $
                case shapeStyle of
                    Line lineStyle ->
                        drawLine lineStyle true points

                    Fill fillStyle ->
                        drawShape fillStyle false points

        FText t ->
            drawInContext f $
                fillText t

        FOutlinedText lineStyle t ->
            drawInContext f $
                strokeText lineStyle t

        FElement renderable -> do
            kid <-
                currentChild

            parent <-
                getParent

            wrapper <-
                liftEff
                    case kid of
                        Just k ->
                            case nodeToDiv k of
                                Just divKid -> do
                                    -- We've got a previous wrapper. Should check for
                                    -- an old renderable ...
                                    void $ renderIntoDOM ReplacingChildren (elementToNode divKid) renderable
                                    pure divKid

                                Nothing -> do
                                    -- It wasn't a div, so insert ...
                                    w <- createNode document "div"
                                    void $ insertBefore (elementToNode w) k parent
                                    void $ renderIntoDOM AfterLastChild (elementToNode w) renderable
                                    pure w

                        Nothing -> do
                            -- There were no more children, so append
                            w <- createNode document "div"
                            void $ appendChild (elementToNode w) parent
                            void $ renderIntoDOM AfterLastChild (elementToNode w) renderable
                            pure w

            dim <-
                liftEff do
                    -- If it's already in the document, getDimensions should work
                    inDoc <-
                        getDimensions wrapper

                    -- Otherwise, we'll have to measure it
                    if isNaN inDoc.width
                        then measure (elementToNode wrapper)
                        else pure inDoc

            -- Have to delay this until after getting the dimensions ...
            liftEff $
                setStyle "position" "absolute" wrapper

            trans <-
                makeTransform dim f

            liftEff $
                addTransform trans wrapper

            groupAlpha <-
                getGroupAlpha

            -- The original Javascript code also takes into account the opacity of the
            -- `Element`. Of course, I don't know that it is an `Element`, since I've
            -- generalized it to `Renderable`. But, I guess I could read back the
            -- current opacity from the style? Or, set these properties on a wrapper?
            -- Actually, using a wrapper probably makes the most sense ... TODO.
            liftEff $
                setStyle "opacity" (show (groupAlpha * innerForm.alpha)) wrapper

            moveToNextChild
            pure ctx

			
        FGroup transform forms -> do
            -- First, we figure out what our transform should be. It combines the
            -- scale, theta, x and y from the form with the additional transform
            -- from the group
            let trans = T2D.multiply transform (formToMatrix f)

            -- Now, get the new alpha we should use (given any groups already in the stack)
            groupAlpha <- (_ * innerForm.alpha) <$> getGroupAlpha

            -- We push the transform and alpha onto a stack, so that we can
            -- re-apply them if we end up on a new Canvas element while we're
            -- iterating the sub-forms
            putStuffOnTheStackOfGroupSettings { alpha: groupAlpha, trans }

            -- Then we save our context and actually apply the alpha and transform
            liftEff do
                void $ Canvas.save ctx
                void $ Canvas.transform trans ctx
                void $ Canvas.setGlobalAlpha ctx groupAlpha

            -- Now, traverse the forms and render them. Isn't this fun? The original
            -- Javascript code actually does something clever here to avoid the recursion.
            -- But I think I'll try the recursive version first and see if it causes any
            -- trouble. You wouldn't think that FGruops would go so deep as to exhaust
            -- the function stack.
            traverse_ renderForm forms

            -- So, we've rendered our forms, and possibly their sub-forms, and the
            -- sub-forms' sub-forms, and the sub-forms' sub-forms' sub-forms, and
            -- the sub-forms' sub-forms' sub-forms' sub-forms, and so on. So, it's
            -- time to restore the context, and pop the stuff off the stack of
            -- groupSettings.
            liftEff $ void $
                Canvas.restore ctx

            popStuffOffTheStackOfGroupSettings

            pure ctx


putStuffOnTheStackOfGroupSettings :: ∀ e. { alpha :: Number, trans :: Transform2D } -> UpdateEffects e Unit
putStuffOnTheStackOfGroupSettings stuff =
    modify \(UpdateState state) ->
        UpdateState $
            state
                { groupSettings = Cons stuff state.groupSettings
                }


popStuffOffTheStackOfGroupSettings :: ∀ e. UpdateEffects e Unit
popStuffOffTheStackOfGroupSettings =
    modify \(UpdateState state) ->
        UpdateState $
            state
                { groupSettings = fromMaybe Nil (tail state.groupSettings)
                }


makeCanvas :: ∀ e. UpdateEffects e CanvasElement
makeCanvas = do
    document
        <- getDocument

    canvas <-
        liftEff $
            createNode document "canvas"

    liftEff do
        setStyle "display" "block" canvas
        setStyle "position" "absolute" canvas

    void $ setCanvasProps canvas

    -- The unsafeCoerce should be fine, since we just created it and we know it's a canvas ...
    pure $
        unsafeCoerce canvas


setCanvasProps :: ∀ e. DOM.Element -> UpdateEffects e DOM.Element
setCanvasProps canvas = do
    env <-
        asks \(UpdateEnv {devicePixelRatio: dpr, collage: Collage coll}) ->
            {dpr, coll}

    liftEff do
        setStyle "width" ((show env.coll.w) <> "px") canvas
        setStyle "height" ((show env.coll.h) <> "px") canvas

        setAttribute "width" (show $ (toNumber env.coll.w) * env.dpr) canvas
        setAttribute "height" (show $ (toNumber env.coll.h) * env.dpr) canvas

    pure canvas


-- This unsafeCoerce should also be fine, since a CanvasElement must be a DOM.Element
canvasElementToElement :: CanvasElement -> DOM.Element
canvasElementToElement = unsafeCoerce


isCanvasElement :: Node -> Boolean
isCanvasElement node =
    nodeName node == "CANVAS"


nodeToCanvasElement :: Node -> Maybe CanvasElement
nodeToCanvasElement node =
    case nodeName node of
        "CANVAS" ->
            Just $ unsafeCoerce node

        _ ->
            Nothing


nodeToDiv :: Node -> Maybe DOM.Element
nodeToDiv node =
    case nodeName node of
        "DIV" ->
            Just $ unsafeCoerce node

        _ ->
            Nothing


currentChild :: ∀ e. UpdateEffects e (Maybe Node)
currentChild =
    gets \(UpdateState s) ->
        s.currentChild


moveToNextChild :: ∀ e. UpdateEffects e Unit
moveToNextChild = do
    current <-
        currentChild

    setNextChild =<<
        case current of
            Just node ->
                liftEff $ nextSibling node

            Nothing ->
                pure Nothing


setNextChild :: ∀ e. Maybe Node -> UpdateEffects e Unit
setNextChild node = do
    modify \(UpdateState s) ->
        UpdateState $
            s { currentChild = node }


getDocument :: ∀ e. UpdateEffects e Document
getDocument =
    asks \(UpdateEnv env) ->
        env.document


getParent :: ∀ e. UpdateEffects e Node
getParent =
    asks \(UpdateEnv env) ->
        env.parent


getContext :: ∀ e. UpdateEffects e Context2D
getContext = do
    state <-
        gets \(UpdateState s) -> s

    parent <-
        getParent

    case state.context of
        Just c ->
            pure c

        Nothing -> do
            current <-
                currentChild

            case current of
                Just node ->
                    case nodeToCanvasElement node of
                        Just canvas -> do
                            -- We have a canvas, so we'll re-use it, and increment the index
                            -- so we're now pointing at the next thing.
                            moveToNextChild

                            void $ setCanvasProps $
                                canvasElementToElement canvas

                            ctx <-
                                liftEff $
                                    Canvas.getContext2D canvas

                            useContext ctx

                        Nothing -> do
                            -- Move to the next child before we remove our reference point ...
                            moveToNextChild

                            -- Not a canvas, so remove it.
                            liftEff $ void $
                                removeChild node parent

                            -- And we recurse. Should figure out how to use purescript-tailrec
                            getContext

                Nothing -> do
                    -- We've run out of children. So, we make a new one.
                    -- We don't need to move the index, because we'll still need to make
                    -- a new one the next time.
                    canvas <- makeCanvas

                    ctx <- liftEff do
                        void $ appendChild (elementToNode (canvasElementToElement canvas)) parent
                        Canvas.getContext2D canvas

                    useContext ctx


useContext :: ∀ e. Context2D -> UpdateEffects e Context2D
useContext ctx = do
    modify \(UpdateState s) ->
        UpdateState $
            s { context = Just ctx }

    env <-
        asks \(UpdateEnv {devicePixelRatio: dpr, collage: Collage {w, h}}) ->
            {dpr, w, h}

    groupSettings <-
        gets \(UpdateState state) ->
            state.groupSettings

    liftEff do
        -- Start the alpha at 1.0 ... we'll restore the groupSettings below
        void $ Canvas.setGlobalAlpha ctx 1.0

        void $ Canvas.translate
            { translateX: (toNumber env.w) / 2.0 * env.dpr
            , translateY: (toNumber env.h) / 2.0 * env.dpr
            }
            ctx

        void $ Canvas.scale
            { scaleX: env.dpr
            , scaleY: -env.dpr
            }
            ctx

        for_ (reverse groupSettings) \setting -> do
            -- So, for each of the groupSettings that we've pushed on to the stack,
            -- we will have done a save in the previous context, and we'll expect
            -- to be able to do restores on the way back out. So, we'll do a save
            -- here before we re-apply each transform.
            void $ Canvas.save ctx
            void $ Canvas.transform setting.trans ctx
            void $ Canvas.setGlobalAlpha ctx setting.alpha

        pure ctx


forgetContext :: ∀ e. UpdateEffects e Unit
forgetContext =
    modify \(UpdateState s) ->
        UpdateState $
            s { context = Nothing }


clearRest :: ∀ e. UpdateEffects e Unit
clearRest = do
    child <-
        currentChild

    case child of
        Just c -> do
            parent <-
                asks \(UpdateEnv env) ->
                    env.parent

            -- Advance the index before we lose our reference point
            moveToNextChild

            liftEff $ void $
                removeChild c parent

            -- And recurse ... should investigate purescript-tailrec
            clearRest

        Nothing ->
            pure unit

