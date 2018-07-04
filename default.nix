let
  pkgs = import ((import <nixpkgs> { }).fetchFromGitHub {
    owner  = "NixOS";
    repo   = "nixpkgs";
    rev    = "43d3e539c5cd3b0ce0d08ca1b17831146da81a5f";
    sha256 = "03r2ddpk2v17sc0742kdfnlj8sn5l60vz8a03ryiqsk5hkwn8cbv";
  }) { };

  stdenv = pkgs.stdenv;
  lib    = pkgs.lib;

  generator = stdenv.mkDerivation {
    name = "adelbertc.github.io-generator";
    src = lib.cleanSource ./generator;
    buildInputs = [
      (pkgs.haskellPackages.ghcWithPackages (hpkgs: with hpkgs; [ hakyll ]))
    ] ++ lib.optional stdenv.isDarwin pkgs.darwin.apple_sdk.frameworks.Cocoa;
    phases = "unpackPhase buildPhase";
    buildPhase = ''
      ghc -O2 --make site.hs -o $out
    '';
  };
in
  stdenv.mkDerivation {
    name = "adelbertc.github.io";
    src = lib.cleanSource ./src;
    phases = "unpackPhase buildPhase installPhase";
    buildPhase = "${generator} build";
    installPhase = ''
      mkdir -p $out
      cp -r _site/* $out
    '';
  }
