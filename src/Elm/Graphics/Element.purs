
-- | Graphical elements that snap together to build complex widgets and layouts.
-- | Each Element is a rectangle with a known width and height, making them easy to
-- | combine and position.

module Elm.Graphics.Element
    ( Element
    , image, fittedImage, croppedImage, tiledImage
    , leftAligned, rightAligned, centered, justified, show
    , width, height, size, color, opacity, link, tag
    , widthOf, heightOf, sizeOf
    , flow, Direction, up, down, left, right, inward, outward
    , layers, above, below, beside
    , empty, spacer, container
    , middle, midTop, midBottom, midLeft, midRight, topLeft, topRight
    , bottomLeft, bottomRight
    , Pos, Position
    , absolute, relative, middleAt, midTopAt, midBottomAt, midLeftAt
    , midRightAt, topLeftAt, topRightAt, bottomLeftAt, bottomRightAt
    -- Not part of the Elm API ... used to create an Element from a Collage,
    -- or other renderabales.
    , fromRenderable
    ) where


import Control.Monad (when, unless)
import Control.Monad.Eff (Eff, forE, foreachE)
import Control.Monad.Eff.Unsafe (unsafePerformEff)
import DOM (DOM)
import DOM.Event.EventTarget (addEventListener, eventListener)
import DOM.HTML.Event.EventTypes (load)
import DOM.HTML.HTMLImageElement (create, naturalWidth, naturalHeight) as HTMLImageElement
import DOM.HTML.Types (HTMLDocument, htmlDocumentToDocument, htmlElementToElement, htmlImageElementToHTMLElement)
import DOM.Node.Document (createElement)
import DOM.Node.Element (setId, setAttribute, tagName, removeAttribute)
import DOM.Node.HTMLCollection (length, item) as HTMLCollection
import DOM.Node.Node (firstChild, appendChild, parentNode, parentElement, replaceChild)
import DOM.Node.ParentNode (firstElementChild, children) as ParentNode
import DOM.Node.Types (Document, Node, elementToNode, elementToParentNode, elementToEventTarget, ElementId(..))
import DOM.Node.Types (Element) as DOM
import DOM.Renderable (class Renderable, AnyRenderable, EffDOM, toAnyRenderable)
import DOM.Renderable (render, update) as Renderable
import Data.Array (catMaybes)
import Data.Foldable (maximum, sum, for_)
import Data.Int (ceil, toNumber)
import Data.List (List(..), null, (:), reverse, length, index)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Nullable (Nullable, toMaybe)
import Data.Ord (max)
import Data.String (joinWith)
import Data.Tuple (Tuple(..))
import Elm.Basics (Float, truncate)
import Elm.Color (Color, toCss)
import Elm.Graphics.Internal (createNode, setStyle, removeStyle, addTransform, removeTransform, measure, removePaddingAndMargin, nodeToElement)
import Elm.Text (Text, renderHtml)
import Elm.Text (fromString, monospace) as Text
import Prelude (class Show, class Eq, Unit, unit, flip, map, (<$>), (<#>), ($), (>>>), bind, discard, (>>=), pure, void, (+), (-), (/), (*), (<>), (==), (/=), (>), (||), (&&), negate)
import Prelude (show) as Prelude
import Text.Format (format, precision)


-- FOREIGN

-- Inner HTML
foreign import setInnerHtml :: ∀ e. String -> DOM.Element -> Eff (dom :: DOM | e) Unit

-- Unsafe document
foreign import nullableDocument :: ∀ e. Eff (dom :: DOM | e) (Nullable HTMLDocument)

-- Whether one thing is the same as another ... that is, the identical thing, not equality.
-- Note that we allow the types to differ, since the compiler might think of them as different
-- types for one reason or another.
foreign import same :: ∀ a b. a -> b -> Boolean


-- PRIMITIVES

-- | A graphical element that can be rendered on screen. Every element is a
-- | rectangle with a known width and height, so they can be composed and stacked
-- | easily.
newtype Element = Element
    { props :: Properties
    , element :: ElementPrim
    }

instance renderableElement :: Renderable Element where
    render document value = elementToNode <$> render document value
    update {result, value, document} = updateFromNode document result value


-- I've removed the `id :: Int` because it's essentially effectful to add an id.
-- It seems to be used (indirectly) to determine whether two ElementPrim's are
-- the same object. We'll use `same` for that instead.
type Properties =
    { width :: Int
    , height :: Int
    , opacity :: Float
    , color :: Maybe Color
    , href :: String
    , tag :: String
    -- TODO: Figure out hover / click logic.
    -- , hover :: Unit
    -- , click :: Unit
    }

eqProperties :: Properties -> Properties -> Boolean
eqProperties a b =
    a.width == b.width &&
    a.height == b.height &&
    a.opacity == b.opacity &&
    a.color == b.color &&
    a.href == b.href &&
    a.tag == b.tag


data ElementPrim
    = Image ImageStyle Int Int String
    | Container RawPosition Element
    | Flow Direction (List Element)
    | Spacer
    | RawHtml String String -- html align
    | Custom AnyRenderable


data ImageStyle
    = Plain
    | Fitted
    | Cropped {top :: Int, left :: Int}
    | Tiled

instance eqImageStyle :: Eq ImageStyle where
    eq Plain Plain = true
    eq Fitted Fitted = true
    eq (Cropped rec1) (Cropped rec2) = rec1.top == rec2.top && rec1.left == rec2.left
    eq Tiled Tiled = true
    eq _ _ = false


-- | Specifies a position for an element within a `container`, like “the top
-- | left corner”.
newtype Position = Position RawPosition

instance eqPosition :: Eq Position where
    eq (Position a) (Position b) = eqRawPosition a b


-- | Specifies a distance from a particular location within a `container`, like
-- | “20 pixels right and up from the center”. You can use `absolute` or `relative`
-- | to specify a `Pos` in pixels or as a percentage of the container.
data Pos
    = Absolute Int
    | Relative Float

instance eqPos :: Eq Pos where
    eq (Absolute a) (Absolute b) = a == b
    eq (Relative a) (Relative b) = a == b
    eq _ _ = false


data Three = P | Z | N

instance eqThree :: Eq Three where
    eq P P = true
    eq Z Z = true
    eq N N = true
    eq _ _ = false


type RawPosition =
    { horizontal :: Three
    , vertical :: Three
    , x :: Pos
    , y :: Pos
    }

eqRawPosition :: RawPosition -> RawPosition -> Boolean
eqRawPosition a b =
    a.horizontal == b.horizontal && a.vertical == b.vertical && a.x == b. x && a.y == b.y


-- | Represents a `flow` direction for a list of elements.
data Direction
    = DUp
    | DDown
    | DLeft
    | DRight
    | DIn
    | DOut

instance eqDirection :: Eq Direction where
    eq DUp DUp = true
    eq DDown DDown = true
    eq DLeft DLeft = true
    eq DRight DRight = true
    eq DIn DIn = true
    eq DOut DOut = true
    eq _ _ = false


-- | An Element that takes up no space. Good for things that appear conditionally:
-- |
-- |     flow down [ img1, if showMore then img2 else empty ]
empty :: Element
empty = spacer 0 0


-- | Get the width of an Element
widthOf :: Element -> Int
widthOf (Element {props}) = props.width


-- | Get the height of an Element
heightOf :: Element -> Int
heightOf (Element {props}) = props.height


-- | Get the width and height of an Element
sizeOf :: Element -> {width :: Int, height :: Int}
sizeOf (Element {props}) =
    { width: props.width
    , height: props.height
    }


-- | Create an `Element` with a given width.
width :: Int -> Element -> Element
width newWidth (Element {element, props}) =
    let
        newHeight =
            case element of
                Image _ w h _ ->
                    ceil (toNumber h / toNumber w * toNumber newWidth)

                RawHtml html _ ->
                    ceil $ _.height $ runHtmlHeight newWidth html

                _ ->
                    props.height

    in
        Element
            { element
            , props: props
                { width = newWidth
                , height = newHeight
                }
            }


-- | Create an `Element` with a given height.
height :: Int -> Element -> Element
height newHeight (Element {element, props}) =
    Element
        { element
        , props: props { height = newHeight }
        }


-- | Create an `Element` with a new width and height.
size :: Int -> Int -> Element -> Element
size w h e = do
    height h (width w e)


-- | Create an `Element` with a given opacity. Opacity is a number between 0 and 1
-- | where 0 means totally clear.
opacity :: Float -> Element -> Element
opacity givenOpacity (Element {element, props}) =
    Element
        { element
        , props: props { opacity = givenOpacity }
        }


-- | Create an `Element` with a given background color.
color :: Color -> Element -> Element
color clr (Element {element, props}) =
    Element
        { element
        , props: props { color = Just clr }
        }


-- | Create an `Element` with a tag. This lets you link directly to it.
-- | The element `(tag "all-about-badgers" thirdParagraph)` can be reached
-- | with a link like this: `/facts-about-animals.elm#all-about-badgers`
tag :: String -> Element -> Element
tag name (Element {element, props}) =
    Element
        { element
        , props: props { tag = name }
        }


-- | Create an `Element` that is a hyper-link.
link :: String -> Element -> Element
link href (Element {element, props}) =
    Element
        { element
        , props: props { href = href }
        }


-- IMAGES

-- | Create an image given a width, height, and image source.
image :: Int -> Int -> String -> Element
image w h src =
    newElement w h (Image Plain w h src)


-- | Create a fitted image given a width, height, and image source.
-- | This will crop the picture to best fill the given dimensions.
fittedImage :: Int -> Int -> String -> Element
fittedImage w h src =
    newElement w h (Image Fitted w h src)


-- | Create a cropped image. Take a rectangle out of the picture starting
-- | at the given top left coordinate. If you have a 140-by-140 image,
-- | the following will cut a 100-by-100 square out of the middle of it.
-- |
-- |     croppedImage (Tuple 20 20) 100 100 "yogi.jpg"
croppedImage :: Tuple Int Int -> Int -> Int -> String -> Element
croppedImage (Tuple t l) w h src =
    newElement w h (Image (Cropped {top: t, left: l}) w h src)


-- | Create a tiled image. Repeat the image to fill the given width and height.
-- |
-- |     tiledImage 100 100 "yogi.jpg"
tiledImage :: Int -> Int -> String -> Element
tiledImage w h src =
    newElement w h (Image Tiled w h src)


-- CUSTOM

-- | Create an `Element` from a custom type that is `Renderable`.
fromRenderable :: ∀ a. (Renderable a) => Int -> Int -> a -> Element
fromRenderable w h renderable =
    newElement w h (Custom (toAnyRenderable renderable))

-- Perhaps should have another variant that doesn't take a fixed width and height,
-- and instead measures it, anaologous to htmlHeight?


-- TEXT

-- | Align text along the left side of the text block. This is sometimes known as
-- | *ragged right*.
leftAligned :: Text -> Element
leftAligned = block "left"


-- | Align text along the right side of the text block. This is sometimes known
-- | as *ragged left*.
rightAligned :: Text -> Element
rightAligned = block "right"


-- | Center text in the text block. There is equal spacing on either side of a
-- | line of text.
centered :: Text -> Element
centered = block "center"


-- | Align text along the left and right sides of the text block. Word spacing is
-- | adjusted to make this possible.
justified :: Text -> Element
justified = block "justify"


-- | Convert anything to its textual representation and make it displayable in
-- | the browser. Excellent for debugging.
-- |
-- |     main :: Element
-- |     main =
-- |       show "Hello World!"
-- |
-- |     show value =
-- |         leftAligned (Text.monospace (Text.fromString (toString value)))
show :: ∀ a. (Show a) => a -> Element
show = Prelude.show >>> Text.fromString >>> Text.monospace >>> leftAligned


-- LAYOUT

-- | Put an element in a container. This lets you position the element really
-- | easily, and there are tons of ways to set the `Position`.
-- | To center `element` exactly in a 300-by-300 square you would say:
-- |
-- |     container 300 300 middle element
-- |
-- | By setting the color of the container, you can create borders.
container :: Int -> Int -> Position -> Element -> Element
container w h (Position rawPos) e =
    newElement w h (Container rawPos e)


-- | Create an empty box. This is useful for getting your spacing right and
-- | for making borders.
spacer :: Int -> Int -> Element
spacer w h =
    newElement w h Spacer


-- | Have a list of elements flow in a particular direction.
-- | The `Direction` starts from the first element in the list.
-- |
-- |     flow right [a,b,c]
-- |
-- |         +---+---+---+
-- |         | a | b | c |
-- |         +---+---+---+
flow :: Direction -> List Element -> Element
flow dir es =
    let
        ws = map widthOf es
        hs = map heightOf es
        maxOrZero list = fromMaybe 0 (maximum list)
        newFlow w h = newElement w h (Flow dir es)

    in
        if null es
            then empty
            else case dir of
                DUp    -> newFlow (maxOrZero ws) (sum hs)
                DDown  -> newFlow (maxOrZero ws) (sum hs)
                DLeft  -> newFlow (sum ws) (maxOrZero hs)
                DRight -> newFlow (sum ws) (maxOrZero hs)
                DIn    -> newFlow (maxOrZero ws) (maxOrZero hs)
                DOut   -> newFlow (maxOrZero ws) (maxOrZero hs)


-- | Stack elements vertically.
-- | To put `a` above `b` you would say: ``a `above` b``
above :: Element -> Element -> Element
above hi lo =
    newElement
        (max (widthOf hi) (widthOf lo))
        (heightOf hi + heightOf lo)
        (Flow DDown (hi : lo : Nil))


-- | Stack elements vertically.
-- | To put `a` below `b` you would say: ``a `below` b``
below :: Element -> Element -> Element
below = flip above


-- | Put elements beside each other horizontally.
-- | To put `a` beside `b` you would say: ``a `beside` b``
beside :: Element -> Element -> Element
beside lft rht =
    newElement
        (widthOf lft + widthOf rht)
        (max (heightOf lft) (heightOf rht))
        (Flow right (lft : rht : Nil))


-- | Layer elements on top of each other, starting from the bottom:
-- | `layers == flow outward`
layers :: List Element -> Element
layers es =
    let
        ws = map widthOf es
        hs = map heightOf es

    in
        newElement
            (fromMaybe 0 (maximum ws))
            (fromMaybe 0 (maximum hs))
            (Flow DOut es)


-- Repetitive things --

-- | A position specified in pixels. If you want something 10 pixels to the
-- | right of the middle of a container, you would write this:
-- |
-- |     middleAt (absolute 10) (absolute 0)
absolute :: Int -> Pos
absolute = Absolute


-- | A position specified as a percentage. If you want something 10% away from
-- | the top left corner, you would say:
-- |
-- }     topLeftAt (relative 0.1) (relative 0.1)
relative :: Float -> Pos
relative = Relative


middle :: Position
middle =
    Position
        { horizontal: Z
        , vertical: Z
        , x: Relative 0.5
        , y: Relative 0.5
        }


topLeft :: Position
topLeft =
    Position
        { horizontal: N
        , vertical: P
        , x: Absolute 0
        , y: Absolute 0
        }


topRight :: Position
topRight =
    Position
        { horizontal: P
        , vertical: P
        , x: Absolute 0
        , y: Absolute 0
        }


bottomLeft :: Position
bottomLeft =
    Position
        { horizontal: N
        , vertical: N
        , x: Absolute 0
        , y: Absolute 0
        }


bottomRight :: Position
bottomRight =
    Position
        { horizontal: P
        , vertical: N
        , x: Absolute 0
        , y: Absolute 0
        }


midLeft :: Position
midLeft =
    Position
        { horizontal: N
        , vertical: Z
        , x: Absolute 0
        , y: Relative 0.5
        }


midRight :: Position
midRight =
    Position
        { horizontal: P
        , vertical: Z
        , x: Absolute 0
        , y: Relative 0.5
        }


midTop :: Position
midTop =
    Position
        { horizontal: Z
        , vertical: P
        , x: Relative 0.5
        , y: Absolute 0
        }


midBottom :: Position
midBottom =
    Position
        { horizontal: Z
        , vertical: N
        , x: Relative 0.5
        , y: Absolute 0
        }


middleAt :: Pos -> Pos -> Position
middleAt x y =
    Position
        { horizontal: Z
        , vertical: Z
        , x
        , y
        }


topLeftAt :: Pos -> Pos -> Position
topLeftAt x y =
    Position
        { horizontal: N
        , vertical: P
        , x
        , y
        }


topRightAt :: Pos -> Pos -> Position
topRightAt x y =
    Position
        { horizontal: P
        , vertical: P
        , x
        , y
        }


bottomLeftAt :: Pos -> Pos -> Position
bottomLeftAt x y =
    Position
        { horizontal: N
        , vertical: N
        , x
        , y
        }


bottomRightAt :: Pos -> Pos -> Position
bottomRightAt x y =
    Position
        { horizontal: P
        , vertical: N
        , x
        , y
        }


midLeftAt :: Pos -> Pos -> Position
midLeftAt x y =
    Position
        { horizontal: N
        , vertical: Z
        , x
        , y
        }


midRightAt :: Pos -> Pos -> Position
midRightAt x y =
    Position
        { horizontal: P
        , vertical: Z
        , x
        , y
        }


midTopAt :: Pos -> Pos -> Position
midTopAt x y =
    Position
        { horizontal: Z
        , vertical: P
        , x
        , y
        }


midBottomAt :: Pos -> Pos -> Position
midBottomAt x y =
    Position
        { horizontal: Z
        , vertical: N
        , x
        , y
        }


up :: Direction
up = DUp


down :: Direction
down = DDown


left :: Direction
left = DLeft


right :: Direction
right = DRight


inward :: Direction
inward = DIn


outward :: Direction
outward = DOut


-- The remainder is a conversion of the Native JS code from Elm

-- CREATION

newElement :: Int -> Int -> ElementPrim -> Element
newElement w h prim =
    Element
        { element: prim
        , props:
            { width: w
            , height: h
            , opacity: 1.0
            , color: Nothing
            , href: ""
            , tag: ""
            }
        }


-- PROPERTIES

setProps :: ∀ e. Document -> Element -> DOM.Element -> Eff (dom :: DOM | e) DOM.Element
setProps document (Element {props, element}) node = do
    let
        w = props.width
        h = props.height

        -- TODO: These are concepts from Input.elm ... revisit when I do that.
        -- var width = props.width - (element.adjustWidth || 0);
        -- var height = props.height - (element.adjustHeight || 0);

    setStyle "width" (Prelude.show w <> "px") node
    setStyle "height" (Prelude.show h <> "px") node

    when (props.opacity /= 1.0) $
        setStyle "opacity" (Prelude.show props.opacity) node

    for_ props.color \c ->
        setStyle "backgroundColor" (toCss c) node

    when (props.tag /= "") $
        setId (ElementId props.tag) node

    -- TODO: Figure out hover and click
    {-
    if (props.hover.ctor !== '_Tuple0')
    {
        addHover(node, props.hover);
    }

    if (props.click.ctor !== '_Tuple0')
    {
        addClick(node, props.click);
    }
    -}

    if props.href == ""
        then pure node
        else do
            anchor <- createNode document "a"

            setStyle "display" "block" anchor
            setStyle "pointerEvents" "auto" anchor
            setAttribute "href" props.href anchor

            void $ appendChild (elementToNode node) (elementToNode anchor)
            pure anchor


{- TODO
    function addClick(e, handler)
    {
        e.style.pointerEvents = 'auto';
        e.elm_click_handler = handler;
        function trigger(ev)
        {
            e.elm_click_handler(Utils.Tuple0);
            ev.stopPropagation();
        }
        e.elm_click_trigger = trigger;
        e.addEventListener('click', trigger);
    }

    function removeClick(e, handler)
    {
        if (e.elm_click_trigger)
        {
            e.removeEventListener('click', e.elm_click_trigger);
            e.elm_click_trigger = null;
            e.elm_click_handler = null;
        }
    }

    function addHover(e, handler)
    {
        e.style.pointerEvents = 'auto';
        e.elm_hover_handler = handler;
        e.elm_hover_count = 0;

        function over(evt)
        {
            if (e.elm_hover_count++ > 0) return;
            e.elm_hover_handler(true);
            evt.stopPropagation();
        }
        function out(evt)
        {
            if (e.contains(evt.toElement || evt.relatedTarget)) return;
            e.elm_hover_count = 0;
            e.elm_hover_handler(false);
            evt.stopPropagation();
        }
        e.elm_hover_over = over;
        e.elm_hover_out = out;
        e.addEventListener('mouseover', over);
        e.addEventListener('mouseout', out);
    }

    function removeHover(e)
    {
        e.elm_hover_handler = null;
        if (e.elm_hover_over)
        {
            e.removeEventListener('mouseover', e.elm_hover_over);
            e.elm_hover_over = null;
        }
        if (e.elm_hover_out)
        {
            e.removeEventListener('mouseout', e.elm_hover_out);
            e.elm_hover_out = null;
        }
    }
-}


-- IMAGES

setBackgroundSize :: ∀ e. String -> DOM.Element -> Eff (dom :: DOM | e) Unit
setBackgroundSize backgroundSize elem = do
    foreachE backgroundSizeStyles \style ->
        setStyle style backgroundSize elem


backgroundSizeStyles :: Array String
backgroundSizeStyles =
    [ "webkitBackgroundSize"
    , "MozBackgroundSize"
    , "OBackgroundSize"
    , "backgroundSize"
    ]


makeImage :: ∀ e. Document -> Properties -> ImageStyle -> Int -> Int -> String -> Eff (dom :: DOM | e) DOM.Element
makeImage document props imageStyle imageWidth imageHeight src =
    case imageStyle of
        Plain -> do
            img <- createNode document "img"
            setAttribute "src" src img
            setAttribute "name" src img
            setStyle "display" "block" img
            pure img

        Fitted -> do
            div <- createNode document "div"
            setStyle "background" ("url('" <> src <> "') no-repeat center") div
            setBackgroundSize "cover" div
            pure div

        Cropped pos -> do
            e <- createNode document "div"

            setStyle "overflow" "hidden" e

            imgElement <-
                HTMLImageElement.create unit

            let
                img =
                    htmlElementToElement (htmlImageElementToHTMLElement imgElement)

            removePaddingAndMargin img

            let
                listener =
                    eventListener \event -> do
                        intrinsicWidth <-
                            toNumber <$>
                                HTMLImageElement.naturalWidth imgElement

                        intrinsicHeight <-
                            toNumber <$>
                                HTMLImageElement.naturalHeight imgElement

                        let
                            sw =
                                toNumber props.width / toNumber imageWidth

                            sh =
                                toNumber props.height / toNumber imageHeight

                            newWidth =
                                Prelude.show (truncate (intrinsicWidth * sw)) <> "px"

                            newHeight =
                                Prelude.show (truncate (intrinsicHeight * sh)) <> "px"

                            marginLeft =
                                Prelude.show (truncate (toNumber (-pos.left) * sw)) <> "px"

                            marginTop =
                                Prelude.show (truncate (toNumber (-pos.top) * sh)) <> "px"

                        setStyle "width" newWidth img
                        setStyle "height" newHeight img
                        setStyle "marginLeft" marginLeft img
                        setStyle "marginTop" marginTop img

                        pure unit

            addEventListener load listener false (elementToEventTarget img)
            setAttribute "src" src img
            setAttribute "name" src img
            void $ appendChild (elementToNode img) (elementToNode e)
            pure e

        Tiled -> do
            div <- createNode document "div"
            let s = "url(" <> src <> ")"
            setStyle "backgroundImage" s div
            pure div


-- FLOW

goOut :: ∀ e. DOM.Element -> Eff (dom :: DOM | e) Unit
goOut = setStyle "position" "absolute"


goDown :: ∀ e. DOM.Element -> Eff (dom :: DOM | e) Unit
goDown elem = pure unit


goRight :: ∀ e. DOM.Element -> Eff (dom :: DOM | e) Unit
goRight elem = do
    setStyle "styleFloat" "left" elem
    setStyle "cssFloat" "left" elem


directionTable :: Direction -> (∀ e. DOM.Element -> Eff (dom :: DOM | e) Unit)
directionTable dir =
    case dir of
        DUp -> goDown
        DDown -> goDown
        DLeft -> goRight
        DRight -> goRight
        DIn -> goOut
        DOut -> goOut


needsReversal :: Direction -> Boolean
needsReversal DUp = true
needsReversal DLeft = true
needsReversal DIn = true
needsReversal _ = false


makeFlow :: ∀ e. Document -> Direction -> List Element -> EffDOM e DOM.Element
makeFlow document dir elist = do
    parent <- createNode document "div"

    case dir of
        DIn -> setStyle "pointerEvents" "none" parent
        DOut -> setStyle "pointerEvents" "none" parent
        _ -> pure unit

    let
        possiblyReversed =
            if needsReversal dir
                then reverse elist
                else elist

        goDir =
            directionTable dir

    for_ possiblyReversed \elem -> do
        rendered <- render document elem
        goDir rendered
        appendChild (elementToNode rendered) (elementToNode parent)

    pure parent


-- CONTAINER

toPos :: Pos -> String
toPos (Absolute pos) = (Prelude.show pos) <> "px"
toPos (Relative pos) = format (precision 2) (pos * 100.0) <> "%"


setPos :: ∀ e. RawPosition -> Element -> DOM.Element -> Eff (dom :: DOM | e) Unit
setPos pos (Element {element, props}) elem =
    let
        w = props.width
        h = props.height

        -- TODO
        -- var w = props.width + (element.adjustWidth ? element.adjustWidth : 0);
        -- var h = props.height + (element.adjustHeight ? element.adjustHeight : 0);

        translateX =
            case pos.horizontal of
                Z -> Just $ "translateX(" <> Prelude.show ((-w) / 2) <> "px)"
                _ -> Nothing

        translateY =
            case pos.vertical of
                Z -> Just $ "translateY(" <> Prelude.show ((-h) / 2) <> "px)"
                _ -> Nothing

        transform =
            joinWith " " $ catMaybes [translateX, translateY]

        applyTransform =
            if transform == ""
                then removeTransform
                else addTransform transform

        horizontal = \e ->
            case pos.horizontal of
                P -> do
                    setStyle "right" (toPos pos.x) e
                    removeStyle "left" e

                _ -> do
                    setStyle "left" (toPos pos.x) e
                    removeStyle "right" e

        vertical = \e ->
            case pos.vertical of
                N -> do
                    setStyle "bottom" (toPos pos.y) e
                    removeStyle "top" e

                _ -> do
                    setStyle "top" (toPos pos.y) e
                    removeStyle "bottom" e

    in
        foreachE
            [ setStyle "position" "absolute"
            , setStyle "margin" "auto"
            , horizontal
            , vertical
            , applyTransform
            ] \op -> op elem


makeContainer :: ∀ e. Document -> RawPosition -> Element -> EffDOM e DOM.Element
makeContainer document pos elem = do
    e <- render document elem
    setPos pos elem e

    div <- createNode document "div"

    setStyle "position" "relative" div
    setStyle "overflow" "hidden" div

    void $ appendChild (elementToNode e) (elementToNode div)
    pure div


rawHtml :: ∀ e. Document -> String -> String -> Eff (dom :: DOM | e) DOM.Element
rawHtml document html align = do
    div <- createNode document "div"

    setInnerHtml html div
    setStyle "visibility" "hidden" div

    when (align /= "") $
        setStyle "textAlign" align div

    setStyle "visibility" "visible" div
    setStyle "pointerEvents" "auto" div

    pure div


-- RENDER

render :: ∀ e. Document -> Element -> EffDOM e DOM.Element
render document e =
    makeElement document e
    >>= setProps document e


makeElement :: ∀ e. Document -> Element -> EffDOM e DOM.Element
makeElement document (Element {element, props}) =
    case element of
        Image imageStyle imageWidth imageHeight src ->
            makeImage document props imageStyle imageWidth imageHeight src

        Flow direction children ->
            makeFlow document direction children

        Container position inner ->
            makeContainer document position inner

        Spacer ->
            createNode document "div"

        RawHtml html align ->
            rawHtml document html align

        Custom renderable -> do
            -- We don't insist on renderables creating elements, so we use a wrapper here.
            -- I suppose we could test what we get back from Renderable and only use a wrapper
            -- if it's not in fact an element.
            wrapper <- createNode document "div"
            child <- Renderable.render document renderable
            void $ appendChild child (elementToNode wrapper)
            pure wrapper


-- UPDATE

updateAndReplace :: ∀ e. Document -> DOM.Element -> Element -> Element -> EffDOM e DOM.Element
updateAndReplace document node curr next = do
    newNode <- update document node curr next

    unless (same newNode node) do
        nullableParent <- parentNode (elementToNode node)
        for_ nullableParent \parent ->
            replaceChild (elementToNode newNode) (elementToNode node) parent

    pure newNode


updateFromNode :: ∀ e. Document -> Node -> Element -> Element -> EffDOM e Node
updateFromNode document node curr next =
    case nodeToElement node of
        Just element ->
            elementToNode <$> update document element curr next

        Nothing ->
            -- We would have produced an element, so something's wrong ... fall
            -- back to `render`
            elementToNode <$> render document next


update :: ∀ e. Document -> DOM.Element -> Element -> Element -> EffDOM e DOM.Element
update document outerNode (Element curr) (Element next) = do
    innerNode <-
        if tagName outerNode == "A"
            then do
                nullableChild <- ParentNode.firstElementChild (elementToParentNode outerNode)
                case nullableChild of
                     Just child -> pure child
                     Nothing -> pure outerNode

            else pure outerNode

    let
        nextE = next.element
        currE = curr.element

    if same currE nextE
        then do
            -- If the ElementPrim is the same, then just update the  props
            updateProps document innerNode (Element curr) (Element next)
            pure outerNode

        else
            -- Otherwise, it depends on what the old and new element are
            case { nextE, currE } of

                -- Both spacers
                { nextE: Spacer
                , currE: Spacer
                } -> do
                    updateProps document innerNode (Element curr) (Element next)
                    pure outerNode

                -- Both RawHtml
                { nextE: RawHtml html _
                , currE: RawHtml oldHtml _
                } -> do
                    when (html /= oldHtml) $
                        setInnerHtml html innerNode

                    updateProps document innerNode (Element curr) (Element next)
                    pure outerNode

                -- Both Images
                { nextE: Image imageStyle imageWidth imageHeight src
                , currE: Image oldImageStyle oldImageWidth oldImageHeight oldSrc
                } ->
                    case { imageStyle, oldImageStyle } of
                        -- If we're transitioning from plain to plain, then we just
                        -- have to update the src if necessary, and the props. At
                        -- least, that's how Elm does it.
                        { imageStyle: Plain
                        , oldImageStyle: Plain
                        } -> do
                            when (oldSrc /= src) $
                                setAttribute "src" src innerNode

                            updateProps document innerNode (Element curr) (Element next)
                            pure outerNode

                        _ ->
                            -- Width and height changes appear to need a re-render ...
                            -- Normally just an update props would be required.
                            if next.props.width /= curr.props.width ||
                               next.props.height /= curr.props.height ||
                               imageStyle /= oldImageStyle ||
                               imageWidth /= oldImageWidth ||
                               imageHeight /= oldImageHeight ||
                               src /= oldSrc
                                    then render document (Element next)
                                    else do
                                        updateProps document innerNode (Element curr) (Element next)
                                        pure outerNode

                -- Both flows
                { nextE: Flow dir list
                , currE: Flow oldDir oldList
                } -> do
                    if dir /= oldDir
                        then render document (Element next)
                        else do
                            kids <- ParentNode.children (elementToParentNode innerNode)
                            len <- HTMLCollection.length kids

                            if len /= length list || len /= length oldList
                                then render document (Element next)
                                else do
                                    let
                                        reversal = needsReversal dir
                                        goDir = directionTable dir

                                    -- Why doesn't forE take an Int?
                                    forE 0 len \i -> do
                                        let
                                            kidIndex =
                                                if reversal
                                                    then len - (i + 1)
                                                    else i

                                        kid <- HTMLCollection.item kidIndex kids
                                        innerOld <- pure $ index oldList i
                                        innerNext <- pure $ index list i

                                        for_ kid \k ->
                                            for_ innerOld \old ->
                                                for_ innerNext \iNext ->
                                                    updateAndReplace document k old iNext >>= goDir

                                    updateProps document innerNode (Element curr) (Element next)
                                    pure outerNode

                -- Both containers
                { nextE: Container rawPos elem
                , currE: Container oldRawPos oldElem
                } -> do
                    nullableSubnode <- ParentNode.firstElementChild (elementToParentNode innerNode)
                    for_ nullableSubnode \subnode -> do
                        newSubNode <- updateAndReplace document subnode oldElem elem
                        setPos rawPos elem newSubNode

                    updateProps document innerNode (Element curr) (Element next)
                    pure outerNode

                -- Both custom
                { nextE: Custom oldRenderable
                , currE: Custom newRenderable
                } -> do
                    -- Because we wrap custom stuff in a div, we need to actually dive down one level
                    nullableWrapped <- firstChild (elementToNode innerNode)

                    case nullableWrapped of
                        Just oldResult -> do
                            updatedNode <-
                                Renderable.update
                                    { value: oldRenderable
                                    , result: oldResult
                                    , document
                                    }
                                    newRenderable

                            -- If it updated in place, then we should update the props.
                            -- Otherwise, we should set the props as if fresh.
                            if same updatedNode oldResult
                                then do
                                    updateProps document innerNode (Element curr) (Element next)
                                    pure outerNode

                                else
                                    setProps document (Element next) innerNode

                        Nothing ->
                            -- If there was no wrapper, then we should bail and just render
                            render document (Element next)

                -- Different element constructors
                _ ->
                    render document (Element next)


updateProps :: ∀ e. Document -> DOM.Element -> Element -> Element -> Eff (dom :: DOM | e) Unit
updateProps document node (Element curr) (Element next) = do
    let
        nextProps = next.props
        currProps = curr.props

        element = next.element

        w = nextProps.width
        h = nextProps.height

        -- TODO
        -- var width = nextProps.width - (element.adjustWidth || 0);
        -- var height = nextProps.height - (element.adjustHeight || 0);

    when (w /= currProps.width) $
        setStyle "width" ((Prelude.show w) <> "px") node

    when (h /= currProps.height) $
        setStyle "height" ((Prelude.show h) <> "px") node

    when (nextProps.opacity /= currProps.opacity) $
        setStyle "opacity" (Prelude.show nextProps.opacity) node

    when (nextProps.color /= currProps.color) $
        case nextProps.color of
            Just c -> setStyle "backgroundColor" (toCss c) node
            Nothing -> removeStyle "backgroundColor" node

    when (nextProps.tag /= currProps.tag) $
        if nextProps.tag == ""
            then removeAttribute "id" node
            else setId (ElementId nextProps.tag) node

    when (nextProps.href /= currProps.href) $
        if currProps.href == ""
            then do
                anchor <- createNode document "a"

                setStyle "display" "block" anchor
                setStyle "pointerEvents" "auto" anchor
                setAttribute "href" nextProps.href anchor

                nullableParent <- parentNode (elementToNode node)
                for_ nullableParent \parent -> do
                    void $ replaceChild (elementToNode anchor) (elementToNode node) parent
                    void $ appendChild (elementToNode node) (elementToNode anchor)

            else do
                nullableAnchor <- parentElement (elementToNode node)
                for_ nullableAnchor \anchor ->
                    if nextProps.href == ""
                        then do
                            nullableParent <- parentNode (elementToNode anchor)
                            for_ nullableParent \parent ->
                                void $ replaceChild (elementToNode node) (elementToNode anchor) parent

                        else
                            setAttribute "href" nextProps.href anchor

        -- TODO
        {-
        -- update click and hover handlers
        var removed = false;

        // update hover handlers
        if (currProps.hover.ctor === '_Tuple0')
        {
            if (nextProps.hover.ctor !== '_Tuple0')
            {
                addHover(node, nextProps.hover);
            }
        }
        else
        {
            if (nextProps.hover.ctor === '_Tuple0')
            {
                removed = true;
                removeHover(node);
            }
            else
            {
                node.elm_hover_handler = nextProps.hover;
            }
        }

        // update click handlers
        if (currProps.click.ctor === '_Tuple0')
        {
            if (nextProps.click.ctor !== '_Tuple0')
            {
                addClick(node, nextProps.click);
            }
        }
        else
        {
            if (nextProps.click.ctor === '_Tuple0')
            {
                removed = true;
                removeClick(node);
            }
            else
            {
                node.elm_click_handler = nextProps.click;
            }
        }

        // stop capturing clicks if
        if (removed
            && nextProps.hover.ctor === '_Tuple0'
            && nextProps.click.ctor === '_Tuple0')
        {
            node.style.pointerEvents = 'none';
        }
        -}


-- TEXT

block :: String -> Text -> Element
block align text =
    let
        html = renderHtml text
        pos = runHtmlHeight 0 html

    in
        newElement (ceil pos.width) (ceil pos.height) $
            RawHtml html align


markdown :: String -> Element
markdown text =
    let
        pos = runHtmlHeight 0 text

    in
        newElement (ceil pos.width) (ceil pos.height) $
            RawHtml text ""


-- Calculate htmlHeight without the effect. The theory is that because htmlHeight
-- puts the div in the DOM but then immediately takes it out again, it's reasonable
-- to run this "unsafely" -- the effect is undone. And, of course, it makes the
-- API work as Elm expects it to.
runHtmlHeight :: Int -> String -> {width :: Number, height :: Number}
runHtmlHeight w html =
    unsafePerformEff $ htmlHeight w html


htmlHeight :: ∀ e. Int -> String -> Eff (dom :: DOM | e) {width :: Number, height :: Number}
htmlHeight w html = do
    -- Because of runHtmlHeight, we double-check whether we really have a document or not.
    -- In principle, we should take the document as a parameter. However, that would complicate
    -- the original Elm API in ways that might not be desirable ... I can reconsider that
    -- at some point.
    nullableDocument
    <#> toMaybe
    >>= maybe
        ( pure
            { width: 0.0
            , height: 0.0
            }
        )
        \doc -> do
            temp <- createElement "div" (htmlDocumentToDocument doc)

            setInnerHtml html temp

            when (w > 0) $
                setStyle "width" ((Prelude.show w) <> "px") temp

            measure (elementToNode temp)
