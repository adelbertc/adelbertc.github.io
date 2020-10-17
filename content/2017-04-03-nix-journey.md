+++
title = "My journey into Nix"
date = 2017-04-03
+++

As a Windows user for many years, I always liked that there was a
way to uninstall any program I installed[^1]. When I moved to Mac OS and
installed programs through the App Store, `brew`, `pip`, I quickly
realized I had no clue how to reliably uninstall them. This made me quite
uncomfortable, but I managed to live with it.

<!-- more -->

A few years later I heard about [Nix][nix] and how it solved exactly
this problem. At a glance it seemed like a good approach, but I never
got around to trying it until recently. So far I've been really liking
what I've seen and wanted to share what I learned.

## What is Nix?

Nix is a cross-platform package manager, working across Linux variants,
Mac OS, and Windows.

Nix is also a pure functional package manager, treating package installs
like a pure functional data structure. Where most package managers update
packages by mutating the install in-place, Nix installs new versions in
a separate location and shuffles some "pointers" to point to the new one.
The old one continues to exist in its original location - that is, until
the garbage collector is run.

Let's see what this actually means.

### The Nix store

Nix installs packages in the *Nix store*, located by default under `/nix/store`.
Everything lives in the Nix store, including Nix itself[^2]. Installing a package
`foo` through Nix installs it into `/nix/store/<hash>-foo-<version>`. The configuration
of `foo` determines the hash and its version determines, well, the version. This
means for any given package, the following are installed in different locations:

1. Different configuration, different version
2. Different configuration, same version
3. Same configuration, different version

Thus, installing different configurations or versions is not destructive
- the old version continues to exist in a different location. This is what makes
Nix purely functional.

If an install has dependencies (e.g. [sbt](http://www.scala-sbt.org/) depends
on a JDK), those dependencies are installed under their corresponding
`<hash>-<package>-<version>` folder. If two or more packages require the same
dependency, that dependency is shared[^3].

Here are some basic commands to get started with Nix. You may want
to run `nix-channel --update` before to make sure you have
the latest set of packages. Nix channels will be discussed later in this post.

+----------------------+-----------------------------------------------------------+
| Command              | Description                                               |
+:=====================+:==========================================================+
| `nix-env -qaP [pkg]` | Check to see if [pkg] is available through Nix, showing   |
|                      | its Nix attribute path if available.                      |
+----------------------+-----------------------------------------------------------+
| `nix-env -iA [attr]` | Install a package by its attribute path [attr].           |
+----------------------+-----------------------------------------------------------+
| `nix-env -u [pkg]`   | Update [pkg]. We can add `--dry-run` to see what would    |
|                      | be installed without actually updating if we're nervous.  |
+----------------------+-----------------------------------------------------------+
| `nix-env -e [pkg]`   | "Uninstalls" [pkg] - read the next section to learn what  |
|                      | actually happens when we uninstall a package.             |
+----------------------+-----------------------------------------------------------+

Please refer to the [Nix manual][nixManual] for more information on these commands.

### How Nix manages packages

Given this hash-based install scheme, how do we actually use a package
after it's installed? It would be annoying if we had to manually specify
the path of the package we wanted, hash and all. Nix's answer to this
is user environments, generations, and profiles.

User environments hold symlinks to the installed packages. For instance,
running `ls -l` on my currently active user environment shows something like[^4]:

```
$ ls -l /nix/store/<hash>-user-environment/bin/
cabal -> /nix/store/<hash>-cabal-install-1.24.0.2/bin/cabal
ghc-mod -> /nix/store/<hash>-ghc-mod-5.7.0.0/bin/ghc-mod
ghc-modi -> /nix/store/<hash>-ghc-mod-5.7.0.0/bin/ghc-modi
hakyll-init -> /nix/store/<hash>-hakyll-4.9.5.1/bin/hakyll-init
nix-build -> /nix/store/<hash>-nix-1.11.7/bin/nix-build
...
```

Every time a package is installed, uninstalled, or updated, a new user
environment is created with the corresponding symlinks created, removed,
or modified.

User environments are named with a hash followed by `-user-environment`,
located alongside other packages in the Nix store. This becomes important
when we look at how removing packages works.

Symlinked to user environments are generations, located outside of the
store (but still under `/nix`) in `/nix/var/nix/profiles`. Running `ls -l`
shows something like:

```
$ ls -l /nix/var/nix/profiles/
default -> default-23-link
default-20-link -> /nix/store/<hash>-user-environment
default-21-link -> /nix/store/<hash>-user-environment
default-22-link -> /nix/store/<hash>-user-environment
default-23-link -> /nix/store/<hash>-user-environment
...
```

Here the `default-N-link` symlinks are *generations* for the `default` *profile*.
Whenever a user environment is created, a corresponding generation is created
that points to it. The profile is then modified to point at this new generation.
Since symlinking is an atomic operation, these series of symlinks allow Nix to
perform atomic upgrades. If at any point during an install we decide to hit `Ctrl+C`,
our profile is left untouched. The Nix store may contain dirty state leftover from
the terminated install, but those will get handled if the install is retried or the garbage
collector is run.

We're almost ready to get the packages on our `PATH`. In each user's home
directory there is a `~/.nix-profile` symlink which points at their profile
(different users may have different profiles). When Nix was installed,
it added a statement in the user's bash profile (e.g. `~/.profile`) to
source a script in this profile which chases the symlinks all the way down and
adds the `bin` to the `PATH`.

```
$ cat ~/.profile
...

if [ -e /.../.nix-profile/etc/profile.d/nix.sh ]; then
  . /.../.nix-profile/etc/profile.d/nix.sh;
fi

...
```

### Rollbacks

Because Nix does not do destructive updates, rollbacks are easy.

```
$ nix-env --rollback
```

What is interesting is we can even rollback uninstalls. To Nix, this is
no different than rolling back an install. Each install, uninstall, and
update creates a new user environment with a new generation. A rollback
simply changes the pointer to point at the previous generation.

We can also rollback to a specific generation.

```
$ nix-env --list-generations
  20   2017-03-17 10:57:28
  21   2017-03-21 21:44:18
  22   2017-03-21 21:46:56
  23   2017-03-26 12:23:13   (current)

$ nix-env --switch-generation 22
```

The numbers here correspond to the numbers in the symlinks.

### Garbage collection

Up to this point we've only seen Nix add packages to the store.
Given our machines have limited disk space, at some point Nix needs
to actually delete packages from the store.

Nix does this via *garbage collection*, sharing the same name
and purpose as the memory management mechanism. Where in programs
garbage collection tracks object references, Nix tracks symlinks
into the Nix store.

Recall that generations are symlinks into user environments located
in the store, which in turn are symlinks to packages. This means
that so long as generations are never deleted, every package is
reachable and ineligible for garbage collection (consider what
happens if a package was garbage collected and we then switched
to a generation that referenced that package).

Therefore in order for packages to be removed, generations need to
be deleted. Generation deletion is an explicit step done by the
user - Nix will not delete generations by itself.

One way to delete generations is by number.

```
$ nix-env --delete-generations 20 21
removing generation 20
removing generation 21
$ nix-env --list-generations
  22   2017-03-21 21:46:56
  23   2017-03-26 12:23:13   (current)
```

To delete all old generations, we can use `nix-env --delete-generations old`.

Now we have some user environments, and by extension packages, with no
references to them. We can see what these are by running
`nix-store --gc --print-dead`. To run the garbage collector and delete
them, we run `nix-store --gc`.

### Nix the language

"Nix" refers to the package manager we've been discussing, but also to
the related programming language. Packages in Nix are specified by
expressions written in Nix the language. These expressions create *derivations*
which tell Nix how to build a package.

At this point I could write a tutorial on the Nix language, but it would just end up being an
ad-hoc, informally-written, bug-ridden copy of the
[Nix manual chapter on expressions][nixExpressions] and
[Nix by example: The Nix expression language][nixByExample][^5]. If you're
interested in learning about Nix the language, I would recommend reading those.

I have also been told by several people that the [Nix pill][nixPill] series is
very good. I've yet to read it myself, but it's definitely on my to-read list.

### Nixpkgs

[Nixpkgs][nixpkgs] is the primary way of installing packages through Nix. Nixpkgs
is a repository of Nix expressions, each of which tell Nix how to build a package
from source. For example, [here][hello] is the Nix expression for building GNU Hello.

Different operating systems will track Nixpkgs through different *channels*, which are
essentially branches of the repository. I use Mac OS, so my Nix tracks the "unstable"
channel which is the master branch after it passes through a periodically running
CI.

```
$ nix-channel --list
nixpkgs https://nixos.org/channels/nixpkgs-unstable
```

While Nix derivations tell Nix how to build a package from source, this doesn't mean we're
doomed to say, build Rust from source (which involves multiple bootstraps of the compiler).
Whenever we ask Nix to install a package, it will first check an upstream cache for a
previously built binary[^6]. If the binary exists it is downloaded to the appropriate location
and the install completes. It is only when the binary doesn't exist that the system builds
the package from source.

## Freedom to explore

The best part of Nix is that it gives us the freedom to explore.  With traditional
package managers every install and upgrade is risky. With Nix these are guaranteed not to
cause problems. If we install something and don't like what we see, a rollback is just a
command away. This enables us to discover, experiment, and play with new packages risk-free,
a truly liberating feeling.

## Further reading

Here are some resources I found valuable when learning Nix.

1. [Nix manual][nixManual]
2. [Purely Functional Linux with NixOS][pflwNixOs]
3. [Nixpkgs manual][nixpkgsManual]

[hello]: https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/misc/hello/default.nix
[hydra]: http://nixos.org/hydra/
[nix]: http://nixos.org/nix/
[nixByExample]: https://medium.com/@MrJamesFisher/nix-by-example-a0063a1a4c55
[nixExpressions]: http://nixos.org/nix/manual/#chap-writing-nix-expressions
[nixInstall]: http://nixos.org/nix/manual/#chap-installation
[nixManual]: http://nixos.org/nix/manual/
[nixPill]: http://lethalman.blogspot.com/2014/07/nix-pill-1-why-you-should-give-it-try.html
[nixpkgs]: http://nixos.org/nixpkgs/
[nixpkgsManual]: http://nixos.org/nixpkgs/manual/
[pflwNixOs]: https://begriffs.com/posts/2016-08-08-intro-to-nixos.html

[^1]: I know this isn't entirely true due to files the program may
      keep in other places, but I didn't know that at the time.

[^2]: When you [install Nix][nixInstall], the installer places the Nix tools in the store
      as if it were installed by Nix itself. This bootstraps Nix to be managed by Nix,
      and makes it easy to opt out if you decide Nix isn't for you (just destroy the
      Nix store).

[^3]: This behavior matches exactly that of persistent data structures, and is safe for
      the same reasons.

[^4]: Here we see Nix tools like `nix-build` are installed alongside packages.

[^5]: [Greenspun's tenth rule](https://en.wikipedia.org/wiki/Greenspun's_tenth_rule)

[^6]: These pre-built binaries are built by a central [Hydra][hydra] cluster.
