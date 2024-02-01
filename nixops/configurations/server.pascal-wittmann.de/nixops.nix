{

  network = {
    enableRollback = true;
    storage.legacy = { };
  };

  server = { config, pkgs, options, lib, ... }:

    {
      require = [
        ./modules/clean-deployment-keys.nixops.nix
        ./modules/homepage.nix
        ./modules/radicale.nix
        ./modules/systemd-email-notify.nix
        ./users.nix
      ];

      nixpkgs.config.allowUnfree = true;

      deployment.targetHost = "server.pascal-wittmann.de";

      # Use the GRUB 2 boot loader.
      boot.loader.grub.enable = true;
      # Define on which hard drive you want to install Grub.
      boot.loader.grub.device = "/dev/vda";
      boot.loader.grub.users.admin.hashedPasswordFile = "/var/keys/grubAdminPassword";

      boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_hardened;
      boot.initrd.availableKernelModules = [
        "ata_piix"
        "uhci_hcd"
        "virtio_pci"
        "virtio_blk"
      ];
      boot.kernelModules = [ ];
      boot.extraModulePackages = [ ];

      boot.blacklistedKernelModules = [
        # Obscure network protocols
        "ax25"
        "netrom"
        "rose"

        # Old or rare or insufficiently audited filesystems
        "adfs"
        "affs"
        "bfs"
        "befs"
        "cramfs"
        "efs"
        "erofs"
        "exofs"
        "freevxfs"
        "f2fs"
        "hfs"
        "hpfs"
        "jfs"
        "minix"
        "nilfs2"
        "ntfs"
        "omfs"
        "qnx4"
        "qnx6"
        "sysv"
        "ufs"

        "tipc"
        "sctp"
        "dccp"
        "rds"

        "usb-storage"
      ];

      boot.extraModprobeConfig = ''
        install tipc /bin/true
        install sctp /bin/true
        install dccp /bin/true
        install rds  /bin/true

        install usb-storage /bin/true
      '';

      boot.kernel.sysctl = with lib; {
        "net.ipv4.conf.all.log_martians" = mkDefault true;
        "net.ipv4.conf.default.log_martians" = mkDefault true;
        "net.ipv6.conf.all.accept_redirects" = mkDefault false;
        "net.ipv6.conf.default.accept_redirects" = mkDefault false;
        "net.ipv4.conf.default.accept_redirects" = mkDefault false;
        "net.ipv4.conf.all.secure_redirects" = mkDefault false;
        "net.ipv4.conf.all.rp_filter" = mkDefault "1";

        # Somehow this option does not apply…
        "net.ipv4.conf.all.forwarding" = mkDefault "0";

        "net.ipv4.conf.all.send_redirects" = mkDefault "0";
        "net.core.bpf_jit_harden" = mkDefault "2";
        "kernel.yama.ptrace_scope" = mkOverride 500 1;
        "kernel.unprivileged_bpf_disabled" = mkDefault "1";
        "kernel.sysrq" = mkDefault "0";
        "kernel.perf_event_paranoid" = mkDefault "3";
        "kernel.modules_disabled" = mkDefault "1";
        "kernel.kptr_restrict" = mkOverride 500 "2";
        "kernel.dmesg_restrict" = mkDefault "1";
        "fs.suid_dumpable" = mkDefault "0";
        "fs.protected_regular" = mkDefault "2";
        "fs.protected_fifos" = mkDefault "2";
        "dev.tty.ldisc_autoload" = mkDefault "0";
      };

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/7d067332-eba7-4a8e-acf7-a463cf50677f";
        fsType = "ext4";
      };

      swapDevices = [
        { device = "/dev/disk/by-uuid/279e433e-1ab9-4fd1-9c37-0d7e4e082944"; }
      ];

      nix.settings.allowed-users = [ ];
      nix.settings.max-jobs = 2;
      nix.gc.automatic = true;
      nix.gc.dates = "06:00";

      # Deploy without root
      nix.settings.trusted-users = [ "root" "deployer" ];
      security.sudo.wheelNeedsPassword = false;
      deployment.targetUser = "deployer";

      security.sudo.execWheelOnly = true;
      security.loginDefs.settings = {
        # Used values from https://github.com/dev-sec/ansible-collection-hardening/issues/365
        SHA_CRYPT_MIN_ROUNDS = 640000;
        SHA_CRYPT_MAX_ROUNDS = 640000;
      };


      services.restic.backups.server-data = {
        repository = "sftp://u388595.your-storagebox.de:23/nixos";
        paths = [ "/home" "/var" "/srv" "/root" ];
        passwordFile = "/var/keys/resticServerData";
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 3"
          "--keep-yearly 1"
        ];
        initialize = true;
      };

      systemd.email-notify.mailTo = "mail@pascal-wittmann.de";
      systemd.email-notify.mailFrom = "systemd <admin@frey.family>";

      services.journald.extraConfig = ''
          SystemMaxUse=1G
      '';

      system.autoUpgrade.enable = true;
      system.autoUpgrade.channel = https://nixos.org/channels/nixos-23.11;
      system.autoUpgrade.dates = "04:00";
      system.autoUpgrade.allowReboot = true;
      systemd.services.nixos-upgrade.environment.NIXOS_CONFIG = pkgs.writeText "configuration.nix" ''
        all@{ config, pkgs, lib, ... }:
              with lib; with builtins;
              let
                modifyPaths = f : paths : map toPath (map f (map toString paths));

                serverConfig = (import /etc/nixos/current/nixops.nix).server all;
                withoutDeploymentOptions = removeAttrs serverConfig [ "deployment" ];
                withoutDeploymentRequires = overrideExisting withoutDeploymentOptions
                                             { require = modifyPaths (require: concatStrings [ "/etc/nixos/current/" (replaceStrings [ "nix/store/"] [ "" ] require) ])
                                                                             (filter (filename: ! (hasInfix ".nixops" (toString filename)))
                                                                                              serverConfig.require);

                                               system = serverConfig.system // {
                                                 activationScripts = removeAttrs serverConfig.system.activationScripts [ "copy-configuration" ];
                                               };
                                             };
              in withoutDeploymentRequires
      '';

      system.activationScripts = {
        copy-configuration = ''
          if [ -d /etc/nixos/current ]; then
             rm -r /etc/nixos/current
          fi
          mkdir /etc/nixos/current

          ln -s ${./nixops.nix} /etc/nixos/current/nixops.nix
          ln -s ${./users.nix} /etc/nixos/current/users.nix
          ln -s ${./modules} /etc/nixos/current/modules
        '';
      };

      # Work around NixOS/nixpkgs#28527
      systemd.services.nixos-upgrade.path = with pkgs; [ gnutar xz.bin gzip config.nix.package.out ];

      networking.hostName = "nixos"; # Define your hostname.

      networking.interfaces.ens3.ipv6.addresses = [
        { address = "2a03:4000:2:70e::42"; prefixLength = 64; }
      ];
      networking.defaultGateway6 = { address = "fe80::1"; interface = "ens3"; };

      networking.firewall.enable = true;
      networking.firewall.allowPing = true;
      networking.firewall.pingLimit = "--limit 1/second --limit-burst 5";
      networking.firewall.autoLoadConntrackHelpers = false;
      networking.firewall.allowedTCPPorts = [
        80 # http
        443 # https
      ];

      # Select internationalisation properties.
      i18n.defaultLocale = "en_US.UTF-8";

      console = {
        font = "Lat2-Terminus16";
        keyMap = "de";
      };

      # Set your time zone.
      time.timeZone = "Europe/Berlin";

      # Security - PAM
      security.pam.loginLimits = [
        {
          domain = "*";
          item = "maxlogins";
          type = "-";
          value = "3";
        }
      ];

      security.acme.defaults.email = "contact@pascal-wittmann.de";
      security.acme.acceptTerms = true;


      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = with pkgs; [
        # Install only the alacritty terminfo file
        alacritty.terminfo
        zile

        # Needed for NixOps
        rsync
      ];

      # What breaks with this option?
      environment.defaultPackages = lib.mkForce [];

      # List services that you want to enable:

      # Atuin Sync Server
      services.atuin.enable = true;

      programs.msmtp = {
        enable = true;
        accounts.default = {
          auth = true;
          tls = true;
          host = "frey-family.netcup-mail.de";
          from = "admin@frey.family";
          user = "admin@frey.family";
          passwordeval = "cat /var/keys/smtp";
        };
      };

      # Cron daemon.
      services.cron.enable = true;
      services.cron.systemCronJobs = [ ];

      # Logrotate
      services.logrotate.enable = true;
      services.logrotate.settings = {
        "postgresql" = {
            files = [
              "/var/backup/postgresql/homepage_production.sql.gz"
              "/var/backup/postgresql/nextcloud.sql.gz"
            ];
            frequency = "daily";
            rotate = 30;
        };
      };

      # fail2ban
      services.fail2ban.enable = true;
      services.fail2ban.bantime-increment.enable = true;
      services.fail2ban.jails = {
        sshd.settings = {
          enabled = true;
        };

        nginx-http-auth = ''
          enabled  = true
          port     = http,https
          logpath  = /var/log/nginx/*.log
          backend  = polling
          journalmatch =
        '';

        nginx-bad-request = ''
          enabled  = true
          port     = http,https
          logpath  = /var/log/nginx/*.log
          backend  = polling
          journalmatch =
        '';

        nginx-botsearch = ''
          enabled  = true
          port     = http,https
          logpath  = /var/log/nginx/*.log
          backend  = polling
          journalmatch =
        '';

        vaultwarden = ''
          enabled  = true
        '';

        radicale = ''
          enabled = true
        '';
      };

      environment.etc = {
        "fail2ban/filter.d/vaultwarden.conf".text = ''
             [Definition]
             failregex = ^.*Username or password is incorrect\. Try again\. IP: <ADDR>\. Username: <F-USER>.*</F-USER>\.$

             ignoreregex =
             journalmatch = _SYSTEMD_UNIT=vaultwarden.service + _COMM=vaultwarden
        '';

        "fail2ban/filter.d/radicale.conf".text = ''
             [Definition]
             failregex = ^.*Failed login attempt from .+ \(forwarded for '<ADDR>'\): '<F-USER>.+</F-USER>$
             ignoreregex =

             journalmatch = _SYSTEMD_UNIT=radicale.service + _COMM=radicale
        '';
      };

      # Enable the OpenSSH daemon
      services.openssh.enable = true;
      services.openssh.allowSFTP = true;
      services.openssh.settings =  {
        X11Forwarding = false;
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        MaxSessions = 2;
        MaxAuthTries = 3;
        ClientAliveCountMax = 2;
        AllowTcpForwarding = "no";
        AllowAgentForwarding = "no";
        AllowStreamLocalForwarding = "no";
        AuthenticationMethods = "publickey";
        TCPKeepAlive = "no";
      };

      # PostgreSQL.
      services.postgresql.enable = true;
      services.postgresql.package = pkgs.postgresql_15;
      services.postgresql.dataDir = "/var/lib/postgresql/15";
      services.postgresqlBackup.databases = [ "homepage_production" "nextcloud" ];
      services.postgresqlBackup.enable = true;
      services.postgresqlBackup.location = "/var/backup/postgresql";
      services.postgresqlBackup.startAt = "*-*-* 02:15:00";

      # MySQL
      services.mysql.enable = true;
      services.mysql.package = pkgs.mysql;

      # Caldav / Cardav
      services.radicale.enable = true;
      services.radicale.settings = {
        server = {
          hosts = [ "127.0.0.1:5232" ];
          ssl = false;
        };

        storage = {
          filesystem_folder = "/srv/radicale/collections";
          hook = ''${pkgs.git}/bin/git add -A && (${pkgs.git}/bin/git diff --cached --quiet || ${pkgs.git}/bin/git commit -m "Changes by "%(user)s && GIT_SSH_COMMAND='${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=no -i /srv/radicale/id_ed25519' ${pkgs.git}/bin/git push origin)'';
        };

        auth = {
          type = "htpasswd";
          htpasswd_filename = "/var/keys/radicale";
          # encryption method used in the htpasswd file
          htpasswd_encryption = "bcrypt";
        };
      };
      services.radicale.package = pkgs.radicale3;
      services.radicale.nginx.enable = true;
      services.radicale.nginx.hostname = "calendar.pascal-wittmann.de";

      # nextcloud
      services.nextcloud.enable = true;
      services.nextcloud.package = pkgs.nextcloud27;
      services.nextcloud.home = "/srv/nextcloud";
      services.nextcloud.config.adminpassFile = "/var/keys/nextcloud";
      services.nextcloud.hostName = "cloud.pascal-wittmann.de";
      services.nextcloud.https = true;
      services.nextcloud.autoUpdateApps.enable = true;
      services.nextcloud.config = {
        dbtype = "pgsql";
        dbport = 5432;
        dbname = "nextcloud";
        dbuser = "nextcloud";
        dbpassFile = "/var/keys/databaseNextcloud";
        dbhost = "127.0.0.1";

        defaultPhoneRegion = "DE";
      };
      services.nextcloud.phpOptions = {
        "opcache.jit" = "tracing";
        "opcache.jit_buffer_size" = "100M";
        "opcache.interned_strings_buffer" = "16";
      };

      # paperless
      services.paperless.enable = true;
      services.paperless.dataDir = "/srv/paperless";
      services.paperless.passwordFile = "/var/keys/paperless";
      services.paperless.extraConfig = {
        PAPERLESS_URL = "https://paperless.pascal-wittmann.de";
      };

      # vaultwarden
      services.vaultwarden.enable = true;
      services.vaultwarden.package = pkgs.vaultwarden;
      services.vaultwarden.backupDir = "/var/backup/vaultwarden";
      services.vaultwarden.config = {
        domain = "https://vaultwarden.pascal-wittmann.de:443";
        rocketAddress = "127.0.0.1";
        rocketPort = 8222;
        signupsAllowed = false;
      };
      services.vaultwarden.environmentFile = "/var/keys/vaultwardenEnv";
      systemd.services.vaultwarden.wants = [ "nginx.service" ];
      systemd.services.vaultwarden.after = [ "nginx.service" ];
      systemd.services.vaultwarden.bindsTo = [ "nginx.service" ];

      # nginx
      services.nginx.enable = true;
      services.nginx.recommendedGzipSettings = true;
      services.nginx.recommendedOptimisation = true;
      services.nginx.recommendedTlsSettings = true;
      services.nginx.commonHttpConfig = ''
        map $remote_addr $ip_anonym1 {
        default 0.0.0;
        "~(?P<ip>(\d+)\.(\d+))\.(\d+)\.\d+" $ip;
        "~(?P<ip>[^:]+:[^:]+):" $ip;
        }

        map $remote_addr $ip_anonym2 {
        default .0.0;
        "~(?P<ip>(\d+)\.(\d+)\.(\d+))\.\d+" .0.0;
        "~(?P<ip>[^:]+:[^:]+):" ::;
        }

        map $ip_anonym1$ip_anonym2 $ip_anonymized {
        default 0.0.0.0;
        "~(?P<ip>.*)" $ip;
        }

        log_format anonymized '$ip_anonymized - $remote_user [$time_local] '
        '"$request" $status $body_bytes_sent '
        '"$http_referer" "$http_user_agent"';

        access_log /var/log/nginx/access.log anonymized;
      '';
      services.nginx.virtualHosts = {
        "penchy.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          root = "/srv/penchy";
        };

        "cloud.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
        };

        "calendar.pascal-wittmann.de" = {
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          '';
        };

        "vaultwarden.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = { proxyPass = "http://127.0.0.1:8222"; };
          extraConfig = ''
            proxy_read_timeout 90;

            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
            add_header X-Content-Type-Options nosniff;
            add_header X-XSS-Protection "1; mode=block";
            add_header X-Frame-Options SAMEORIGIN;
          '';
        };

        "netdata.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = { proxyPass = "http://127.0.0.1:19999"; };
          extraConfig = ''
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_http_version 1.1;
            proxy_pass_request_headers on;
            proxy_set_header Connection "keep-alive";
            proxy_store off;

            ssl_verify_client on;
            ssl_client_certificate /var/keys/netdataMtls;

            auth_basic "Password protected area";
            auth_basic_user_file /var/keys/basicAuth;
          '';
        };

        "atuin.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = { proxyPass = "http://127.0.0.1:8888"; };
        };

        "paperless.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          extraConfig = ''
            ssl_verify_client on;
            ssl_client_certificate /var/keys/paperlessMtls;
            client_max_body_size 0;
          '';
          locations."/" = { proxyPass = "http://127.0.0.1:28981"; };
        };

        "users.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;

          locations."/pascal" = {
            root = "/srv/users/";
            extraConfig = ''
              autoindex on;
            '';
          };

          locations."/lerke" = {
            root = "/srv/users/";
            extraConfig = ''
              autoindex on;
              auth_basic "Password protected area";
              auth_basic_user_file /var/keys/basicAuth;
            '';
          };

          extraConfig = ''
            add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
            add_header X-Content-Type-Options nosniff;
            add_header X-XSS-Protection "1; mode=block";
            add_header X-Frame-Options DENY;
          '';
        };
      };

      # Homepage
      services.homepage.enable = true;

      # Netdata
      services.netdata.enable = true;
      services.netdata.config = {
        global = {
          "debug log" = "syslog";
          "access log" = "syslog";
          "error log" = "syslog";
        };
      };

      services.netdata.configDir = {
       "health_alarm_notify.conf" = "/var/keys/netdataTelegramNotify";
      };

      # Sound
      sound.enable = false;

      # Enable zsh
      programs.zsh.enable = true;

      # X-libraries and fonts are not needed on the server.
      #  environment.noXlibs = true;
      fonts.fontconfig.enable = false;

      users.mutableUsers = false;
      users.defaultUserShell = "${pkgs.zsh}/bin/zsh";

      virtualisation.docker.enable = true;

      deployment.keys.nextcloud.text = builtins.readFile ./secrets/nextcloud;
      deployment.keys.nextcloud.destDir = "/var/keys";
      deployment.keys.nextcloud.user = "nextcloud";

      deployment.keys.databaseNextcloud.text = builtins.readFile ./secrets/database-nextcloud;
      deployment.keys.databaseNextcloud.destDir = "/var/keys";
      deployment.keys.databaseNextcloud.user = "nextcloud";

      deployment.keys.basicAuth.text = builtins.readFile ./secrets/passwords;
      deployment.keys.basicAuth.destDir = "/var/keys";
      deployment.keys.basicAuth.user = "nginx";

      deployment.keys.smtp.text = builtins.readFile ./secrets/smtp;
      deployment.keys.smtp.destDir = "/var/keys";
      deployment.keys.smtp.group = "mail";

      deployment.keys.databaseHomepage.text = builtins.readFile ./secrets/homepage_database_password;
      deployment.keys.databaseHomepage.destDir = "/var/keys";
      deployment.keys.databaseHomepage.user = "homepage";

      deployment.keys.radicale.text = builtins.readFile ./secrets/radicale;
      deployment.keys.radicale.destDir = "/var/keys";
      deployment.keys.radicale.user = "radicale";

      deployment.keys.vaultwardenEnv.text = builtins.readFile ./secrets/vaultwarden.env;
      deployment.keys.vaultwardenEnv.destDir = "/var/keys";
      deployment.keys.vaultwardenEnv.user = "vaultwarden";

      deployment.keys.paperless.text = builtins.readFile ./secrets/paperless;
      deployment.keys.paperless.destDir = "/var/keys";
      deployment.keys.paperless.user = "paperless";

      deployment.keys.paperlessMtls.text = builtins.readFile ./secrets/paperless-mtls/client.crt;
      deployment.keys.paperlessMtls.destDir = "/var/keys";
      deployment.keys.paperlessMtls.user = "nginx";

      deployment.keys.netdataMtls.text = builtins.readFile ./secrets/netdata-mtls/client.crt;
      deployment.keys.netdataMtls.destDir = "/var/keys";
      deployment.keys.netdataMtls.user = "nginx";

      deployment.keys.netdataTelegramNotify.text = builtins.readFile ./secrets/netdata-telegram-notify;
      deployment.keys.netdataTelegramNotify.destDir = "/var/keys";
      deployment.keys.netdataTelegramNotify.user = "netdata";

      deployment.keys.resticServerData.text = builtins.readFile ./secrets/restic-server-data;
      deployment.keys.resticServerData.destDir = "/var/keys";
      deployment.keys.resticServerData.user = "root";

      deployment.keys.grubAdminPassword.text = builtins.readFile ./secrets/grub-admin-password;
      deployment.keys.grubAdminPassword.destDir = "/var/keys";
      deployment.keys.grubAdminPassword.user = "root";
    };
}
