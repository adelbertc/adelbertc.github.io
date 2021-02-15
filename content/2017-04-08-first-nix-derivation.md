+++
title = "My first Nix derivation"
date = 2017-04-08
[taxonomies]
tags=["code", "nix"]
+++

When I started learning Nix I set myself a milestone of contributing a derivation
to Nixpkgs. Along the way I learned some interesting things about the Nix toolchain
and began to really appreciate the freedom it gave me to experiment.

<!-- more -->

I noticed [Coursier][coursier] was not in Nixpkgs and decided it would
be a good project to complete my milestone. The fact that it has a
[pretty easy install][coursierInstall] helped as well. In this post I have tried to reproduce
my thought process in writing the derivation, though in some places I have altered
history for a (ostensibly) better narrative.

## Monkey see, monkey do

When I started on this I had read the [Nix manual chapter on expressions][nixExpressions],
the [Nixpkgs manual][nixpkgsManual], and [Nix by example][nixByExample]. These were
all good resources, but I still felt lost as to how to get started. I eventually decided
to start by looking at and copying the [Nix expression][ammoniteDerivation] for
[Ammonite][ammonite] which has a similar install process as Coursier.

I cloned the [Nixpkgs repository][nixpkgsRepo] and copied
the Ammonite expression into `./nixpkgs/pkgs/development/tools/coursier/default.nix`[^1],
changing the appropriate values and removing what I thought unnecessary or didn't understand.
This left me with the following expression.

```{ .nix .numberLines }
{ stdenv, fetchurl }:

stdenv.mkDerivation rec {
  name    = "coursier-${version}";
  version = "1.0.0-M15-5";

  src = fetchurl {
    url    = "https://github.com/coursier/coursier/raw/v${version}/coursier";
    sha256 = "610c5fc08d0137c5270cefd14623120ab10cd81b9f48e43093893ac8d00484c9";
  };

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/coursier
    chmod +x $out/bin/coursier
  '';
}
```

This expression is specifically a function, the arguments of which are on line 1.
Without getting into too much detail[^2] `stdenv` provides basic tools
like Bash and `cp`, and `fetchurl` provides a way to well, fetch from
a URL.

In the body of the function I make a derivation - a derivation describes how to
build a package from source. `stdenv.mkDerivation` is a convenience function that
takes a set of standard attributes which it will use to create a derivation.
The `rec` allows attributes within the set to refer to each other, such as `version`
in the definition of `name`. The rest reads pretty declaratively.

The `installPhase` uses tools like `mkdir`, `cp`, and `chmod` - these are provided
by `stdenv`. If I omitted the `stdenv` argument these tools would not be available
to me (nor would I be able to call `stdenv.mkDerivation`).

`installPhase` also references `${src}` and `$out`. The choice to use or omit
braces here is not accidental - with braces the contents will be expanded within Nix
and without braces the contents will be expanded in Bash (using environment variables).
Here this means `${src}` will interpolate the result of the `src` attribute (line 7) into
the Nix expression during evaluation, and `$out` will be filled in by Bash at
install time by looking for an `$out` environment variable (more on this in a bit).

## Testing

Now I wanted to test this function by running it through Nix and making sure everything
was OK. So far I had just written a function but it needed to be called to actually create
the derivation and run the builder. This occurs in `nixpkgs/pkgs/top-level/all-packages.nix`
which contains the set of all Nix packages. The code is organized by the type of
package - Coursier is a tool so I put the following under the Tools section, copied again
from what I saw other packages do.

```{ .nix }
coursier = callPackage ../development/tools/coursier {};
```

`callPackage` is another convenience function that takes the path of a Nix function and calls
it, filling in the arguments by looking for an attribute of the same name in the surrounding
set of Nixpkgs. For instance the `stdenv` argument is filled in by looking for the
`stdenv` attribute in the Nixpkgs set.

With that in place, I ran `nix-build -A coursier -K` in the root of the `nixpkgs` directory.
This command builds and installs `coursier`, placing a `result` symlink to the install in the current
directory. Running `nix-build` in the `nixpkgs` directory makes Nix use our local copy
instead of going somewhere else to look for it[^3]. The `-K`
tells Nix to keep the temporary directory used for the build even in the event of a failure, which is
useful for debugging.

After running that command I was greeted with a wall of scrolling text which
eventually ended in:

```{ .numberLines }
building path(s) ‘/nix/store/<hash>-coursier-1.0.0-M15-5’
unpacking sources
unpacking source archive /nix/store/<hash>-coursier
do not know how to unpack source archive /nix/store/<hash>-coursier
note: keeping build directory ‘/.../nix-build-coursier-1.0.0-M15-5.drv-0’
builder for ‘/nix/store/<hash>-coursier-1.0.0-M15-5.drv’ failed with exit code 1
error: build of ‘/nix/store/<hash>-coursier-1.0.0-M15-5.drv’ failed
```

Two lines here stood out to me: the fourth line indicating the error, and the one
following it giving the path of the aforementioned temporary directory.

Looking into the directory there was just one file named `env-vars`. I have
reproduced a subset of the contents below.

```
declare -x name="coursier-1.0.0-M15-5"
declare -x nativeBuildInputs=""
declare -x out="/nix/store/<hash>-coursier-1.0.0-M15-5"
declare -x src="/nix/store/<hash>-coursier"
declare -x version="1.0.0-M15-5"
```

Many of these lines declare variables sharing the same names as the attributes
given to `mkDerivation`. Of particular interest is the `out` variable which I
referenced earlier. Here Nix had automatically set it to be the path that Coursier
was going to be installed into.

As for the error, I was very confused when I first read it. It suggested
Nix was unable to "unpack" something, but I wasn't trying to
unpack anything - the Coursier download was a single file.
Looking through the Nix manual some more, I realized `mkDerivation` had some default
behavior I did not want. It assumed the source fetched was
compressed in something like a tarball (which is often the case) so it tried
to take extra steps behind the scenes to unpack it. Since Coursier was not compressed
unpacking it would be futile, hence the error.

The individual steps `mkDerivation` takes to install is specified by the
`phases` attribute. Omitting this attribute makes `mkDerivation`
use the aformentioned default behavior. In my case I just wanted the one phase, thus[^4]:

```{ .nix }
{ stdenv, fetchurl }:

stdenv.mkDerivation rec {
  name    = "coursier-${version}";
  version = "1.0.0-M15-5";

  src = fetchurl {
    url    = "https://github.com/coursier/coursier/raw/v${version}/coursier";
    sha256 = "610c5fc08d0137c5270cefd14623120ab10cd81b9f48e43093893ac8d00484c9";
  };

  phases = "installPhase";

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/coursier
    chmod +x $out/bin/coursier
  '';
}
```

I ran the `nix-build` command again and this time it worked, leaving a `result`
symlink in the current directory.

```
$ ls -l result
result -> /nix/store/<hash>-coursier-1.0.0-M15-5
```

Coursier was now installed in my Nix store, but referenced only by this symlink. This
means if I deleted the symlink and ran the garbage collector, my system would be as
it was before. As someone who tries to keep a clean system, knowing this really
helped put me at ease.

I then ran `./result/bin/coursier --help` which produced the expected help message,
letting me know the install succeeded.

## Or did it?

At this point I was ready to call it done and submit a pull request. However, I
soon remembered that running Coursier the way I did did not mean my Nix expression
was correct - it was possible my computer's configuration had an effect. Because Nix's
model wants all dependencies to be explicitly declared, my job was not done.

Thankfully, Nix provides a way to test this. Running
`nix-shell -A coursier --pure` in the `nixpkgs` directory drops me into a
shell with nothing on my `PATH` except for what is declared as Coursier's
dependencies. This effectively replicates the environment used to build Coursier.

Here's what happened when I tried to run `./result/bin/coursier --help` from
that shell.

```
$ nix-shell -A coursier --pure

[nix-shell:~/github/nixpkgs]$ ./result/bin/coursier --help
./result/bin/coursier: line 2: exec: java: not found
```

Uh oh. It turns out that Coursier needs Java to run (it is written in Scala) and
when I ran it earlier it was picking up Java from my own configured `PATH`.
Inside a pure Nix shell there was no Java, so it errored out. The derivation needed
to be fixed.

I went back and revisited the Ammonite derivation, looking at what I had removed.
I knew that like Coursier, Ammonite was downloaded as a single script which referenced
`java` (it too was written in Scala), and wanted to see how it handled that.
I noticed it had a dependency on `jre` which sounded like what I wanted,
but it also had this `makeWrapper` thing that was used in the install process.

A quick search turned up the Nix wiki article on the
[Nix Runtime Environment Wrapper][makeWrapper] which outlined what `makeWrapper`
was used for.

> The makeWrapper package adds a shell function, wrapProgram, which will ensure the
> specified program has the specified environment when it is executed.

The use of `makeWrapper` now made sense - since Ammonte, like Coursier, blindly calls `java` it
expects there to be one on the `PATH`. By using `makeWrapper` I could add the
JRE to the `PATH` before calling the script.

In general the way `makeWrapper` works is by renaming the target file by prepending
the name with a `.` and appending it with `-wrapped`. A new file is then created
with the original name which sets the `PATH` according to the arguments passed to it
before calling the original script.

`makeWrapper` also needs to be specified in `nativeBuildInputs` - this makes it so
`makeWrapper` is available at install time but discarded afterwards.

Adding these modifications gave:

```{ .nix }
{ stdenv, fetchurl, makeWrapper, jre }:

stdenv.mkDerivation rec {
  name    = "coursier-${version}";
  version = "1.0.0-M15-5";

  src = fetchurl {
    url    = "https://github.com/coursier/coursier/raw/v${version}/coursier";
    sha256 = "610c5fc08d0137c5270cefd14623120ab10cd81b9f48e43093893ac8d00484c9";
  };

  nativeBuildInputs = [ makeWrapper ];

  phases = "installPhase";

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/coursier
    chmod +x $out/bin/coursier
    wrapProgram $out/bin/coursier --prefix PATH ":" ${jre}/bin ;
  '';
}
```

I then ran it through `nix-build` and dropped into the `nix-shell` again.

```
[nix-shell:~/github/nixpkgs]$ ls -a result/bin/
.  ..  .coursier-wrapped  coursier

[nix-shell:~/github/nixpkgs]$ cat result/bin/coursier
#! /nix/store/<hash>-bash-4.4-p12/bin/bash -e
export PATH=/nix/store/<hash>-zulu1.8.0_121-8.20.0.5/bin${PATH:+:}$PATH
exec -a "$0" "/nix/store/<hash>-coursier-1.0.0-M15-5/bin/.coursier-wrapped"  "${extraFlagsArray[@]}" "$@"

[nix-shell:~/github/nixpkgs]$ ./result/bin/coursier --help
Coursier 1.0.0-M15
Usage: coursier [options] [command] [command-options]

Available commands: bootstrap, fetch, launch, resolve, spark-submit

Type  coursier command --help  for help on an individual command
```

Hurrah!

## Finishing up

All that was left now was to give some meta-information and submit
the pull request. The meta attribute just gives descriptive information
about the package itself such as its homepage and description.
I've reproduced the meta information I gave for Coursier below.

```
meta = with stdenv.lib; {
  homepage    = http://get-coursier.io/;
  description = "A Scala library to fetch dependencies from Maven / Ivy repositories";
  license     = licenses.asl20;
};
```

With that in place, I filed the [pull request][pr], got some feedback,
addressed them, and a day later it was merged!

## Don't just read, do

The majority of my process during this project involved digging around the codebase,
copying code, and figuring out what it did. I do believe this is a perfectly good
way of learning things especially when you're first getting started, so long as you work
hard to understand the things you're copying (a good way to do this is
to delete anything you don't understand and seeing what the consequences are).
In writing the expression for Coursier I learned about the subtle default behaviors of
`mkDerivation` and how to use `nix-build` and `nix-shell` to test without fear.

If you get stuck,
search around the manual, the wiki, or ask questions on the `#nixos` IRC channel.
I asked many questions in the IRC channel and the answers were always very
helpful and instructive.

At the end of the day what's most important is getting started and actually writing code
- you can only read so much before you stop internalizing information.

[ammonite]: http://www.lihaoyi.com/Ammonite/
[ammoniteDerivation]: https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/tools/ammonite/default.nix
[coursier]: https://github.com/coursier/coursier
[coursierInstall]: https://github.com/coursier/coursier#command-line
[makeWrapper]: https://nixos.org/wiki/Nix_Runtime_Environment_Wrapper
[nixByExample]: https://medium.com/@MrJamesFisher/nix-by-example-a0063a1a4c55
[nixExpressions]: http://nixos.org/nix/manual/#chap-writing-nix-expressions
[nixpkgsManual]: http://nixos.org/nixpkgs/manual/
[nixpkgsRepo]: https://github.com/NixOS/nixpkgs
[pr]: https://github.com/NixOS/nixpkgs/pull/24108

[^1]: I decided on this path by poking around Nixpkgs and seeing where a tool like Coursier would fit.
      I saw Ammonite was under development tools and figured Coursier would fit under there too.

[^2]: For a more in-depth discussion about these, refer to the [Nix manual][nixExpressions] section
      on Nix expressions.

[^3]: Specifically `nix-build` will use the `default.nix` file in the current directory to configure
      itself if no path is specified.

[^4]: I could have written `["installPhases"]` which would have made it a list (and perhaps be the
      more accurate thing to do) and it would have continued to work. Since Nix is dynamically typed it is
      fine with either a string or list here.
