let
  nixpkgs = fetchGit {
    url = "https://github.com/NixOS/nixpkgs.git";
    rev = "b3dea4a166073f22f71fb9cca4331b6937013582";
    ref = "nixpkgs-20.09-darwin";
  };

  pkgs = import nixpkgs { };
in
  pkgs.mkShell {
    name = "web-dev";
    buildInputs = with pkgs; [ zola ];
  }
