# This fork

This is an Extended Support Repository, I wil not work on this actively but PRs are welcome and I will check them and merge them. There is also no guarantee that I will fix issues.

# Multiboot USB

<https://mbusb.aguslr.com/>

## About

This is a project that contains a collection of [GRUB][] files and scripts that
will allow you to create a pendrive capable of booting [different ISO
files][isos].

![Demo
GIF](https://gitlab.com/aguslr/multibootusb/raw/master/docs/assets/img/demo.gif
"Demo")


## Documentation

Visit the [project's website for more information][website].

[grub]: https://www.gnu.org/software/grub/
[isos]: https://mbusb.aguslr.com/isos.html
[website]: https://mbusb.aguslr.com/

## Installation

```bash
nix-build default.nix
sudo ./result/bin/makeUSB.sh /dev/sda exfat
```

## Dependencies

- coreutils
- gptfdisk
- curl
- gnutar
- unzip
- grub2
- gnused
- exfatprogs: for exfat

## Example directory structure

```bash
eza --tree $data_mnt
$data_mnt
├── autounattend.xml
└── boot
    ├── autoexec.ipxe
    ├── grub
    └── isos
        ├── artix-xfce-runit-20240823-x86_64.iso
        ├── hirens
        └── ipxe.efi
```
