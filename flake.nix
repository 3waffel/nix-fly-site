{
  description = "Deploy Static Site on Fly.io";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit self;} {
      systems = ["x86_64-linux" "aarch64-darwin"];
      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: let
        caddy-config = pkgs.writeText "Caddyfile" ''
          {
          	auto_https off
          }

          :8080 {
          	root * {$SITE_ROOT}
          	encode gzip
          	file_server

          	handle_errors {
          		@404 {
          			expression {http.error.status_code} == 404
          		}
          		rewrite @404 /404.html
          		file_server
          	}
          }
        '';
      in {
        devShells.default = with pkgs;
          mkShell {
            buildInputs = [
              zola
              flyctl
            ];
          };

        packages.default = with pkgs;
          stdenv.mkDerivation {
            name = "static-site";
            src = ./.;
            nativeBuildInputs = [
              zola
            ];
            buildPhase = ''
              zola build
            '';
            installPhase = ''
              cp -r public $out
            '';
          };

        packages.container = with pkgs;
          dockerTools.buildLayeredImage {
            name = "static-site";
            tag = "2022-11-16";
            config = {
              Cmd = ["${caddy}/bin/caddy " "run" "-config" "${caddy-config}"];
              Env = [
                "SITE_ROOT=${config.packages.default}"
              ];
            };
          };

        apps.deploy = with pkgs;
          writeShellScriptBin "deploy" ''
            set -euxo pipefail
            export PATH="${lib.makeBinPath [(docker.override {clientOnly = true;}) flyctl]}:$PATH"
            archive=${config.packages.container}
            image=$(docker load < $archive | awk '{ print $3; }')
            flyctl deploy -i $image
          '';
      };
    };
}
