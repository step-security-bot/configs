{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.homepage;
  revision = "ab45143f7c3d47e0f0fcc0aca3a62baebaa242f2";
  user = "homepage";

  homepage-app = (import (pkgs.fetchFromGitHub {
    owner = "pSub";
    repo = "pascal-wittmann.de";
    rev = "9d407021cae710a97f8b351f6e89210de6c6a1f4";
    sha256 = "1vx2vjrn3d1yip6farbvf179xdiz987lf51fvss2dkrxjjy1ikac";
  })) { };

in {
  options = {
    services.homepage.enable = mkEnableOption "Wheter to enable pascal-wittmann.de";
  };

  config = mkIf cfg.enable {
    users.extraUsers = singleton
    { name = user;
      uid = 492;
      description = "Homepage pascal-wittmann.de";
      home = "/var/homepage";
    };

    services.lighttpd.enableModules = [ "mod_redirect" "mod_proxy" "mod_setenv" ];
    services.lighttpd.extraConfig = ''
      $HTTP["scheme"] == "http" {
        $HTTP["host"] =~ "^(www\.|)pascal-wittmann\.de$" {
          url.redirect = (".*" => "https://%0$0")
        }
      }

      $HTTP["scheme"] == "https" {
        $HTTP["host"] =~ "^(www\.|)pascal-wittmann\.de$" {
          proxy.balance = "hash"
          proxy.server  = ( "" => (( "host" => "127.0.0.1", "port" => 3001 )))
        }
      }
    '';

    systemd.services.homepage = {
      description = "Personal Homepage powered by Yesod";
      wantedBy = [ "multi-user.target" ];
      after = [ "lighttpd.service" "postgresql.service" ];
      bindsTo = [ "lighttpd.service" "postgresql.service" ];
      environment = {
        APPROOT = "https://www.pascal-wittmann.de";
        PORT = "3001";
        PGUSER = user;
        PGPASS = import ../secrets/homepage_database_password;
        PGDATABASE = "homepage_production";
        GITHUB_OAUTH_CLIENT_ID = "82fa60e9329799fe88f8";
        GITHUB_OAUTH_CLIENT_SECRET = import ../secrets/github_oauth_client_secret;
      };
      script = ''
        cd /srv/homepage
        ${homepage-app}/bin/homepage
      '';
      serviceConfig.KillSignal = "SIGINT";
      serviceConfig.User = "homepage";
    };
  };
}
