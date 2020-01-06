---
title: Setting up per-project RLS for Emacs with Nix and Direnv
---

One of my favorite things about [Nix][nix] is using the nix-shell to provision the development tooling for a project
without infecting the rest of the system. Even if the project itself isn't built with Nix, I will often have a
`shell.nix` just to provision tools like [Cargo][cargo] and [SBT][sbt]. This becomes especially helpful with Rust
where each of my Rust projects can have a different `rustc` version without needing to switch my [rustup][rustup] toolchain.

To that effect, I've setup my Emacs to use the Direnv integration [emacs-direnv][direnvEmacs] to provision the buffer's environment using the project's
Nix shell whenever I open a file in that project --- if you're not familiar with Direnv I encourage you to
read about it [here][direnv]. That combined with Emacs [Language Server Protocol][lsp] (LSP) integration via [lsp-mode][lspMode] and
the [Rust Language Server][rls] (RLS) and I've got a setup that allows me to switch between Rust projects using
varying Rust versions without hassle.

This setup took a bit of fiddling to work so I thought I'd share it here for the public and to document for myself so I don't forget.

## Setting up Emacs

The core plugins I use to get this setup working are direnv, lsp-mode, lsp-ui, and company-lsp. **For direnv, besides installing
the Emacs plugin, make sure to install Direnv itself on your system as well.** For the LSP plugins, I've setup my Emacs to use
"recent" versions of the plugins since LSP integration is ever-evolving ---  I haven't bothered to test what the
oldest working versions of these plugins are, but at time of writing the versions I'm using are `20191016.1813` for lsp-mode,
`20191016.1644` for lsp-ui, and `20190612.1553` for company-lsp. For those managing their Emacs plugins with Nix,
you can try doing what I do in [my Emacs Nix overlay][myEmacsOverlay] to get versions newer than upstream Nixpkgs may provide.

From there my Emacs setup is largely taken from the [Metals][metals] (Scala Language Server) Emacs tutorial, with some
additions to hook in direnv.

```commonlisp
(use-package direnv
  :init
  (add-hook 'prog-mode-hook #'direnv-update-environment)
  :config
  (direnv-mode))
  
(use-package company-lsp
  :defer t)

(use-package lsp-mode
  :after (direnv evil)
  :config
  ; We want LSP
  (setq lsp-prefer-flymake nil)
  ; Optional, I don't like this feature
  (setq lsp-enable-snippet nil)
  ; LSP will watch all files in the project
  ; directory by default, so we eliminate some
  ; of the irrelevant ones here, most notable
  ; the .direnv folder which will contain *a lot*
  ; of Nix-y noise we don't want indexed.
  (setq lsp-file-watch-ignored '(
    "[/\\\\]\\.direnv$"
    ; SCM tools
    "[/\\\\]\\.git$"
    "[/\\\\]\\.hg$"
    "[/\\\\]\\.bzr$"
    "[/\\\\]_darcs$"
    "[/\\\\]\\.svn$"
    "[/\\\\]_FOSSIL_$"
    ; IDE tools
    "[/\\\\]\\.idea$"
    "[/\\\\]\\.ensime_cache$"
    "[/\\\\]\\.eunit$"
    "[/\\\\]node_modules$"
    "[/\\\\]\\.fslckout$"
    "[/\\\\]\\.tox$"
    "[/\\\\]\\.stack-work$"
    "[/\\\\]\\.bloop$"
    "[/\\\\]\\.metals$"
    "[/\\\\]target$"
    ; Autotools output
    "[/\\\\]\\.deps$"
    "[/\\\\]build-aux$"
    "[/\\\\]autom4te.cache$"
    "[/\\\\]\\.reference$")))
```

## Setting up the project

Once Emacs is ready to roll we need a `shell.nix` to provision an environment with Nix and
an `.envrc` to tell direnv to use said `shell.nix` when entering the project.

While Nixpkgs has [some Rust integration][nixpkgsRust], it does not provide many knobs for us
to turn in terms of the Rust environment we want, like the compiler version or toolchain
extensions like `rust-src`. Thankfully, the kind folks at Mozilla published a
[Nix overlay][mozillaOverlay] that makes it much more ergonomic to work with Rust in Nix.

Most of the `shell.nix` then is boilerplate to pull and setup this overlay. From there
it's just a matter of specifying the Rust version we want, along with the extensions we want
for RLS.

```nix
let
  rust-version = "1.40.0";

  nixpkgs = fetchGit {
    url = "https://github.com/NixOS/nixpkgs.git";
    rev = "a3070689aef665ba1f5cc7903a205d3eff082ce9";
    ref = "release-19.09";
  };

  mozilla-overlay =
    import (builtins.fetchTarball https://github.com/mozilla/nixpkgs-mozilla/archive/master.tar.gz);

  pkgs = import nixpkgs {
    overlays = [ mozilla-overlay ];
  };

  rust-channel = pkgs.rustChannelOf {
    channel = rust-version;
  };

  rust = rust-channel.rust.override {
    extensions = [ "rust-src" ];
  };

  cargo = rust-channel.cargo;
in
  pkgs.mkShell {
    name = "rust-dev";
    buildInputs = [ rust cargo ];
  }
```

As for the `.envrc`, Direnv comes with [Nix bindings][direnvNix] so all we need in
that file is:

```sh
use_nix
```

Now we just need to `direnv allow` to whitelist the project for Direnv,
open a file in the project, and reap the rewards --- you should see a little
"LSP :: Connected to [rls:XXX status:starting]" diagnostic in the
minibuffer indicating great success. There may be some lag when you open the project
for the first time as Nix is pulling the dependencies, or before any diagnostics appear as
RLS is working in the background to download Rust dependencies and compiling the project. To
make the former a bit more tolerable, I will run `nix-shell` in a terminal outside of
Emacs so I can actually see the download progress instead of staring at a locked Emacs session.
For the latter, lsp-mode and RLS have the `lsp-log`, `rls`, and `rls::stderr` buffers you can
open to see progress or debug any issues you may encounter.

## Other languages

Much of this setup translates readily to other languages or other Emacs language modes. Likely
all you will need to do is get a `shell.nix` that provisions the correct environment with any
tools your language mode needs and you're off to the races. Keep in mind though that some languages
(e.g. Scala) and their corresponding language servers (e.g. SBT + Metals) already have native support
for project-specific compiler versions so the only win you may get from mimicking this setup in
those cases is consistency.

[cargo]: https://github.com/rust-lang/cargo
[direnv]: https://github.com/direnv/direnv/
[direnvEmacs]: https://github.com/wbolster/emacs-direnv
[direnvNix]: https://github.com/direnv/direnv/wiki/Nix
[lsp]: https://langserver.org/
[lspMode]: https://github.com/emacs-lsp/lsp-mode
[metals]: https://scalameta.org/metals/docs/editors/emacs.html
[mozillaOverlay]: https://github.com/mozilla/nixpkgs-mozilla
[myEmacsOverlay]: https://github.com/adelbertc/dotfiles/blob/0840e5f3060f61f199f9431765dec307df6b0c6e/nixpkgs/.config/nixpkgs/overlays/emacs.nix
[nix]: https://nixos.org/nix/
[nixpkgsRust]: https://nixos.org/nixpkgs/manual/#rust
[rls]: https://github.com/rust-lang/rls
[rustup]: https://rustup.rs/
[sbt]: https://www.scala-sbt.org/
