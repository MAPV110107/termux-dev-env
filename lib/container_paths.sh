# Resolves paths inside the proot-distro container directly from Termux.
# Plain config files (dotfiles, .conf files) can be written straight into
# the rootfs without going through 'proot-distro login' — that's only
# needed to actually execute something inside the container.

[ -n "${TDE_CONTAINER_PATHS_LOADED:-}" ] && return 0
TDE_CONTAINER_PATHS_LOADED=1

export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
TDE_ROOTFS_PATH="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/containers/$TDE_DISTRO_NAME/rootfs"

container_home() {
  echo "$TDE_ROOTFS_PATH/home/$1"
}
