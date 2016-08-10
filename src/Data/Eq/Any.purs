
-- | Ordinarily, you can only check two values for equality if the type-checker
-- | knows that they are the same type.
-- |
-- | This module provides an `anyEq` function which loosens that restriction. It
-- | works with any two values, no matter their type, so long as each has an `Eq`
-- | instance. To do so, it checks whether the two `Eq` instances are implemented
-- | with the same function. If so, clearly that function can take both values,
-- | and can be called to determine equality. If not, clearly the values are unequal.
-- |
-- | But why would the type-checker not know that the two values are of the same
-- | type? On occasion, it is convenient to "forget" the type of a value, and only
-- | remember some fact about the type -- say, that it has an `Eq` instance.
-- | This is a little like what `Data.Exists` does, except that `Data.Exists`
-- | doesn't remember anything at all about the original type.
-- |
-- | So, this module provides an `anyEq` function, which turns any value with an
-- | `Eq` instance into an `AnyEq`. All you can do with an `AnyEq` is compare it
-- | for equality with another `AnyEq`. The nice thing is that the two `AnyEq`
-- | values may originally have been different types.

module Data.Eq.Any
    ( AnyEq, anyEq, eqAny
    ) where


import Unsafe.Coerce (unsafeCoerce)
import Data.Eq (class Eq, eq)


-- | A type for values that have forgotten everything but how to determine whether
-- | they are equal to another value.
-- |
-- | You can produce an `AnyEq` via the `anyEq` function. Once you have an `AnyEq`,
-- | the only thing you can do with it is check it for equality with another `AnyEq`.
-- |
-- |     anyEq 5 == anyEq 5
-- |     anyEq 5 /= anyEq 6
-- |     anyEq 5 /= anyEq "five"
-- |     anyEq "five" == anyEq "five"
-- |     anyEq "five" /= anyEq "six"
newtype AnyEq = AnyEq (∀ b. (∀ a. (Eq a) => a -> b) -> b)


-- | Given a value with an `Eq` instance, forget everything except how to determine
-- | whether you are equal to another `AnyEq`.
anyEq :: ∀ a. (Eq a) => a -> AnyEq
anyEq a = AnyEq \c -> c a


instance eqAnyEq :: Eq AnyEq where
    eq (AnyEq func1) (AnyEq func2) =
        func1 (func2 eqAny)


-- | Check two values for equality, even if all you know is that they both have an
-- | `Eq` instance. Of course, normally you'll know that the values have the same
-- | type, so you'd prefer to just use `(==)` directly.
-- |
-- |     5 `eqAny` 5 == true
-- |     5 `eqAny` 7 == false
-- |     5 `eqAny` "five" == false
-- |     "five" `eqAny` "five" == true
-- |     "five" `eqAny` "six" == false
eqAny :: ∀ a b. (Eq a, Eq b) => a -> b -> Boolean
eqAny a b =
    let
        -- We capture the functions which implement the `Eq` instances.
        eqA = eq :: a -> a -> Boolean
        eqB = eq :: b -> b -> Boolean

    in
        if refEq eqA eqB
            -- If the two `eq` functions are the same, then clearly the function
            -- can accept both a and b. So, we can safely use unsafeCoerce.
            -- Note that we don't necessarily care whether a and b are literally
            -- the same type, so long as they have identical `eq` functions.
            then eqA a (unsafeCoerce b)

            -- If the two `eq` functions are not the same, then clearly the
            -- two values are not equal.
            else false


-- Reference equality, i.e. `a === b` in Javascript.
foreign import refEq :: ∀ a b. a -> b -> Boolean