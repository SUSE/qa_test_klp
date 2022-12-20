#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2019 Petr Vorel <pvorel@suse.cz>
set -e

missing=
for cmd in aclocal autoconf autoheader automake make; do
	if ! command -v $cmd >/dev/null; then
		echo "Missing '$cmd', install it!"
		missing=1
	fi
done

if [ "$missing" ]; then
	exit 22
fi

aclocal
autoconf
autoheader
automake -a
./configure
make -j$(getconf _NPROCESSORS_ONLN)
