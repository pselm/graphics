## Module Elm.Graphics.Element

Graphical elements that snap together to build complex widgets and layouts.
Each Element is a rectangle with a known width and height, making them easy to
combine and position.

#### `Element`

``` purescript
newtype Element
```

A graphical element that can be rendered on screen. Every element is a
rectangle with a known width and height, so they can be composed and stacked
easily.

##### Instances
``` purescript
Renderable Element
```

#### `image`

``` purescript
image :: Int -> Int -> String -> Element
```

Create an image given a width, height, and image source.

#### `fittedImage`

``` purescript
fittedImage :: Int -> Int -> String -> Element
```

Create a fitted image given a width, height, and image source.
This will crop the picture to best fill the given dimensions.

#### `croppedImage`

``` purescript
croppedImage :: Tuple Int Int -> Int -> Int -> String -> Element
```

Create a cropped image. Take a rectangle out of the picture starting
at the given top left coordinate. If you have a 140-by-140 image,
the following will cut a 100-by-100 square out of the middle of it.

    croppedImage (Tuple 20 20) 100 100 "yogi.jpg"

#### `tiledImage`

``` purescript
tiledImage :: Int -> Int -> String -> Element
```

Create a tiled image. Repeat the image to fill the given width and height.

    tiledImage 100 100 "yogi.jpg"

#### `leftAligned`

``` purescript
leftAligned :: Text -> Element
```

Align text along the left side of the text block. This is sometimes known as
*ragged right*.

#### `rightAligned`

``` purescript
rightAligned :: Text -> Element
```

Align text along the right side of the text block. This is sometimes known
as *ragged left*.

#### `centered`

``` purescript
centered :: Text -> Element
```

Center text in the text block. There is equal spacing on either side of a
line of text.

#### `justified`

``` purescript
justified :: Text -> Element
```

Align text along the left and right sides of the text block. Word spacing is
adjusted to make this possible.

#### `show`

``` purescript
show :: forall a. Show a => a -> Element
```

Convert anything to its textual representation and make it displayable in
the browser. Excellent for debugging.

    main :: Element
    main =
      show "Hello World!"

    show value =
        leftAligned (Text.monospace (Text.fromString (toString value)))

#### `width`

``` purescript
width :: Int -> Element -> Element
```

Create an `Element` with a given width.

#### `height`

``` purescript
height :: Int -> Element -> Element
```

Create an `Element` with a given height.

#### `size`

``` purescript
size :: Int -> Int -> Element -> Element
```

Create an `Element` with a new width and height.

#### `color`

``` purescript
color :: Color -> Element -> Element
```

Create an `Element` with a given background color.

#### `opacity`

``` purescript
opacity :: Float -> Element -> Element
```

Create an `Element` with a given opacity. Opacity is a number between 0 and 1
where 0 means totally clear.

#### `link`

``` purescript
link :: String -> Element -> Element
```

Create an `Element` that is a hyper-link.

#### `tag`

``` purescript
tag :: String -> Element -> Element
```

Create an `Element` with a tag. This lets you link directly to it.
The element `(tag "all-about-badgers" thirdParagraph)` can be reached
with a link like this: `/facts-about-animals.elm#all-about-badgers`

#### `widthOf`

``` purescript
widthOf :: Element -> Int
```

Get the width of an Element

#### `heightOf`

``` purescript
heightOf :: Element -> Int
```

Get the height of an Element

#### `sizeOf`

``` purescript
sizeOf :: Element -> { width :: Int, height :: Int }
```

Get the width and height of an Element

#### `flow`

``` purescript
flow :: Direction -> List Element -> Element
```

Have a list of elements flow in a particular direction.
The `Direction` starts from the first element in the list.

    flow right [a,b,c]

        +---+---+---+
        | a | b | c |
        +---+---+---+

#### `Direction`

``` purescript
data Direction
```

Represents a `flow` direction for a list of elements.

##### Instances
``` purescript
Eq Direction
```

#### `up`

``` purescript
up :: Direction
```

#### `down`

``` purescript
down :: Direction
```

#### `left`

``` purescript
left :: Direction
```

#### `right`

``` purescript
right :: Direction
```

#### `inward`

``` purescript
inward :: Direction
```

#### `outward`

``` purescript
outward :: Direction
```

#### `layers`

``` purescript
layers :: List Element -> Element
```

Layer elements on top of each other, starting from the bottom:
`layers == flow outward`

#### `above`

``` purescript
above :: Element -> Element -> Element
```

Stack elements vertically.
To put `a` above `b` you would say: ``a `above` b``

#### `below`

``` purescript
below :: Element -> Element -> Element
```

Stack elements vertically.
To put `a` below `b` you would say: ``a `below` b``

#### `beside`

``` purescript
beside :: Element -> Element -> Element
```

Put elements beside each other horizontally.
To put `a` beside `b` you would say: ``a `beside` b``

#### `empty`

``` purescript
empty :: Element
```

An Element that takes up no space. Good for things that appear conditionally:

    flow down [ img1, if showMore then img2 else empty ]

#### `spacer`

``` purescript
spacer :: Int -> Int -> Element
```

Create an empty box. This is useful for getting your spacing right and
for making borders.

#### `container`

``` purescript
container :: Int -> Int -> Position -> Element -> Element
```

Put an element in a container. This lets you position the element really
easily, and there are tons of ways to set the `Position`.
To center `element` exactly in a 300-by-300 square you would say:

    container 300 300 middle element

By setting the color of the container, you can create borders.

#### `middle`

``` purescript
middle :: Position
```

#### `midTop`

``` purescript
midTop :: Position
```

#### `midBottom`

``` purescript
midBottom :: Position
```

#### `midLeft`

``` purescript
midLeft :: Position
```

#### `midRight`

``` purescript
midRight :: Position
```

#### `topLeft`

``` purescript
topLeft :: Position
```

#### `topRight`

``` purescript
topRight :: Position
```

#### `bottomLeft`

``` purescript
bottomLeft :: Position
```

#### `bottomRight`

``` purescript
bottomRight :: Position
```

#### `Pos`

``` purescript
data Pos
```

Specifies a distance from a particular location within a `container`, like
“20 pixels right and up from the center”. You can use `absolute` or `relative`
to specify a `Pos` in pixels or as a percentage of the container.

##### Instances
``` purescript
Eq Pos
```

#### `Position`

``` purescript
newtype Position
```

Specifies a position for an element within a `container`, like “the top
left corner”.

##### Instances
``` purescript
Eq Position
```

#### `absolute`

``` purescript
absolute :: Int -> Pos
```

A position specified in pixels. If you want something 10 pixels to the
right of the middle of a container, you would write this:

    middleAt (absolute 10) (absolute 0)

#### `relative`

``` purescript
relative :: Float -> Pos
```

A position specified as a percentage. If you want something 10% away from
the top left corner, you would say:


#### `middleAt`

``` purescript
middleAt :: Pos -> Pos -> Position
```

#### `midTopAt`

``` purescript
midTopAt :: Pos -> Pos -> Position
```

#### `midBottomAt`

``` purescript
midBottomAt :: Pos -> Pos -> Position
```

#### `midLeftAt`

``` purescript
midLeftAt :: Pos -> Pos -> Position
```

#### `midRightAt`

``` purescript
midRightAt :: Pos -> Pos -> Position
```

#### `topLeftAt`

``` purescript
topLeftAt :: Pos -> Pos -> Position
```

#### `topRightAt`

``` purescript
topRightAt :: Pos -> Pos -> Position
```

#### `bottomLeftAt`

``` purescript
bottomLeftAt :: Pos -> Pos -> Position
```

#### `bottomRightAt`

``` purescript
bottomRightAt :: Pos -> Pos -> Position
```

#### `fromRenderable`

``` purescript
fromRenderable :: forall a. Renderable a => Int -> Int -> a -> Element
```

Create an `Element` from a custom type that is `Renderable`.


