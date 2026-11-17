{
  description = "terraform-aws-organization";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
    {
      # Everything pre-commit needs, locally and in CI.
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            env.TENV_AUTO_INSTALL = "true";
            packages = with pkgs; [
              # terraform: tenv's proxy installs the version in .terraform-version
              # (min-required: the floor of required_version in versions.tf)
              tenv
              prek
              tflint
              terraform-docs
              # tests/forwarder.test.mjs
              nodejs_24
            ];
          };
        }
      );
    };
}
