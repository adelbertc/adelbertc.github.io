---
title: Installing NixOS
---

In an effort to force myself to learn [Nix][nix] I spent last weekend installing [NixOS][nixOS] on my desktop. It ended
up being a fairly involved process for me, especially since I barely have any experience with Linux. Therefore I've
decided to write about my installation process (to the best of my recollection anyways), both as a reminder to myself
and for anyone else who may be curious.

Being new to Linux and easily sketched out, I tried my best to look up things I didn't understand and will try to
replicate the explanations I found.

In terms of resources I consulted I used the [NixOS manual][nixOSManual], [Chris Martin's blog post][chrisMartinNix],
[Martijn Vermaat's gist][martijnGist], and the extremely helpful [ArchWiki][archWiki].

This post is based on the NixOS installation I did on August 6, 2017. Things may have changed between then and now.

## Goals

* NixOS 17.03
* Installing on a completely separate hard drive (I was sketched out by NixOS sharing a hard drive with Windows)
* Desktop, not laptop (but this post should help laptop users as well)
* Create a bootable USB drive from Windows
* UEFI boot (it's apparently the hip new thing)
* Encrypted disk

# The boring stuff

## Creating a bootable USB drive

1. Download the ISO from the [NixOS site][nixOSDownload]. I used the "Graphical live CD" because it was marked
   recommended but this post does the install entirely with the console so the "Minimal installation" is probably fine
   as well.
2. While the ISO is downloading find a USB drive with enough space for the ISO. Probably something with around 16GB
   of space.
3. Download [Rufus][rufus].
4. Once the ISO is downloaded run Rufus. select MBR partitioning scheme for BIOS or UEFI (when I was installing
   I didn't know I was going to decide on UEFI, choosing GPT here should be fine), FAT32 file system, and the default
   cluster size. Select the ISO, check Quick format for good measure, and I probably checked "Create extended label
   and icon files" as well.
5. Hit Start to.. start. Rufus might prompt you if you want to use ISO or DD mode, pick DD. At the time of this writing
   the NixOS ISO seems to only like DD, and for non-Windows users the recommended way to mount the image is using `dd`
   anyways. It may also prompt you about downloading Syslinux files, click yes. It will just download these files in
   the same folder as wherever Rufus was started from, you can delete them after.
6. Once it's done, eject the drive and shut down your computer.

## Disabling Secure Boot

If your motherboard has Secure Boot, you'll need to disable it. Consult your motherboard manual on how to do so. I
had an ASUS Z87-K, and this is what I did:

1. Find a USB drive with a bit of space on it (we're going to copy some keys onto it so you don't need that much).
2. Shut down the computer and plug the USB drive in.
3. Boot back up and spam F2 to go into the UEFI BIOS screen.
4. Switch to "Advanced Mode."
5. Click "Boot" on the menu bar.
6. Click on "Secure Boot." Here I could see the "Secure boot state" which was enabled - if it shows up as disabled
   you can skip ahead.
7. Click on "Key Mangement."
8. Click "Save Secure Boot Keys" and save it onto your USB drive. Presumably you can use this backup to load the PK
   key which we're about to delete back in if something goes terribly wrong.
9. Delete the PK key.

This should disable Secure Boot.

# The fun stuff

If you're paranoid like me, shut down your computer and disconnect everything but the drive you intend to install
NixOS on.

NixOS will want to download some stuff during installation so make sure you have an internet connection available.
If you have a wired connection with DHCP setup then you're good to go. If you have wired but no DHCP, be prepared
to configure it manually with `ifconfig`. If you have wireless then refer to another guide (perhaps one of the ones
I linked above) to set it up when I mention it later in this post.

Boot up your computer and spam whatever key you need to drop into the boot menu (F8 for me). Select
the UEFI boot from the USB and run the default NixOS installer. You should be dropped into a shell as `root`.

## Preparing your disk

The [NixOS UEFI Installation guide](https://nixos.org/nixos/manual/index.html#sec-uefi-installation) wants a
GPT-partitioned drive with a UEFI boot partition formatted as a `vfat` filesystem.

For the GPT partitioning we're going to use `gdisk`. Here are some links to read up on `gdisk` and related tools:

* [`fdisk` ArchWiki][archFdisk]
* [TLDP's Partitioning with fdisk](http://www.tldp.org/HOWTO/Partition/fdisk_partitioning.html)
* [Rod Smith's "A gdisk Walkthrough"](http://www.rodsbooks.com/gdisk/walkthrough.html)

At the end of this section we'll have a partition table that looks like:

+--------+------------+------+----------------------+
| Number |  Size      | Code | Name                 |
+:=======+:===========+:=====+:=====================+
| 1      | 500 MB     | EF00 | EFI System Partition |
+--------+------------+------+----------------------+
| 2      | the rest   | 8E00 | Linux LVM            |
+--------+------------+-----------------------------+

We will only encrypt the Linux LVM partition as the boot process will need to be able to read the EFI
System Partition before prompting us for the encryption key.

Chris's post also has a 1 MB EF02 BIOS boot partition, but honestly writes "Don’t ask me exactly what this is for,
all I know is it has to be there." Seeing this I dug around and found on the
[GRUB ArchWiki](https://wiki.archlinux.org/index.php/GRUB) page "For UEFI systems [the BIOS boot partition] is not
required, since no embedding of boot sectors takes place...However, UEFI systems still require an ESP."
The [Fdisk ArchWiki][archFdisk] page then says "GRUB requires a BIOS boot partition with code ef02." NixOS usually
gives the option of either using GRUB or systemd-boot, but for the UEFI install it defaults to systemd-boot. When I
asked on the #nixos IRC channel about UEFI with GRUB, I was told that the two used to not play nicely together. Being
the generally risk-averse person I am, I opted not to try.

Now to actually do the partitioning.

1. Identify your drive's name with `fdisk  -l`. Be extremely sure of this because if you have other drives
   connected and you format the wrong one, the data is gone.
2. Run `gdisk <drive name>`, e.g. `gdisk /dev/sda`.
3. Hit `p` to print the partition table and confirm this is the drive you want to work with.
4. `o` to clear any partition table that may have previously been on the drive.
5. `p` to verify the table is clear.
6. `n` to add a new partition for the EFI System Partition. Use the default for the number and first sector, `+500M` for
   the last sector, and `EF00` for the hex code.
7. `n` again, now for the Linux LVM partition. Use the default for the number, first, and last sector (it will default
   to fill up the rest of the drive), and `8E00` for the hex code. Some guides suggest `8300` for Linux filesystem, I
   decided to use `8E00` since that's what the
   [Dm-crypt ArchWiki](https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system) page suggests for the
   encrypted drive.
8. `p` to verify the state of the table.
9. `w` to save and apply the changes.

Once that is done we can encrypt the drive with [LUKS](https://gitlab.com/cryptsetup/cryptsetup) and throw a filesystem
on top.

1. At the command line run `fdisk -l` and identify the names of your EFI System Partition and your Linux LVM partition.
   Write these down as we'll need them in a bit. These should be something like `/dev/sda1` and `/dev/sda2`. For me it
   was `/dev/sdb1` and `/dev/sdb2`. I'm going to use `<boot partition>` to indicate the EFI System Partition name and
   `<lvm partition>` to indicate the Linux LVM partition. Be very careful not to mix these two names up.
2. `cryptsetup luksFormat <lvm partition>` to create the LUKS container at the specified partition. You will be
   prompted for the passphrase that will need to be entered whenever your boot into NixOS.
3. `cryptsetup luksOpen <lvm partition> enc-pv` to open the encrypted container. The container will then be available
   under `/dev/mapper/enc-pv`. As far as I can tell the "enc-pv" is just a human-friendly name, I have
   seen other guides call this `crypted` or `cryptroot`. I use `enc-pv` because that's what the guides I was following
   used and I'm paranoid.
4. `pvcreate /dev/mapper/enc-pv` to create a physical volume on the partition.
5. `vgcreate vg /dev/mapper/enc-pv` to create a volume group.
6. `lvcreate -L <# of GB of swap space you want>G swap vg` to create swap space. I wasn't sure how much to put here
   and some preliminary searching led to long arguments about why an apparently old rule of 2 x (amount of RAM) is no
   longer necessary. I was lazy so I just put 16G, but you may want to put more thought into this than I.
7. `lvcreate -l '100%FREE' -n root vg` to allocate the rest of the partition for your root filesystem.
8. `mkfs.vfat -n BOOT <boot partition>` (not the LVM partition!!!) to format the boot partition, giving it a label
   of "BOOT."
9. I'm going to format the root filesystem at ext4 since that's what the cool kids seem to use. If you want something
   else do your thing here. For ext4, `mkfs.ext4 -L root /dev/vg/root`. This also gives it the label "root."
10. `mkswap -L swap /dev/vg/swap` to setup and name the swap.
11. Now we mount the partitions. We're going to mount at `/mnt` since that's what NixOS manual says to do.
  `mount /dev/vg/root /mnt` to mount the root filesystem.
12. `mkdir /mnt/boot`
13. `mount <boot partition> /mnt/boot`
14. `swapon /dev/vg/swap` to activate swap.

## Installing NixOS

Finally, let's generate the NixOS configuration files and get this show on the road.

1. `nixos-generate-config --root /mnt`. This will generate two configuration files under `/mnt/etc/nixos`,
   `configuration.nix` which will hold the configuration for your whole system and what you will probably be changing
   not unfrequently, and `hardware-configuration.nix` which you probably shouldn't touch.
2. We're going to need to refer to the LVM partition in a reliable way later, so run `blkid <lvm partition>` and write
   down the UUID associated with it.
3. If you intend on using a wireless internet connection, this is about the time you should refer to another guide to
   get WiFi setup. If you're using wired without DHCP, make sure you have that setup as well.
4. Before booting into NixOS proper we need to tell it to expect an encrypted partition. Use `vim` or `nano` or
   something to open and edit `/mnt/etc/nixos/configuration.nix`.
5. Add the following somewhere in the file:

```nix
boot.initrd.luks.devices = [
  {
    name = "root";
    device = /dev/disk/by-uuid/<the aforementioned UUID here>;
    preLVM = true;
  }
];
```

When I first did this I just put my LVM partition name under `device`, something like `device = /dev/sda2`. After I
shut down my computer, reconnected my other hard drive, and rebooted my machine, NixOS complained about `/dev/sda2`
being wonky. Apparently the names assigned to drives can vary across boots, and it's not surprising connecting another
drive can mess with how names are chosen. Therefore instead of referring to the root filesystem by name in the
configuration we use the more reliable UUID.

6. Somewhere you should also see `boot.loader.systemd-boot.enable = true`. When I mentioned earlier that NixOS UEFI
   defaults to systemd-boot, this is what I was referring to.
7. Save the file, and run `nixos-install` to apply the configuration. This will pull a bunch of packages down from
   upstream and do the Nix thing to get everything setup. If everything is OK it should prompt you for a password to
   use for root in your newly installed NixOS. If something went wrong it'll stop and you just need to edit the
   configuration file again to fix your mistake.
8. `reboot` to reboot into your installed NixOS! Hopefully your boot order is configured so this just works, otherwise
   you may have to drop into the boot menu again to select the right drive.
9. You should be prompted for your LUKS passphrase on startup, followed by your username and password. Use `root` and
   the password you chose in the previous step. If you are instead greeted with an error jump to the paragraph after
   this section.
10. You're done! You can now start following step 14 of the
    [NixOS installation guide](https://nixos.org/nixos/manual/index.html#ch-installation) or do your own thing.

If your NixOS boot does not work, you mess up, or need to reboot for any reason, just boot from your USB drive in
UEFI mode like before. To re-setup everything so you can fix the NixOS configuration:

1. Use `fdisk -l` to identify your boot partition and LVM  partition name.
2. `cryptsetup luksOpen <lvm partition> enc-pv` (or whatever friendly name you chose earlier).
3. `lvchange -a y /dev/vg/swap`
4. `lvchange -a y /dev/vg/root`
5. `mount /dev/vg/root /mnt`
6. `mount <boot partition> /mnt/boot`
7. `swapon /dev/vg/swap`

You should then be able to edit `/mnt/etc/nixos/configuration.nix` as before.

[archWiki]: https://wiki.archlinux.org/
[archFdisk]: https://wiki.archlinux.org/index.php/Fdisk
[chrisMartinNix]: https://chris-martin.org/2015/installing-nixos
[martijnGist]: https://gist.github.com/martijnvermaat/76f2e24d0239470dd71050358b4d5134
[nix]: https://nixos.org/nix/
[nixOS]: https://nixos.org/
[nixOSDownload]: https://nixos.org/nixos/download.html
[nixOSManual]: https://nixos.org/nixos/manual/index.html#sec-installation
[rufus]: https://rufus.akeo.ie/
