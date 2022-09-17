{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.homepage;

  homepage-app = (
    import (
      pkgs.fetchFromGitHub {
        owner = "pSub";
        repo = "pascal-wittmann.de";
        rev = "a29cd95b4f3feb7fa149a2db1f19b9003a3f8525";
        sha256 = "1ivr8wlb06ib77bv0yz6jq1zz53df6qqnhvs2rlnicgknzh95qfv";
      }
    )
  ) {
    nixpkgs = import (
      fetchTarball
        "https://nixos.org/channels/nixos-21.11/nixexprs.tar.xz"
    )
      {};
   };
in
{
  options = {
    services.homepage.enable =
      mkEnableOption "Whether to enable pascal-wittmann.de";
  };

  config = mkIf cfg.enable {
    users.extraUsers.homepage = {
      uid = 492;
      description = "Homepage pascal-wittmann.de";
      home = "/var/homepage";
      group = "homepage";
      extraGroups = [ "mail" ];
    };

    users.extraGroups.homepage.name = "homepage";

    services.postgresql.ensureDatabases = [ "homepage_production" ];

    services.nginx.virtualHosts = {
      "www.pascal-wittmann.de" = {
        forceSSL = true;
        enableACME = true;

        locations."/" = {
          extraConfig = "return 301 https://pascal-wittmann.de$request_uri;";
        };

      };

      "pascal-wittmann.de" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = { proxyPass = "http://127.0.0.1:3001"; };
        extraConfig = ''
          add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
          add_header X-Content-Type-Options nosniff;
          add_header X-XSS-Protection "1; mode=block";
          add_header X-Frame-Options DENY;

          rewrite ^/datenschutz$ /privacy permanent;
          rewrite ^/impressum$ /contact permanent;
          rewrite ^/category/(.+)/entry/(.+)$ /entry/$2 permanent;
          rewrite ^/category/(.+)/entry/(.+)/reply-to/(\d+)$ /entry/$2/reply-to/$3 permanent;
        '';
      };
    };

    systemd.services.homepage = {
      description = "Personal Homepage powered by Yesod";
      wantedBy = [ "multi-user.target" ];
      wants = [ "nginx.service" "postgresql.service" ];
      after = [ "nginx.service" "postgresql.service" ];
      bindsTo = [ "nginx.service" "postgresql.service" ];
      environment = {
        APPROOT = "https://pascal-wittmann.de";
        PORT = "3001";
        PGUSER = "homepage";
        PGDATABASE = "homepage_production";
      };
      script = ''
        export PGPASS=`cat /var/keys/databaseHomepage`
        cd /srv/homepage
        ${homepage-app}/bin/homepage
      '';
      serviceConfig.KillSignal = "SIGINT";
      serviceConfig.User = "homepage";
    };
  };
}
