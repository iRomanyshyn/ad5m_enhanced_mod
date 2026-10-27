# !/bin/bash
# Build Wrapper Script for AD5M Klipper Mod
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/env.sh

MULTICORE=-j$(nproc)
#####################################################
###### Buildroot Common Build Helper Functions ######
#####################################################

# Verify that a build uses the reviewed Buildroot tree recorded in this
# repository. Do not silently reuse output configured by another Buildroot
# source: it makes a package impossible to reproduce and can mix host tools.
verify_buildroot_contract()
{
	if [ ! -r "$BUILDROOT_CONTRACT_FILE" ]; then
		log_error "Buildroot contract file not found: $BUILDROOT_CONTRACT_FILE"
		exit 1
	fi

	expected_revision=$(tr -d '[:space:]' < "$BUILDROOT_CONTRACT_FILE")
	if ! [[ "$expected_revision" =~ ^[0-9a-f]{40}$ ]]; then
		log_error "Invalid Buildroot revision in $BUILDROOT_CONTRACT_FILE"
		exit 1
	fi

	if [ ! -d "$BUILDROOT_GIT" ] || [ ! -f "$BUILDROOT_GIT/Makefile" ]; then
		log_error "Canonical Buildroot checkout not found: $BUILDROOT_GIT"
		log_error "Clone ../buildroot-flashforge-ad5m or set AD5M_BUILDROOT_DIR to a reviewed checkout."
		exit 1
	fi

	BUILDROOT_GIT=$(realpath "$BUILDROOT_GIT")
	actual_revision=$(git -C "$BUILDROOT_GIT" rev-parse HEAD 2>/dev/null) || {
		log_error "Buildroot source is not a Git checkout: $BUILDROOT_GIT"
		exit 1
	}

	if [ "$actual_revision" != "$expected_revision" ]; then
		log_error "Buildroot revision mismatch: expected $expected_revision, found $actual_revision"
		log_error "Update both repositories through a reviewed AD5M-001 contract change."
		exit 1
	fi

	if [ -n "$(git -C "$BUILDROOT_GIT" status --porcelain --untracked-files=normal)" ]; then
		log_error "Buildroot checkout has uncommitted changes: $BUILDROOT_GIT"
		exit 1
	fi
}

# initialize a buildroot build dir with config
buildroot_prepare() # args: path config_generator
{
	br_path="$1";
	br_name=$(basename "$1")
	br_config_generator="$2"
	verify_buildroot_contract

	mkdir -p "$br_path"
	pushd "$br_path" > /dev/null

	if [ -f Makefile ] && ! grep -Fq "MAKEARGS := -C $BUILDROOT_GIT" Makefile; then
		log_error "$br_name was configured with a different Buildroot source. Run the corresponding clean target first."
		exit 1
	fi

	# setup make environment, use external tree
    if [ ! -f Makefile ]; then
  		make O="$PWD" BR2_EXTERNAL="$BUILDROOT_EXT" -C "$BUILDROOT_GIT" $MULTICORE allnoconfig
    fi

	# backup old config
  	if [ -f .config ]; then
	    mv .config .config_old
    fi

	# generate new config from defconfigs
    $br_config_generator
    make $MULTICORE olddefconfig

	# restore old config if unchanged (keep timestamp)
    if [ -f .config_old ] && cmp --silent .config .config_old
    then
  	    mv -f .config_old .config
  	    log_info "$br_name: config up to date"
    else
        rm -f .config_old
        log_info "$br_name: config initialized"
    fi

    popd > /dev/null
}

# (re-)build a buildroot project
buildroot_build_always() # args: path make_command
{
	br_path="$1";
	br_name=$(basename "$1")
	br_make="$2 $MULTICORE"

	pushd "$br_path" > /dev/null

	if [ -e "host" ] || [ -e "images" ] || [ -e "target" ] || \
	   find build/ -mindepth 1 -maxdepth 1 ! -name buildroot-config 2> /dev/null | read; then
	   log_warn "unclean build of $br_name"
	fi

	if $br_make
	then
		log_info "$br_name: build done"
	else
		log_error "$br_name: build failed"
		exit 1
	fi

	popd > /dev/null
}


# (re-)build a buildroot build dir if not uptodate
buildroot_build_if_needed() # args: path make_command target_file
{
	br_path="$1";
	br_name=$(basename "$1")
	br_make="$2 $MULTICORE"
	br_target_file="$3"

	pushd "$br_path" > /dev/null

	if [ -f "$br_target_file" ] && [ "$br_target_file" -nt .config ]
	then
		log_info "$br_name: target up to date"
	else
		buildroot_build_always "$br_path" "$br_make"
	fi

	popd > /dev/null
}

###########################################
###### Buildroot Mod SDK Build Steps ######
###########################################

defconfig_sdk() {
    cp "$BUILDROOT_CONFIGS/sdk" "$BUILDROOT_SDK/.config"
}

prepare_sdk() {
	buildroot_prepare "$BUILDROOT_SDK" "defconfig_sdk"
}

build_sdk() {
	br_image=( "$BUILDROOT_SDK"/images/*sdk-buildroot.tar.gz )
	buildroot_build_if_needed "$BUILDROOT_SDK" "make sdk"  "$br_image"
}

rebuild_sdk() {
	buildroot_build_always "$BUILDROOT_SDK" "make sdk"
}

clean_sdk() {
  rm -rf "$BUILDROOT_SDK"
}

package_sdk()
{
	br_image=( "$BUILDROOT_SDK"/images/*sdk-buildroot.tar.gz )
	sdk_name="KlipperMod-SDK-$GIT_VERSION.tar.xz"
	mkdir -p $BUILD_PACKAGE
	gzip -dc "$br_image" | xz -T`nproc` > $BUILD_PACKAGE/$sdk_name
	log_info "sdk: created $sdk_name"
}

###############################################
###### Buildroot Mod Variant Build Steps ######
###############################################

variant_env()
{
	variant=$1

	# add plugins suffix to build directory name if plugins are used
	plugin_suffix=""
	if [ -n "$WITH_PLUGINS" ]; then
		plugin_suffix="-$(echo "$WITH_PLUGINS" | tr ' ' '\n' | sort | tr '\n' '-' | sed 's/-$//')"
	fi

    br_builddir="$BUILDROOT_OUT/variant-$variant$plugin_suffix"
	br_image="$br_builddir/images/rootfs.tar"
	br_chroot="$br_builddir/images/chroot.tar.xz"
}

defconfig_variant() {
    variant_env $1
    pushd $br_builddir
  	# merge config fragments to .config
  	merge_configs=("$BUILDROOT_CONFIGS/sdk" "$BUILDROOT_CONFIGS/base" "$BUILDROOT_CONFIGS/variant-$variant")
  	
  	# add plugin configs if WITH_PLUGINS is set
  	if [ -n "$WITH_PLUGINS" ]; then
  		log_info "Adding plugins to variant-$variant: $WITH_PLUGINS"
  		for plugin in $WITH_PLUGINS; do
  			plugin_config="$BUILDROOT_CONFIGS/plugin-$plugin"
  			if [ -f "$plugin_config" ]; then
  				merge_configs+=("$plugin_config")
  			else
  				log_error "Plugin config not found: $plugin_config"
  				exit 1
  			fi
  		done
  	fi
  	
  	"$BUILDROOT_GIT"/support/kconfig/merge_config.sh "${merge_configs[@]}"
	# Buildroot resolves BR2_TOOLCHAIN_EXTERNAL_PATH against its source tree,
	# whereas the SDK is owned by this repository's output tree. Set the
	# generated configuration from BUILDROOT_SDK so canonical sibling checkouts
	# and reviewed AD5M_BUILDROOT_DIR overrides both use the exact SDK we built.
	sdk_host_dir=$(realpath -m "$BUILDROOT_SDK/host")
	sed -i '/^BR2_TOOLCHAIN_EXTERNAL_PATH=/d' .config
	printf 'BR2_TOOLCHAIN_EXTERNAL_PATH="%s"\n' "$sdk_host_dir" >> .config
	# Klipper's MCU configs are consumed by package build commands from the
	# Buildroot output directory. Derive their paths from the repository root
	# instead of relying on a fragment-relative path.
	mcu_config_dir=$(realpath -m "$GIT_ROOT/build_scripts/components/mcu_configs/ffad5m")
	sed -i '/^BR2_PACKAGE_KLIPPER_CONFIGS=/d' .config
	printf 'BR2_PACKAGE_KLIPPER_CONFIGS="%s/eboard %s/mainboard"\n' \
		"$mcu_config_dir" "$mcu_config_dir" >> .config
	# Rootfs overlays are likewise interpreted relative to Buildroot's source
	# tree. Generate absolute paths for the selected variant so the wrapper is
	# independent of checkout layout.
	overlay_common=$(realpath -m "$GIT_ROOT/build_overlays/common")
	overlay_variant=$(realpath -m "$GIT_ROOT/build_overlays/variant-$variant")
	sed -i '/^BR2_ROOTFS_OVERLAY=/d' .config
	printf 'BR2_ROOTFS_OVERLAY="%s %s"\n' \
		"$overlay_common" "$overlay_variant" >> .config
    popd > /dev/null
}

prepare_variant() {
	variant_env $1
	buildroot_prepare "$br_builddir" "defconfig_variant $variant"
}

build_variant() {
	variant_env $1
	buildroot_build_if_needed "$br_builddir" "make" "$br_image"
}

rebuild_variant() {
	variant_env $1
	buildroot_build_always "$br_builddir" "make"
}

clean_variant() {
	variant_env $1
	rm -rf "$br_builddir"
}

package_variant() {
	variant_env $1
	rm -f "$br_chroot"
	xz -cT`nproc` "$br_image" > "$br_chroot"

	# add plugins suffix to package name if plugins are used
	plugin_suffix=""
	if [ -n "$WITH_PLUGINS" ]; then
		plugin_suffix="-$(echo "$WITH_PLUGINS" | tr ' ' '\n' | sort | tr '\n' '-' | sed 's/-$//')"
	fi

	package_name="Adventurer5M-KlipperMod-$GIT_VERSION-$variant$plugin_suffix.tgz"
	package_name_pro="Adventurer5MPro-KlipperMod-$GIT_VERSION-$variant$plugin_suffix.tgz"
	mkdir -p $BUILD_PACKAGE
	tar -cf "$BUILD_PACKAGE/$package_name" -C "$GIT_ROOT/device_files/install" . -C "$br_builddir/images/" ./chroot.tar.xz
	cp "$BUILD_PACKAGE/$package_name" "$BUILD_PACKAGE/$package_name_pro"
	log_info "variant-$variant: created $package_name"
}

##############################
###### Misc Build Steps ######
##############################

package_uninstall()
{
	package_name="Adventurer5M-KlipperMod-uninstall.tgz"
	package_name_pro="Adventurer5MPro-KlipperMod-uninstall.tgz"
	tar -cf "$BUILD_PACKAGE/$package_name" -C "$GIT_ROOT/device_files/uninstall" . -C "$GIT_ROOT/build_overlays/common/usr/libexec" ./mcu_update.sh
	cp "$BUILD_PACKAGE/$package_name" "$BUILD_PACKAGE/$package_name_pro"
	log_info "uninstall: created $package_name"
}

checksums()
{
	pushd $BUILD_PACKAGE > /dev/null
	rm -f md5sums
	md5sum * > md5sums
	log_info "created checksums:"
	cat md5sums
	popd > /dev/null
}

cd $GIT_ROOT
GIT_VERSION=$(git describe --tags --always --dirty)

# run command
$@
