# Resolves paths inside the proot-distro container directly from Termux.
# Plain config files (dotfiles, .conf files) can be written straight into
# the rootfs without going through 'proot-distro login' — that's only
# needed to actually execute something inside the container.

[ -n "${TDE_CONTAINER_PATHS_LOADED:-}" ] && return 0
TDE_CONTAINER_PATHS_LOADED=1

export TDE_DISTRO_NAME="${TDE_DISTRO_NAME:-${ARCH_DISTRO_ALIAS:-archarm}}"
# Matches proot-distro's own INSTALLED_ROOTFS_DIR (RUNTIME_DIR/installed-rootfs,
# RUNTIME_DIR=$PREFIX/var/lib/proot-distro — see proot-distro.sh upstream),
# i.e. the rootfs sits directly at .../installed-rootfs/<alias>, not under
# an extra "containers/<alias>/rootfs" layout. Verified against
# termux/proot-distro master (v4.13.0): every "${INSTALLED_ROOTFS_DIR}/${distro_name}/etc"
# check in command_install() confirms /etc lives right under that path.
TDE_ROOTFS_PATH="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/installed-rootfs/$TDE_DISTRO_NAME"

container_home() {
  echo "$TDE_ROOTFS_PATH/home/$1"
}
