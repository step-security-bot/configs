{ config, pkgs, options, lib, ... }:

  # TODO: https://github.com/nix-community/impermanence/

let
  issueFile = pkgs.writeText "issue" ''
    Attention, by continuing to connect to this system, you consent to the owner storing a log of all activity.
    Unauthorized access is prohibited.
  '';
in  {
      require = [
        ./modules/hardware.nix
        ./modules/baralga.nix
        ./modules/homepage.nix
        ./modules/radicale.nix
        ./modules/systemd-email-notify.nix
        ./users.nix
      ];

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "23.11";

      sops.defaultSopsFile = ./secrets.yaml;
      sops.defaultSopsFormat = "yaml";
      sops.age.keyFile = "/nix/secret/sops/age/keys.txt";

      sops.secrets = {
        "basicauth/passwords" = { owner = "nginx"; };
        "cifs/pictures" = {};
        "netdata/telegram" = { owner = "netdata"; };
        "nextcloud/admin" = { owner = "nextcloud"; };
        "nextcloud/db" = { owner = "nextcloud"; };
        "homepage/db" = { owner = "homepage"; };
        "invidious/db" = {};
        "paperless/admin" = { owner = "paperless"; };
        "radicale" = { owner = "radicale"; };
        "restic/data" = {};
        "vaultwarden/env" = { owner = "vaultwarden"; };
        "mtls/actual/crt" = { owner = "nginx"; };
        "mtls/adguard/crt" = { owner = "nginx"; };
        "mtls/invidious/crt" = { owner = "nginx"; };
        "mtls/netdata/crt" = { owner = "nginx"; };
        "mtls/paperless/crt" = { owner = "nginx"; };
        "smtp" = { group = "mail"; };
        "geoip/key" = { };
      };

      # Use the systemd-boot EFI boot loader.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # We need networking in the initrd
      boot.initrd.network = {
        enable = true;
        ssh = {
          enable = true;
          port = 10801;
          authorizedKeys = config.users.users.deployer.openssh.authorizedKeys.keys;
          hostKeys = [ "/nix/secret/initrd/ssh_host_ed25519_key" ];
        };
      };

      # IP:<ignore>:GATEWAY:NETMASK:HOSTNAME:NIC:AUTCONF?
      # See: https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
      boot.kernelParams = [ "ip=152.53.0.129::152.53.0.1:152.53.3.255:v22024034028258810.nicesrv.de:enp3s0:off" ];
      networking = {
        useDHCP = false;
        interfaces."enp3s0" = {
          ipv4.addresses = [{ address = "152.53.0.129"; prefixLength = 22; }];
          ipv6.addresses = [{ address = "2a0a:4cc0:0:10a5::1"; prefixLength = 64; }];
        };
        defaultGateway = "152.53.0.1";
        defaultGateway6 = { address = "fe80::1"; interface = "enp3s0"; };
      };

      environment.etc."ssh/ssh_host_rsa_key" = {
        source = "/nix/persist/etc/ssh/ssh_host_rsa_key";
        mode = "0400";
      };
      environment.etc."ssh/ssh_host_rsa_key.pub" = {
        source = "/nix/persist/etc/ssh/ssh_host_rsa_key.pub";
        mode = "0400";
      };
      environment.etc."ssh/ssh_host_ed25519_key" = {
        source = "/nix/persist/etc/ssh/ssh_host_ed25519_key";
        mode = "0400";
      };
      environment.etc."ssh/ssh_host_ed25519_key.pub" = {
        source = "/nix/persist/etc/ssh/ssh_host_ed25519_key.pub";
        mode = "0400";
      };
      environment.etc."machine-id".source = "/nix/persist/etc/machine-id";

      environment.etc."ssh/ssh_backup_ed25519" = {
        source = "/nix/persist/etc/ssh/ssh_backup_ed25519";
        mode = "0400";
      };

      environment.etc."ssh/ssh_backup_ed25519.pub" = {
        source = "/nix/persist/etc/ssh/ssh_backup_ed25519.pub";
        mode = "0400";
      };

      environment.etc."issue" = {
        source = issueFile;
        mode = "0444";
      };

      environment.etc."issue.net" = {
        source = issueFile;
        mode = "0444";
      };

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
        "net.ipv6.conf.ens3.accept_ra_defrtr" = mkDefault false;

        "net.ipv4.conf.all.log_martians" = mkDefault true;
        "net.ipv4.conf.default.log_martians" = mkDefault true;
        "net.ipv6.conf.all.accept_redirects" = mkDefault false;
        "net.ipv6.conf.default.accept_redirects" = mkDefault false;
        "net.ipv4.conf.default.accept_redirects" = mkDefault false;
        "net.ipv4.conf.all.secure_redirects" = mkDefault false;
        "net.ipv4.conf.all.rp_filter" = mkDefault "1";

        # Somehow this option does not apply…
#        "net.ipv4.conf.all.forwarding" = mkDefault "0";

        "net.ipv4.conf.all.send_redirects" = mkDefault "0";
        "net.core.bpf_jit_harden" = mkDefault "2";
        "kernel.yama.ptrace_scope" = mkOverride 500 1;
        "kernel.unprivileged_bpf_disabled" = mkDefault "1";
        "kernel.sysrq" = mkDefault "0";
        "kernel.perf_event_paranoid" = mkDefault "3";
        # This breaks the boot somehow
 #       "kernel.modules_disabled" = mkDefault "1";
        "kernel.kptr_restrict" = mkOverride 500 "2";
        "kernel.dmesg_restrict" = mkDefault "1";
        "fs.suid_dumpable" = mkDefault "0";
        "fs.protected_regular" = mkDefault "2";
        "fs.protected_fifos" = mkDefault "2";
        "dev.tty.ldisc_autoload" = mkDefault "0";
      };

      nix.settings.allowed-users = [ ];
      nix.settings.max-jobs = 2;
      nix.optimise.automatic = true;
      nix.gc.automatic = true;
      nix.gc.dates = "06:00";

      # Deploy without root
      nix.settings.trusted-users = [ "root" "deployer" ];
      security.sudo.enable = true;

      # TODO: Separate keys for root and deployer
      users.users.root.openssh.authorizedKeys.keys = config.users.users.deployer.openssh.authorizedKeys.keys;

      security.sudo.execWheelOnly = true;
      security.loginDefs.settings = {
        # Used values from https://github.com/dev-sec/ansible-collection-hardening/issues/365
        SHA_CRYPT_MIN_ROUNDS = 640000;
        SHA_CRYPT_MAX_ROUNDS = 640000;
      };

      security.auditd.enable = true;
      security.audit.enable = true;
      security.audit.rules = [
        "-a exit,always -F arch=b64 -S execve"
      ];
      environment.etc."audit/auditd.conf".text = ''
        space_left = 10%
        space_left_action = ignore
        admin_space_left = 5%
        admin_space_left_action = email
        action_mail_acct = admin@frey.family
        num_logs = 10
        max_log_file = 100
        max_log_file_action = rotate
      '';

      services.restic.backups.server-data = {
        repository = "sftp://u388595.your-storagebox.de:23/server";
        paths = [ "/nix/persist" ];
        exclude = [ "/srv/pictures" ];
        passwordFile = "/run/secrets/restic/data";
        extraOptions = [
            "sftp.command='ssh u388595-sub3@u388595.your-storagebox.de -p 23 -i /nix/persist/etc/ssh/ssh_backup_ed25519 -s sftp'"
        ];
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

      networking.hostName = "nixos"; # Define your hostname.
      networking.domain = "pascal-wittmann.de";
      networking.nameservers = [
        "9.9.9.9"
        "149.112.112.112"
      ];

      networking.firewall.enable = true;
      networking.firewall.allowPing = true;
      networking.firewall.pingLimit = "--limit 1/second --limit-burst 5";
      networking.firewall.autoLoadConntrackHelpers = false;
      networking.firewall.allowedTCPPorts = [
        80 # http
        443 # https
        853 # adguard
        10801 # ssh
      ];
      networking.firewall.allowedUDPPorts = [
        853 # adguard
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
      security.pam.enableSSHAgentAuth = true;
      security.pam.services.sudo.sshAgentAuth = true;
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

        chkrootkit
        cifs-utils
        htop
        lynis
        zile

        # TOOD: Why do I have to install this globally for Nextcloud Memories to work?
        ffmpeg
      ];

      # What breaks with this option?
      environment.defaultPackages = lib.mkForce [];

      # List services that you want to enable:

      # AdGuard
      services.adguardhome.enable = true;
      services.adguardhome.settings = {
        auth_attempts = 3;
        block_auth_min = 10;
        http.address = "127.0.0.1:3000";

        dns = {
          protection_enabled = true;
          parental_enabled = false;
          bind_hosts = [ "0.0.0.0" ];
        };

        statistics = {
          enabled = true;
          interval = "8760h";
        };
        dhcp.enabled = false;
        tls = {
          enabled = true;
          server_name = "adguard.pascal-wittmann.de";
          port_https = 0;
          port_dns_over_tls = 853;
          certificate_path = "/run/credentials/adguardhome.service/fullchain.pem";
          private_key_path = "/run/credentials/adguardhome.service/key.pem";
        };
      };
      
      systemd.services.adguardhome.serviceConfig = {
        LoadCredential = [
          "fullchain.pem:/var/lib/acme/adguard.pascal-wittmann.de/fullchain.pem"
          "key.pem:/var/lib/acme/adguard.pascal-wittmann.de/key.pem"
        ];
      };

      # Atuin Sync Server
      services.atuin.enable = true;

      # Mail
      programs.msmtp = {
        enable = true;
        accounts.default = {
          auth = true;
          tls = true;
          host = "frey-family.netcup-mail.de";
          from = "admin@frey.family";
          user = "admin@frey.family";
          passwordeval = "cat /run/secrets/smtp";
        };
      };

      # Cron daemon.
      services.cron.enable = true;
      services.cron.systemCronJobs = [ ];

      # Logrotate
      services.logrotate.enable = true;
      # See https://discourse.nixos.org/t/logrotate-config-fails-due-to-missing-group-30000/28501
      services.logrotate.checkConfig = false;
      services.logrotate.settings = {
        "postgresql" = {
            files = [
	      "/var/backup/postgresql/atuin.sql.gz"
              "/var/backup/postgresql/homepage_production.sql.gz"
              "/var/backup/postgresql/nextcloud.sql.gz"
              "/var/backup/postgresql/invidious.sql.gz"
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
      services.openssh.ports = [ 10801 ];
      services.openssh.allowSFTP = true;
      services.openssh.hostKeys = [
        {
          path = "/nix/secret/initrd/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
      services.openssh.knownHosts.storageBox = {
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
        hostNames = [ "u388595.your-storagebox.de" ];
      };
      services.openssh.settings =  {
        X11Forwarding = false;
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        MaxSessions = 2;
        MaxAuthTries = 3;
        ClientAliveCountMax = 2;
        AllowTcpForwarding = "no";
        AllowAgentForwarding = "yes";
        AllowStreamLocalForwarding = "no";
        AuthenticationMethods = "publickey";
        TCPKeepAlive = "no";
      };

      # PostgreSQL.
      services.postgresql.enable = true;
      services.postgresql.package = pkgs.postgresql_15;
      services.postgresql.dataDir = "/var/lib/postgresql/15";
      services.postgresqlBackup.databases = [ "atuin" "homepage_production" "nextcloud" "invidious" ];
      services.postgresqlBackup.enable = true;
      services.postgresqlBackup.location = "/var/backup/postgresql";
      services.postgresqlBackup.startAt = "*-*-* 02:15:00";

      # invidious
      services.invidious.enable = true;
      services.invidious.port = 3042;
      services.invidious.domain = "invidious.pascal-wittmann.de";
      services.invidious.nginx.enable = true;
      services.invidious.database.passwordFile = "/run/credentials/invidious.service/invidiousDb";
      systemd.services.invidious.serviceConfig = {
        LoadCredential = [
          "invidiousDb:/run/secrets/invidious/db"
        ];
      };

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
          htpasswd_filename = "/run/secrets/radicale";
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
      services.nextcloud.config.adminpassFile = "/run/secrets/nextcloud/admin";
      services.nextcloud.hostName = "cloud.pascal-wittmann.de";
      services.nextcloud.https = true;
      services.nextcloud.autoUpdateApps.enable = true;
      services.nextcloud.config = {
        dbtype = "pgsql";
        dbport = 5432;
        dbname = "nextcloud";
        dbuser = "nextcloud";
        dbpassFile = "/run/secrets/nextcloud/db";
        dbhost = "127.0.0.1";
        dbtableprefix = "oc_";

        defaultPhoneRegion = "DE";
      };
      services.nextcloud.extraOptions = {
        "memories.exiftool" = "${lib.getExe pkgs.exiftool}";
        "memories.vod.ffmpeg" = "${pkgs.ffmpeg-headless}/bin/ffmpeg";
        "memories.vod.ffprobe" = "${pkgs.ffmpeg-headless}/bin/ffprobe";
      };
      services.nextcloud.phpOptions = {
        "opcache.enable" = "1";
        "opcache.enable_cli" = "1";
        "opcache.jit" = "1255";
        "opcache.jit_buffer_size" = "256M";
        "opcache.interned_strings_buffer" = "16";
        "opcache.validate_timestamps" = "0";
        "opcache.save_comments" = "1";

        "pm" = "dynamic";
        "pm.max_children" = "50";
        "pm.start_servers" = "15";
        "pm.min_spare_servers" = "15";
        "pm.max_spare_servers" = "25";
        "pm.max_requests" = "500";
      };
      services.nextcloud.phpExtraExtensions = all: [ all.redis ];

      services.redis.servers.nextcloud = {
        enable = true;
        user = "nextcloud";
        unixSocket = "/var/run/redis-nextcloud/redis.sock";
      };

      systemd.services.nextcloud-setup.serviceConfig.ExecStartPost = pkgs.writeScript "nextcloud-redis.sh" ''
          #!${pkgs.runtimeShell}
          nextcloud-occ config:system:set filelocking.enabled --value true --type bool
          nextcloud-occ config:system:set redis 'host' --value '/var/run/redis-nextcloud/redis.sock' --type string
          nextcloud-occ config:system:set redis 'port' --value 0 --type integer
          nextcloud-occ config:system:set memcache.local --value '\OC\Memcache\Redis' --type string
          nextcloud-occ config:system:set memcache.locking --value '\OC\Memcache\Redis' --type string
      '';

      # paperless
      services.paperless.enable = true;
      services.paperless.dataDir = "/srv/paperless";
      services.paperless.passwordFile = "/run/secrets/paperless/admin";
      services.paperless.extraConfig = {
        PAPERLESS_URL = "https://paperless.pascal-wittmann.de";
        PAPERLESS_OCR_LANGUAGE = "deu+eng";
        PAPERLESS_OCR_USER_ARGS=''{"invalidate_digital_signatures": true}'';
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
      services.vaultwarden.environmentFile = "/run/secrets/vaultwarden/env";
      systemd.services.vaultwarden.wants = [ "nginx.service" ];
      systemd.services.vaultwarden.after = [ "nginx.service" ];
      systemd.services.vaultwarden.bindsTo = [ "nginx.service" ];

      # geoip update
      services.geoipupdate.enable = true;
      services.geoipupdate.settings = {
        EditionIDs = [
          "GeoLite2-ASN"
          "GeoLite2-City"
          "GeoLite2-Country"
        ];
        AccountID = 995265;
        LicenseKey = {
          _secret = "/run/secrets/geoip/key";
        };
      };

      # nginx
      services.nginx.enable = true;
      services.nginx.recommendedGzipSettings = true;
      services.nginx.recommendedOptimisation = true;
      services.nginx.recommendedTlsSettings = true;
      services.nginx.additionalModules = with pkgs.nginxModules; [
        geoip2
      ];

      services.nginx.commonHttpConfig = ''
       geoip2 /var/lib/GeoIP/GeoLite2-Country.mmdb {
          $geoip2_data_country_iso_code country iso_code;
        }

        map $geoip2_data_country_iso_code $allowed_country {
          default 0;
          DE 1;
          AT 1;
        }

        geo $allowed_ip {
          default 0;
          # TODO: Create this file automatically
          include /var/db/IPv4andIPv6.txt;
        }


        map "$allowed_country$allowed_ip" $is_allowed {
          default 0;
          11 1;
          10 1;
          01 1;
        }

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
          locations."/" = {
            proxyPass = "http://127.0.0.1:8222";
            proxyWebsockets = true;
            extraConfig = ''
              if ($is_allowed = 0) {
                return 403;
              }
            '';
          };
          extraConfig = ''
            proxy_read_timeout 90;

            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
            add_header X-Content-Type-Options nosniff;
            add_header X-XSS-Protection "1; mode=block";
            add_header X-Frame-Options SAMEORIGIN;
          '';
        };

        "netdata.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:19999";
            extraConfig = ''
              if ($is_allowed = 0) {
                return 403;
              }
            '';
          };
          extraConfig = ''
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_http_version 1.1;
            proxy_pass_request_headers on;
            proxy_set_header Connection "keep-alive";
            proxy_store off;

            ssl_verify_client on;
            ssl_client_certificate /run/secrets/mtls/netdata/crt;

            auth_basic "Password protected area";
            auth_basic_user_file /run/secrets/basicauth/passwords;
          '';
        };

        "adguard.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3000";
            extraConfig = ''
              if ($is_allowed = 0) {
                return 403;
              }
            '';
          };
          extraConfig = ''
            ssl_verify_client on;
            ssl_client_certificate /run/secrets/mtls/adguard/crt;
          '';
        };

        "invidious.pascal-wittmann.de" = {
          extraConfig = ''
            ssl_verify_client on;
            ssl_client_certificate /run/secrets/mtls/invidious/crt;
          '';
        };
	
        "atuin.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = { proxyPass = "http://127.0.0.1:8888"; };
        };

        "actual.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:5006";
            extraConfig = ''
              if ($is_allowed = 0) {
                return 403;
              }
            '';
          };
          extraConfig = ''
            ssl_verify_client on;
            ssl_client_certificate /run/secrets/mtls/actual/crt;
          '';
        };

        "paperless.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          extraConfig = ''
            ssl_verify_client on;
            ssl_client_certificate /run/secrets/mtls/paperless/crt;
            client_max_body_size 0;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:28981";
            extraConfig = ''
              if ($is_allowed = 0) {
                return 403;
              }
            '';
          };
        };

        "wakapi.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3043";

          };
        };

        "wanderer.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3045";
            extraConfig = ''
              if ($is_allowed = 0) {
                return 403;
              }
            '';
          };
        };

        "immich.pascal-wittmann.de" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:2283";
            extraConfig = ''
              if ($is_allowed = 0) {
                return 403;
              }

              # allow large file uploads
              client_max_body_size 50000M;

              # Set headers
              proxy_set_header Host              $host;
              proxy_set_header X-Real-IP         $remote_addr;
              proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;

              # enable websockets
              proxy_http_version 1.1;
              proxy_set_header   Upgrade    $http_upgrade;
              proxy_set_header   Connection "upgrade";
              proxy_redirect     off;

              # set timeout
              proxy_read_timeout 600s;
              proxy_send_timeout 600s;
              send_timeout       600s;
            '';
          };
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
              auth_basic_user_file /run/secrets/basicauth/passwords;
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

      # Baralga
      services.baralga.enable = false;

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
       "health_alarm_notify.conf" = "/run/secrets/netdata/telegram";
      };

      # Sound
      sound.enable = false;

      # Enable zsh
      programs.zsh.enable = true;

      # X-libraries and fonts are not needed on the server.
      #environment.noXlibs = true;
      fonts.fontconfig.enable = false;

      users.mutableUsers = false;
      users.defaultUserShell = "${pkgs.zsh}/bin/zsh";

      virtualisation.docker.enable = true;
    }
