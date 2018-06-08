let
  overlay = self: super: {
    ntp = super.ntp.overrideAttrs (drv: {
      patches = drv.patches or [] ++ [ ./openat.patch ];
    });
  };
in {
  nixpkgs.overlays = [ overlay ];
}
