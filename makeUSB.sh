#!/usr/bin/env bash

# Description: Script to prepare multiboot USB drive

# show line number when execute by bash -x makeUSB.sh
[ "$BASH" ] &&
	export PS4='    +\t $BASH_SOURCE:$LINENO: ${FUNCNAME[0]:+${FUNCNAME[0]}():}'

# Exit if there is an unbound variable or an error
set -o nounset
set -o errexit

# Defaults
scriptname=$(basename "$0")
data_part=2
data_fmt="vfat"
data_size=""
efi_mnt=""
data_mnt=""
data_subdir="boot"
tmp_dir="${TMPDIR-/tmp}"
update_only=0

cd "$(dirname "$(realpath "$0")")"

# Show usage
showUsage() {
	cat <<-EOF
		Script to prepare multiboot USB drive
		Usage: $scriptname [options] device [fs-type] [data-size]

		 device                         Device to modify (e.g. /dev/sdb)
		 fs-type                        Filesystem type for the data partition [ext3|ext4|vfat|exfat|ntfs]
		 data-size                      Data partition size (e.g. 5G)
		  -h,  --help                   Display this message
		  -s,  --subdirectory <NAME>    Specify a data subdirectory (default: "boot")
		  -u,  --update                 Only update bootloader and configuration files

		Example: makeUSB.sh /dev/sda vfat

	EOF
}

# Clean up when exiting
cleanUp() {
	# Change ownership of files
	{ [ "$data_mnt" ] &&
		chown -R "$normal_user" "${data_mnt}"/* 2>/dev/null; } ||
		true
	# Unmount everything
	umount -f "$efi_mnt" 2>/dev/null || true
	umount -f "$data_mnt" 2>/dev/null || true
	# Delete mountpoints
	[ -d "$efi_mnt" ] && rmdir "$efi_mnt"
	[ -d "$data_mnt" ] && rmdir "$data_mnt"
	# Exit
	exit "${1-0}"
}

# Make sure USB drive is not mounted
unmountUSB() {
	umount -f "${1}"* 2>/dev/null || true
}

# Trap kill signals (SIGHUP, SIGINT, SIGTERM) to do some cleanup and exit
trap 'cleanUp' 1 2 15

# Show help before checking for root
[ "$#" -eq 0 ] && showUsage && exit 0
case "$1" in
-h | --help)
	showUsage
	exit 0
	;;
esac

# Check for root
if [ "$(id -u)" -ne 0 ]; then
	echo "This script needs to run with root privileges."
	exit 1
fi

# Get original user
normal_user="${SUDO_USER-$(id -un)}"

# Check arguments
while [ "$#" -gt 0 ]; do
	case "$1" in
	-s | --subdirectory)
		shift && data_subdir="$1"
		;;
	-u | --update-only)
		update_only=1
		;;
	/dev/*)
		if [ -b "$1" ]; then
			usb_dev="$1"
		else
			printf '%s: %s is not a valid device.\n' "$scriptname" "$1" >&2
			cleanUp 1
		fi
		;;
	[a-z]*)
		data_fmt="$1"
		;;
	[0-9]*)
		data_size="$1"
		;;
	*)
		printf '%s: %s is not a valid argument.\n' "$scriptname" "$1" >&2
		cleanUp 1
		;;
	esac
	shift
done

# Check for required arguments
if [ ! "$usb_dev" ]; then
	printf '%s: No device was provided.\n' "$scriptname" >&2
	showUsage
	cleanUp 1
fi

# Check for GRUB installation binary
if [ -n "${GRUB_EFI:-}" ]; then
	grubefi="$GRUB_EFI"
else
	grubefi=$(command -v grub-install || command -v grub2-install) || cleanUp 3
fi

# Unmount device
unmountUSB "$usb_dev"

if [ "$update_only" -eq 0 ]; then
	# Confirm the device
	printf 'Are you sure you want to use %s? [y/N] ' "$usb_dev"
	read -r answer1
	case "$answer1" in
	[yY][eE][sS] | [yY])
		printf 'THIS WILL DELETE ALL DATA ON THE DEVICE. Are you sure? [y/N] '
		read -r answer2
		case $answer2 in
		[yY][eE][sS] | [yY])
			true
			;;
		*)
			cleanUp 3
			;;
		esac
		;;
	*)
		cleanUp 3
		;;
	esac

	# Print all steps
	set -o verbose

	# Remove partitions
	sgdisk --zap-all "$usb_dev"

	# Create GUID Partition Table
	#sgdisk --mbrtogpt "$usb_dev" || cleanUp 10

	# Create EFI System partition (50M)
	sgdisk --new 1::+50M --typecode 1:0700 \
		--change-name 1:"EFI System" "$usb_dev" || cleanUp 10

	# Set data partition size
	[ -z "$data_size" ] ||
		data_size="+$data_size"

	# Set data partition information
	case "$data_fmt" in
	ext2 | ext3 | ext4)
		type_code="8300"
		part_name="Linux filesystem"
		;;
	msdos | fat | vfat | ntfs | exfat)
		type_code="0700"
		part_name="Microsoft basic data"
		;;
	*)
		printf '%s: %s is an invalid filesystem type.\n' "$scriptname" "$data_fmt" >&2
		showUsage
		cleanUp 1
		;;
	esac

	# Create data partition
	sgdisk --new ${data_part}::"${data_size}": --typecode ${data_part}:"$type_code" \
		--change-name ${data_part}:"$part_name" "$usb_dev" || cleanUp 10

	# Unmount device
	unmountUSB "$usb_dev"

	# Set bootable flag for data partion
	#sgdisk --attributes ${data_part}:set:2 "$usb_dev" || cleanUp 10

	# Unmount device
	unmountUSB "$usb_dev"

	# Format EFI System partition
	wipefs -af "${usb_dev}1" || true
	mkfs.vfat -v -F 32 -n EFI "${usb_dev}1" || cleanUp 10

	# Wipe data partition
	wipefs -af "${usb_dev}${data_part}" || true

	# Format data partition
	if [ "$data_fmt" = "ntfs" ]; then
		# Use mkntfs quick format
		mkfs -t "$data_fmt" -f "${usb_dev}${data_part}" || cleanUp 10
	else
		mkfs -t "$data_fmt" "${usb_dev}${data_part}" || cleanUp 10
	fi
fi

# Unmount device
unmountUSB "$usb_dev"

# Create temporary directories
efi_mnt=$(mktemp -p "$tmp_dir" -d efi.XXXX) || cleanUp 10
data_mnt=$(mktemp -p "$tmp_dir" -d data.XXXX) || cleanUp 10

# Mount EFI System partition
mount "${usb_dev}1" "$efi_mnt" || cleanUp 10

# Mount data partition
mount "${usb_dev}${data_part}" "$data_mnt" || cleanUp 10

# Install GRUB for EFI
$grubefi --target=x86_64-efi --efi-directory="$efi_mnt" \
	--boot-directory="${data_mnt}/${data_subdir}" --removable --recheck ||
	cleanUp 10

# Create necessary directories
mkdir -p "${data_mnt}/${data_subdir}/isos" || cleanUp 10
mkdir -p "${data_mnt}/${data_subdir}/grub/tools" || cleanUp 10

# Copy files
cp -R ./mbusb.* "${data_mnt}/${data_subdir}"/grub*/ ||
	cleanUp 10

sed -i "1aset rootuuid=$(blkid -o value -s UUID ${usb_dev}${data_part})" ${data_mnt}/${data_subdir}/grub/mbusb.cfg ||
	cleanUp 10

# Copy example configuration for GRUB
cp ./grub.cfg.example "${data_mnt}/${data_subdir}"/grub*/ ||
	cleanUp 10

# Rename example configuration
(cd "${data_mnt}/${data_subdir}"/grub*/ && cp grub.cfg.example grub.cfg) ||
	cleanUp 10

# Download wimboot
wimboot_url='https://gitlab.com/api/v4/projects/55131919/packages/generic/wimboot/v2.8.0-1/wimboot-v2.8.0-1.tar.gz'
mountiso_url='https://gitlab.com/api/v4/projects/55267894/packages/generic/mountiso/v0.1.0/mountiso-v0.1.0.zip'
(cd "${data_mnt}/${data_subdir}"/grub*/ && cd tools && curl -sL "$wimboot_url" | tar -zxvf - --wildcards --no-anchored 'wimboot.*' ) || cleanUp 10
(cd "${data_mnt}/${data_subdir}"/grub*/ && cd tools && curl -sL "$mountiso_url" -o mountiso.zip && unzip mountiso.zip 'mountiso*' && rm mountiso.zip) || cleanUp 10

ipxe_url='https://boot.ipxe.org/ipxe.efi'
curl -sL "$ipxe_url" -o "$data_mnt/$data_subdir/isos/ipxe.efi" || cleanUp 10

# Clean up and exit
cleanUp
