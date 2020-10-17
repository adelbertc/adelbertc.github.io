+++
title = "Reasoning with representable functors"
date = 2017-08-09
+++

A couple weeks ago I was working on a project using Conal Elliott's [uniform-pair][uniformPairHackage] library and
noticed it had a curious `Monad` instance, which I've reproduced below.

<!-- more -->

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
  = tabulate g              -- call the lambda 'g'
  = Pair (g False) (g True) -- Pair's tabulate = from
```

Now substituting `False` and `True` into the lambda:

```haskell
-- g False
  = index (f (index (Pair x y) False)) False
  = index (f x) False     -- Pair's index = to
  = first element of f x  -- Pair's index = to

-- g True
  = index (f (index (Pair x y) True)) True
  = index (f y) True      -- Pair's index = to
  = second element of f y -- Pair's index = to
```

Thus:

```haskell
bindRep (Pair x y) f
  = Pair a d -- where Pair (Pair a _) (Pair _ d)
--                          ^ f x      ^ f y
```

The same as `joinP` above.

This is awesome. By starting with the *meaning* of his data type, Conal discovered the only
natural type class instance consistent with the meaning. While in this case I started with the instance and worked
my way back, I believe the more useful and consistent approach is to think hard about your data type's
[denotation][denotationalDesign] and work your way forward.

[denotationalDesign]: http://conal.net/papers/type-class-morphisms/
[representableHackage]: https://hackage.haskell.org/package/representable-functors
[representableNLab]: https://ncatlab.org/nlab/show/representable+functor
[uniformPairHackage]: https://hackage.haskell.org/package/uniform-pair

[^1]: Specifically I mean the $Hask$ category with types as objects and functions as arrows.

[^2]: In general the type class law for `Representable` requires `index` and `tabulate` to be mutual inverses.
