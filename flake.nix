{
  description = "linear-cli — a single-binary Linear client built with Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Pinned, not `zig`: 0.15.2 cannot link on macOS 26 and the 0.16
            # std.Io migration is not backward compatible, so the shell has to
            # agree with .github/workflows/*.yml and the README.
            zig_0_16

            # `zig build lint` shells out to this binary and fails with
            # FileNotFound when it is absent — which is why the step was left
            # out of CI. .ziglint.zon holds the rule set.
            ziglint

            # scripts/check-versions.sh and scripts/publish-npm.sh both parse
            # the package manifests with jq.
            jq
          ];
        };
      }
    );
}
