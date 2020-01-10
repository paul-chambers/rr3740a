#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
# /usr/lib/dracut/modules.d/40hptdrv

check() {
    return 0
}

depends() {
    return 0
}

install() {
    inst_hook pre-udev 40 "$moddir/dracut-hptdrv.sh"
}

