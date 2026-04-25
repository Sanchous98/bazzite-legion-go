FROM ghcr.io/ublue-os/bazzite-deck:stable

# EDID file
COPY legiongo-vrr.bin /usr/lib/firmware/edid/legiongo-vrr.bin

# Dracut config — force file into initramfs
RUN echo 'install_items+=" /usr/lib/firmware/edid/legiongo-vrr.bin "' \
    > /usr/lib/dracut/dracut.conf.d/99-legion-go-edid.conf

# Patch bazzite-hardware-setup
RUN sed -i $'/AOKZOE A1 on deck build detected, fixing edid/i\\\nif [[ $IMAGE_NAME =~ "deck" && ":83E1:" =~ ":$SYS_ID:" ]]; then\\\n  echo "Legion Go on deck build detected, fixing edid for FreeSync"\\\n  if [[ ! $KARGS =~ "drm.edid_firmware" ]]; then\\\n    NEEDED_KARGS+=("--append-if-missing=drm.edid_firmware=eDP-1:edid/legiongo-vrr.bin")\\\n  fi\\\nfi\\\n' /usr/libexec/bazzite-hardware-setup

# Bump HWS_VER for re-run on existing systems
RUN sed -i 's/^HWS_VER=68$/HWS_VER=99/' /usr/libexec/bazzite-hardware-setup

RUN ostree container commit