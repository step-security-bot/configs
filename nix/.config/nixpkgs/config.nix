let
  unstable = import (fetchTarball https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz) { };
  stable = import (fetchTarball https://nixos.org/channels/nixos-23.05/nixexprs.tar.xz) { };
in
{

  allowUnfree = true;

  permittedInsecurePackages = [
    "python2.7-pyjwt-1.7.1"
  ];

  packageOverrides = _: with stable.pkgs; rec {

    myTexLive = texlive.combine {
      inherit (texlive) scheme-full;
    };

    all-env = [
      base-env
      tools-env
      nix-tools-env
      archivers-env
      emacs-env
      apps-env
      spelling-env
      development-env
      security-env
      work-env
    ];

    base-env = buildEnv {
      name = "base-env";
      paths = [
        acpi
        bgs
        bmon
        dmenu
        dunst
        fsql
        i3lock
        inotify-tools
        htop
        libnotify
        networkmanagerapplet
        networkmanager-openconnect
        alacritty
        stow
        trayer
        haskellPackages.xmobar
        xclip
        xbindkeys
        xdotool
        xorg.xinput
        xorg.xmodmap
        zile
      ];
    };

    tools-env = buildEnv {
      name = "tools-env";
      paths = [
        appimage-run
        bind
        binutils
        file
        #ghostscript
        libxml2
        nox
        imagemagick
        parallel
        psmisc
        pinpoint
        inetutils
        tree
        xfce.tumbler
        xfce.ristretto
        which
        wget
        zsh-navigation-tools
      ];
    };

    nix-tools-env = buildEnv {
      name = "nix-tools-env";
      paths = [
        cabal2nix
        dysnomia
        nix-generate-from-cpan
        nix-review
        nixops_unstable
        nixpkgs-lint
      ];
    };

    archivers-env = buildEnv {
      name = "archivers-env";
      paths = [
        atool
        zip
        unzip
        p7zip
      ];
    };

    emacs-env = buildEnv {
      name = "emacs-env";
      paths = [
        emacs
        emacs.pkgs.use-package
        emacs.pkgs.haskell-mode
        emacs.pkgs.scala-mode
#        emacs.pkgs.shm
        emacs.pkgs.writegood-mode
        emacs.pkgs.magit
        emacs.pkgs.nix-mode
        emacs.pkgs.markdown-mode
      ];
    };

    apps-env = buildEnv {
      name = "apps-env";
      paths = [
        unstable.pkgs.brave
        calibre
        clementine
        evince
        exercism
        feh
        filezilla
        firefox
        homebank
        krusader
        keepassxc
        thunderbird
        #llpp
        libreoffice-fresh
        unstable.nextcloud-client
        obsidian
        pass
        unstable.slack
        geeqie
        pcmanfm
        phototonic
        simple-scan
        electrum
        viking
        vlc
        zim
      ];
    };

    spelling-env = buildEnv {
      name = "spelling-env";
      paths = [
        aspell
        aspellDicts.de
        aspellDicts.en
      ];
    };

    development-env = buildEnv {
      name = "development-env";
      paths = [
        gitFull
        #idea.idea-ultimate
        subversion
      ];
    };

    security-env = buildEnv {
      name = "security-env";
      paths = [
        apg
        gnupg
        gnupg1compat
        pinentry
      ];
    };

    work-env = buildEnv {
      name = "work-env";
      paths = [
        #citrix_workspace
        docker
        maven
      ];
    };

  };
}
