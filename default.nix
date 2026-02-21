{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "make-multiboot-usb";
  version = "1.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  
  installPhase = ''
    mkdir -p $out/bin
    cp makeUSB.sh $out/bin/makeUSB.sh
    cp -r mbusb.* grub.cfg.example $out/bin
    chmod +x $out/bin/makeUSB.sh

    wrapProgram $out/bin/makeUSB.sh \
      --prefix PATH : ${pkgs.lib.makeBinPath [
        pkgs.gptfdisk   # sgdisk
        pkgs.dosfstools # mkfs.vfat
        pkgs.ntfs3g     # mkfs.ntfs
        pkgs.util-linux # wipefs, blkid
        pkgs.curl
        pkgs.gnutar
        pkgs.unzip
        pkgs.coreutils
      ]} \
      --set GRUB_EFI ${pkgs.grub2_efi}/bin/grub-install
  '';
}

