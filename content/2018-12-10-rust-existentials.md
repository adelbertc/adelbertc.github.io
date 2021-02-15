+++
title = "Existential types in Rust"
date = 2018-12-10
[taxonomies]
tags=["code", "programming-languages"]
+++

For the past couple of weeks I have been using [Rust][rust] for a project at
work and enjoying it a lot. The emphasis on systems programming
aligns well with my interest in systems, the unique type system keeps
the programming languages enthusiast in me interested, and the use of
expressive types, as always, keeps me in check and makes me confident in my
code.

<!-- more -->

However, it wasn't long before I hit a bit of an obstacle.
The Rust project I am working on is a caching layer, currently backed by
[Redis][redis], and it came to a point where I needed to leverage
[pipelining][redisPipeline].
On its own, pipelining is straightforward as the [redis][redisCrate]
crate implements it already. However all notions of a cache in our code are
abstracted out behind a trait so we can have alternative implementations,
such as an in-memory `HashMap`-backed implementation.

The problem arises with representing the pipeline in code. The redis crate
encodes the pipeline with the `redis::Pipeline` struct:

```rust
// Taken from https://docs.rs/redis/0.9.1/redis/struct.Pipeline.html

let ((k1, k2),) : ((i32, i32),) = redis::pipe()
    .cmd("SET").arg("key_1").arg(42).ignore()
    .cmd("SET").arg("key_2").arg(43).ignore()
    .cmd("MGET").arg(&["key_1", "key_2"]).query(&con)
```

I could augment our trait to use this `Pipeline` struct..

```rust
trait Cache {
  fn pipe() -> redis::Pipeline;
}
```

..but that would force any implementation of our cache to Redis's notion of
a pipeline. Not only would this make it difficult to introspect during testing,
but it would also be nonsensical for our `HashMap`-backed cache. What I needed
was a way to return an abstract type that could change from implementation to
implementation, yet still allow a set of operations on it so clients would be
able to work with the abstract type despite not knowing what it was concretely.

My usual answer to this in languages that support higher-kinded types is to use
[tagless-final][taglessFinal] algebras, but Rust's type system
[currently doesn't support higher-kinded types][rustHkt][^1]. Fortunately,
there is a pretty good alternative that Rust does support: existential types.

### An overview of existential types

Many languages support *universally* quantified types, more commonly known as
generics or parameterized types. Significantly fewer support
*existentially* quantified types - the more mainstream languages that do
support it consist of Scala, Haskell, OCaml, and as we will see in this
post, Rust.

A universally quantified type communicates the idea of "for all types," hence
the use of the phrase "universal." In code this translates to the *caller*
being able to pick the instantiated type.

```rust
fn take<A>(vec: Vec<A>, n: usize) -> Vec<A> {
  ...
}

take::<i32>(vec![1, 2, 3], 3);
take::<&str>(vec!["hello", " ", "world"], 1);
```

The above snippet defines a function `take` with universally quantified
type `A`. The callers below then pick whatever instantiation of `A` they want,
in this case `i32` and `&str`.

In contrast, existentially quantified types communicates "there exists a type."
In code this translates to the *callee*, or function, picking the instantiated
type.

One way Rust encodes this is through the `impl Trait` feature introduced in
Rust 1.26 (or similarly with `Box<Trait>`). The idea is functions can specify
just the trait a return type implements instead of a concrete type - this
constrains the caller to only be able to use methods available on that trait
and liberates the callee to be able to swap the internals without the
caller being the wiser[^2].

```rust
pub trait Token {
  fn render(&self) -> String
}

impl Token for String {
  fn render(&self) -> String {
    self.clone()
  }
}

fn get_token() -> impl Token {
  "this is not a token".to_string()
}

let token = get_token();
```

Here we define a function `get_token` whose static type states it returns some
type (*there exists* some type..) that implements the `Token` trait. Even
though the function *interally* is using `String`, that information is
hidden/lost with the `impl Token` return type. All we can do with `token` is
call the `render` method on it and nothing else, not even methods on `String`.
If at a later point the implementation of `get_token` changes to some other
type that implements `Token`, that can happen transparently to all existing
call-sites.

### Sharing is caring

One downside of the `impl Trait` approach is there is no way to have a group
of functions share the same view of an existential type. For example if we
wanted to write a `renew_token` function that took the same token type as
`get_token`
and returned a new token, there is no way for us to communicate to Rust that
the `impl Token` returned by `get_token` should be the same `impl Token`
consumed and produced by `renew_token`. Indeed, Rust rejects the following
addition..

```rust
// ...

fn get_token() -> impl Token {
  ...
}

// ...

fn renew_token(token: impl Token) -> impl Token {
  unimplemented!()
}

let mut expired_token = get_token();
expired_token = renew_token(expired_token);
```

..with error "expected anonymized type, found a different anonymized type."
This is because given the types in their current form, there is no guarantee
the two `impl Token`s are the same - `get_token` could return a `String`
and `renew_token` could return a JSON Web Token and so the type checker must
pessimistically reject the re-assignment.

Thankfully Rust provides another approach to existential types through its
associated types feature. Instead of hiding the concrete type behind
`impl Trait`, we can use associated types and parameterize functions with
type parameters that implement the corresponding trait. For example:

```rust
pub trait Token {
  type Token;

  fn get_token() -> Self::Token;
  fn renew_token(t: Self::Token) -> Self::Token;
}

fn get_and_renew<T: Token>() -> T::Token {
  let token = T::get_token();
  renew_token(token)
}
```

This time we define a trait `Token` with an abstract associated type and
define methods that point to that associated type. Because now we have
a single type definition to point to, we can tell the compiler that for
a given implementation of `Token`, `get_token` and `renew_token` must
refer to the same `Token` type.

```rust
impl Token for String {
  type Token = String;

  fn get_token() -> String {
    "this is not a token".to_string()
  }

  fn renew_token(t: String) -> String {
    "this is not a renewed token".to_string()
  }
}
```

We then define a function `get_and_renew` that is parameterized by (or if
you'd like, universally quantified over) a type `T` that implements `Token`.
However, since inside the definition of `get_and_renew` we do not know what
`T` will be, the associated type `T::Token` is abstract to us and thus
existentially quantified. We only know that calling `T::get_token` will give
us some type `T::Token` (the existential type), but now we also know we can
pass that `T::Token` to `T::renew_token` and get back a token of the same type!

This approach mimics the "[ML-style modules][mlModules]" technique that is
the primary organization and abstraction mechanism in the ML-family of
languages (e.g. [Standard ML][sml] and [OCaml][ocaml]). Indeed, just like
the ML-family of languages, we can organize entire Rust programs like this
and at the top-level seamlessly swap out different implementations of different
components by instantiating different types (e.g. `String` or JWT in the above
example).

### An end-to-end example: caching with Redis and a hash table

Going back to the initial motivation for this adventure, we can now see how we
can abstract over a caching layer with existential types.

First we define the operations we want our cache to have in a trait - for
simplicity we assume a cache with string keys and integer values:

```rust
pub trait Cache {
  type Pipe: Pipeline;

  fn pipe() -> Self::Pipe;

  fn query(&mut self, pipe: Self::Pipe) -> Option<i32>;
}

pub trait Pipeline {
  fn get(&mut self, key: &str);

  fn set(&mut self, key: &str, value: i32);
}
```

We define a `Cache` trait with an associated type `Pipe` which represents
our pipelined operations. `Pipe` is constrained to implement the `Pipeline`
trait which captures the operations the pipeline supports - this could have
been on the `Cache` trait itself but separating it out and making the
operations methods makes it more ergonomic.

Our cache provides two operations: `pipe` which creates a new
pipeline, and `query` which executes the pipeline and returns either
`Some` if the last operation was a `get` and `None` if it was a `set`[^3].

We can program against this interface by parameterizing with a
type that implements the `Cache` trait, like so:

```rust
fn program<C: Cache>(cache: &mut C) -> Option<i32> {
  let mut pipe = C::pipe();
  pipe.set("hitchiker", 42);
  pipe.get("adel");
  cache.query(pipe)
}
```

Before we can actually execute this program we need to implement `Cache` first.
First the Redis implementation:

```rust
use redis::{Connection, Pipeline as RedisPipeline, PipelineCommands};

impl Pipeline for RedisPipeline {
  fn get(&mut self, key: &str) {
    PipelineCommands::get(self, key.to_string());
  }

  fn set(&mut self, key: &str, value: i32) {
    PipelineCommands::set(self, key.to_string(), value);
  }
}

pub struct RedisInfo {
  connection: Connection,
}

impl Cache for RedisInfo {
  type Pipe = RedisPipeline;

  fn pipe() -> RedisPipeline {
    redis::pipe()
  }

  fn query(&mut self, pipe: RedisPipeline) -> Option<i32> {
    // Generally we should do something smarter here
    // but glossing over that to simplify the post
    pipe.query(&self.connection).ok()
  }
}
```

Alternatively, we could implement it with a `HashMap` which would not
actually have pipelining since everything is in-memory, but could be
useful for testing and inspecting the pipelined payload.

```rust
pub enum Ops {
  Get { key: String },
  Set { key: String, value: i32 },
}

impl Pipeline for Vec<Ops> {
  fn get(&mut self, key: &str) {
    self.push(Ops::Get { key: key.to_string() })
  }

  fn set(&mut self, key: &str, value: i32) {
    self.push(Ops::Set { key: key.to_string(), value })
  }
}

impl Cache for HashMap<String, i32> {
  type Pipe = Vec<Ops>;

  fn pipe() -> Vec<Ops> {
    Vec::new()
  }

  fn query(&mut self, pipe: Vec<Ops>) -> Option<i32> {
    pipe.iter().fold(None, |_, op| {
      match op {
        Ops::Get { key } => self.get(key).map(|i| i.clone()),
        Ops::Set { key, value } => {
          self.insert(key.clone(), value.clone());
          None
        }
      }
    })
  }
}
```

Finally, we can actually run our program with either implementation
serving as the backend.

```rust
use redis::{Client, Connection};

// Redis backend
let client = Client::open("redis://127.0.0.1/").unwrap();
let mut redis = RedisInfo { connection: client.get_connection().unwrap() };
program::<RedisInfo>(&mut redis);

// HashMap backend
let mut cache = HashMap::new();
program::<HashMap<String, i32>>(&mut cache);
```

And there we have it: a program that is parameterized by an abstract,
pipeline-supported `Cache`, two implementations of that cache, both of
which can be seamlessly plugged in. Existential types are pretty cool
(and underrated).

[mlModules]: https://v1.realworldocaml.org/v1/en/html/files-modules-and-programs.html
[ocaml]: https://ocaml.org/
[redis]: https://redis.io/
[redisCrate]: https://crates.io/crates/redis
[redisPipeline]: https://redis.io/topics/pipelining
[rust]: https://www.rust-lang.org/en-US/
[rustHkt]: https://github.com/rust-lang/rfcs/issues/324
[rustImplTrait]: https://www.infoq.com/news/2018/05/rust-1.26-existential-types
[sml]: http://sml-family.org/
[taglessFinal]: http://okmij.org/ftp/tagless-final/index.html

[^1]: Getting close though! See: [https://github.com/rust-lang/rfcs/pull/1598](https://github.com/rust-lang/rfcs/pull/1598).
[^2]: Obligatory [Constraints Liberate, Liberties Constrain](https://youtu.be/GqmsQeSzMdw).
[^3]: This is not the best type signature for the method as the `Option` return
      type is dynamic whereas statically we should know if it is a `Some`
      (last operation was a `get`) or `None` (last operation was a `set`). This
      choice was made purely to simplify the presentation of this blog post.
      I'm sorry.
