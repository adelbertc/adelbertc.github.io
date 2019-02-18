let
  pkgs = import ((import <nixpkgs> { }).fetchFromGitHub {
    owner  = "NixOS";
    repo   = "nixpkgs";
    rev    = "c395d6250788686120aa1a00404b4de1a2fb547c";
    sha256 = "1j8s23b0jcmy2vza0qz1i258avi4zbcwdxl5f0w0am1vj7icsx3r";
  }) { };

  stdenv = pkgs.stdenv;
  lib    = pkgs.lib;

  generator = stdenv.mkDerivation {
    name = "adelbertc.github.io-generator";
    src = lib.cleanSource ./generator;
    buildInputs = [
      (pkgs.haskellPackages.ghcWithPackages (hpkgs: with hpkgs; [ hakyll ]))
    ] ++ lib.optional stdenv.isDarwin [ pkgs.darwin.apple_sdk.frameworks.Cocoa pkgs.darwin.libiconv ];
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
