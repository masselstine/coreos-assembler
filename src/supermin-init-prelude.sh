#!/usr/bin/env bash
# This script is our half-baked ad-hoc reimplementation of a minimal
# Linux boot environment that we generate via `supermin`.  At some
# point we will likely switch to using systemd.

if [ ! -d /proc ]; then mkdir /proc; chmod 555 /proc; fi
mount -t proc /proc /proc
if [ ! -d /sys ]; then mkdir /sys; chmod 555 /sys; fi
mount -t sysfs /sys /sys
#mount -t cgroup2 cgroup2 -o rw,nosuid,nodev,noexec,relatime,seclabel,nsdelegate,memory_recursiveprot /sys/fs/cgroup
mount -t cgroup2 cgroup2 -o rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot /sys/fs/cgroup
if [ ! -d /dev ]; then mkdir /dev; chmod 755 /dev; fi
mount -t devtmpfs devtmpfs /dev

# need /dev/shm for podman
mkdir -p /dev/shm
mount -t tmpfs tmpfs /dev/shm

# load selinux policy
#LANG=C /sbin/load_policy  -i

# load kernel module for 9pnet_virtio for 9pfs mount
/usr/sbin/modprobe 9pnet_virtio
/usr/sbin/modprobe 9p

# need fuse module for rofiles-fuse/bwrap during post scripts run
/usr/sbin/modprobe fuse

# we want /dev/disk symlinks for coreos-installer
/usr/lib/systemd/systemd-udevd --daemon
# We've seen this hang before, so add a timeout. This is best-effort anyway, so
# let's not fail on it.
timeout 30s /usr/sbin/udevadm trigger --settle || :

# set up networking
if [ -z "${RUNVM_NONET:-}" ]; then
    /usr/sbin/dhcpcd -b eth0
fi

# set the umask so that anyone in the group can rwx
umask 002

# set up workdir
# For 9p mounts set msize to 100MiB
# https://github.com/coreos/coreos-assembler/issues/2171
mkdir -p "${workdir:?}"
mount -t 9p -o rw,trans=virtio,version=9p2000.L,msize=10485760 workdir "${workdir}"

# This loop pairs with virtfs setups for qemu in cmdlib.sh.  Keep them in sync.
for maybe_symlink in "${workdir}"/{src/config,src/yumrepos,builds}; do
    if [ -L "${maybe_symlink}" ]; then
        bn=$(basename "${maybe_symlink}")
        mkdir -p "$(readlink "${maybe_symlink}")"
        mount -t 9p -o rw,trans=virtio,version=9p2000.L,msize=10485760 "${bn}" "${maybe_symlink}"
    fi
done

mkdir -p "${workdir}"/cache
cachedev=$(blkid -lt LABEL=cosa-cache -o device || true)
if [ -n "${cachedev}" ]; then
    mount "${cachedev}" "${workdir}"/cache
else
    echo "No cosa-cache filesystem found!"
fi

if [ -f "${workdir}/tmp/supermin/supermin.env" ]; then
    source "${workdir}/tmp/supermin/supermin.env";
fi

# Code can check this to see whether it's being run via supermin; in
# some cases it may be convenient to have files wrap themselves, and
# this disambiguates between container and supermin.
touch /etc/cosa-supermin

# /usr/sbin/ip{,6}tables is installed as a symlink to /etc/alternatives/ip{,6}tables but
# the /etc/alternatives symlink to /usr/sbin/ip{,6}tables-legacy is missing.  This recreates
# the missing link.  Hehe.
#update-alternatives --install /etc/alternatives/iptables iptables /usr/sbin/iptables-legacy 1
#update-alternatives --install /etc/alternatives/ip6tables ip6tables /usr/sbin/ip6tables-legacy 1

# https://github.com/koalaman/shellcheck/wiki/SC2164
cd "${workdir}" || exit
