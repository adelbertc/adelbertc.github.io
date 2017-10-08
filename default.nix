# Nix build for my blog, copied and adapated from:
#   https://utdemir.com/posts/hakyll-on-nixos.html
#   http://www.cs.yale.edu/homes/lucas.paul/posts/2017-04-10-hakyll-on-nix.html

{ pkgs ? import <nixpkgs> { } }:

let
  stdenv = pkgs.stdenv;
  darwinDeps = if stdenv.isDarwin then [ pkgs.darwin.apple_sdk.frameworks.Cocoa ] else [];

  # Name of build and executable for the Hakyll site generator
  generateMySiteName = "generateMySite";

  generateMySite = stdenv.mkDerivation {
    name        = generateMySiteName;
    src         = ./generator;
    phases      = "unpackPhase buildPhase";
    buildInputs = [
      (pkgs.haskellPackages.ghcWithPackages (haskellPkgs: [ haskellPkgs.hakyll ]))
    ] ++ darwinDeps;
    buildPhase  = ''
      mkdir -p $out/bin
      ghc -O2 --make site.hs -o $out/bin/${generateMySiteName}
    '';
  };
in
  stdenv.mkDerivation {
    name        = "my-site";
    src         = ./src;
    phases      = "unpackPhase buildPhase";
    buildInputs = [ generateMySite ];
    buildPhase  = ''
      ${generateMySiteName} build
      mkdir $out
      cp -r _site/* $out
    '';
  }
