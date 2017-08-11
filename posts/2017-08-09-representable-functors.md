---
title: Reasoning with representable functors
---

A couple weeks ago I was working on a project using Conal Elliott's [uniform-pair][uniformPairHackage] library and
noticed it had a curious `Monad` instance, which I've reproduced below.

```haskell
data Pair a = Pair a a

instance Monad Pair where
  return a = Pair a a

  m >>= f = joinP (f <$> m)

joinP :: Pair (Pair a) -> Pair a
joinP (Pair (Pair a _) (Pair _ d)) = Pair a d
```

I was especially curious about why `joinP` chose the first element of the first pair and the second element of
the second pair. My initial guess was that it was determined by the `Functor` instance which would've looked something
like..

```haskell
fmapP :: (a -> b) -> Pair a -> Pair b
fmapP f (Pair x y) = Pair (f x) (f y)
```

For `Monad` to be consistent with `Functor` the follow equation should hold..

```haskell
fmapP f p = p >>= (return . f)
```

..but this didn't really help.

```haskell
(Pair x y) >>= (return . f)
  = joinP ((return . f) <$> Pair x y)
  = joinP (Pair (Pair (f x) (f y)) (Pair (f x) (f y)))
```

Taking either element of the outer pair would've been consistent with the `Functor` instance, as would taking the first
element of the first pair and the second element of the second pair.

A couple days later I was talking with Conal about it and he hinted at using the fact that uniform pairs are
[representable functors][representableNLab]. For a functor to be representable in Haskell[^1] means it is isomorphic to
the set of functions from `X`, for some fixed `X` (this "set of functions from X" is also known as the reader monad).
For uniform pairs, `X = Bool`. Indeed, the following functions are mutual inverses.

```haskell
to :: Pair a -> Bool -> a
to (Pair x _) False = x
to (Pair _ y) True  = y

from :: (Bool -> a) -> Pair a
from f = Pair (f False) (f True)
```

To prove that a functor `f` is representable in Haskell is to implement the `Representable` type class. The
following is reproduced from the [representable-functors][representableHackage] package.

```haskell
class Representable f where
  index :: f a -> Key f -> a

  tabulate :: (Key f -> a) -> f a
```

The `Key f` refers to the fixed `X` mentioned above, so `Key Pair = Bool`. Substituing `Bool` for `Key f` reveals
signatures matching the `to` (`index`) and `from` (`tabulate`) functions[^2].

As it turns out every `Representable` has a canonical monadic return and bind, defined as:

```haskell
returnRep :: Representable f => a -> f a
returnRep = tabulate . const

bindRep :: Representable f => f a -> (a -> f b) -> f b
bindRep m f = tabulate (\a -> index (f (index m a)) a)
```

Let's see what this looks like for `Pair`. First let's do some substitution on `returnRep`:

```haskell
returnRep :: a -> Pair a
returnRep a
  = (tabulate . const) a
  = tabulate (const a)
  = Pair (const a False) (const a True) -- Pair's tabulate = from
  = Pair a a
```

That matches our `return` definition above. Now let's do the same for `bindRep`:

```haskell
bindRep :: Pair a -> (a -> Pair b) -> Pair b
bindRep (Pair x y) f
  = tabulate (\a -> index (f (index (Pair x y) a)) a)
```

Here we can do a sort of case splitting since we know `a = Bool` and therefore
the argument must either be `False` or `True`.

```haskell
-- a = False
  = ... index (f (index (Pair x y) False)) False
  = ... index (f x) False -- definition of Pair's index = to
  = first element of f x  -- definition of Pair's index = to

-- a = True
  = ... index (f (index (Pair x y) True)) True
  = ... index (f y) True  -- definition of Pair's index = to
  = second element of f y -- definition of Pair's index = to
```

This tells us passing `False` to the function gives the first element of `f x`, and passing
`True` to the function gives the second element of `f y`. Thus:

```haskell
joinP :: Pair (Pair a) -> Pair a
joinP (Pair (Pair a _) (Pair _ d)) = Pair a d
--           ^ f x      ^ f y
```

That's awesome.

Now while I started with a `Monad` instance and worked my way back, the more useful pattern is to think about
the [denotation][denotationalDesign] of your data type and work your way forward. In the case of `Pair`, Conal
identified it as an instance of a representable functor and from there a `Monad` instance was revealed.

[denotationalDesign]: http://conal.net/papers/type-class-morphisms/
[representableHackage]: https://hackage.haskell.org/package/representable-functors
[representableNLab]: https://ncatlab.org/nlab/show/representable+functor
[uniformPairHackage]: https://hackage.haskell.org/package/uniform-pair

[^1]: Specifically I mean the $Hask$ category with types as objects and functions as arrows.

[^2]: In general the type class law for `Representable` requires `index` and `tabulate` to be mutual inverses.
