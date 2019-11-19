#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2019 Petr Vorel <pvorel@suse.cz>
set -e

aclocal
autoconf
autoheader
automake -a
./configure
make -j$(getconf _NPROCESSORS_ONLN)
