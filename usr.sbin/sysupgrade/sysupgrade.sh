#!/bin/ksh
#
# $OpenBSD: sysupgrade.sh,v 1.30 2019/11/03 18:22:45 florian Exp $
#
# Copyright (c) 1997-2015 Todd Miller, Theo de Raadt, Ken Westerback
# Copyright (c) 2015 Robert Peichaer <rpe@openbsd.org>
# Copyright (c) 2016, 2017 Antoine Jacoutot <ajacoutot@openbsd.org>
# Copyright (c) 2019 Christian Weisgerber <naddy@openbsd.org>
# Copyright (c) 2019 Florian Obser <florian@openbsd.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

set -e
umask 0022
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

ARCH=$(uname -m)
SETSDIR=/home/_sysupgrade

ug_err()
{
	echo "${1}" 1>&2 && return ${2:-1}
}

usage()
{
	ug_err "usage: ${0##*/} [-fkn] [-r | -s] [installurl]"
}

unpriv()
{
	local _file _rc=0 _user=_syspatch

	if [[ $1 == -f ]]; then
		_file=$2
		shift 2
	fi
 	if [[ -n ${_file} ]]; then
		>${_file}
		chown "${_user}" "${_file}"
	fi
	(($# >= 1))

	# XXX ksh(1) bug; send error code to the caller instead of failing hard
	set +e
	eval su -s /bin/sh ${_user} -c "'$@'" || _rc=$?
	set -e

	[[ -n ${_file} ]] && chown root "${_file}"

	return ${_rc}
}

# Remove all occurrences of first argument from list formed by the remaining
# arguments.
rmel() {
	local _a=$1 _b _c

	shift
	for _b; do
		[[ $_a != "$_b" ]] && _c="${_c:+$_c }$_b"
	done
	echo -n "$_c"
}

RELEASE=false
SNAP=false
FORCE=false
KEEP=false
REBOOT=true

while getopts fknrs arg; do
	case ${arg} in
	f)	FORCE=true;;
	k)	KEEP=true;;
	n)	REBOOT=false;;
	r)	RELEASE=true;;
	s)	SNAP=true;;
	*)	usage;;
	esac
done

(($(id -u) != 0)) && ug_err "${0##*/}: need root privileges"

if $RELEASE && $SNAP; then
	usage
fi

set -A _KERNV -- $(sysctl -n kern.version |
	sed 's/^OpenBSD \([1-9][0-9]*\.[0-9]\)\([^ ]*\).*/\1 \2/;q')

shift $(( OPTIND -1 ))

case $# in
0)	MIRROR=$(sed 's/#.*//;/^$/d' /etc/installurl) 2>/dev/null ||
		MIRROR=https://cdn.openbsd.org/pub/OpenBSD
	;;
1)	MIRROR=$1
	;;
*)	usage
esac

if ! $RELEASE && [[ ${#_KERNV[*]} == 2 ]]; then
	SNAP=true
fi

if $RELEASE && [[ ${_KERNV[1]} == '-beta' ]]; then
	NEXT_VERSION=${_KERNV[0]}
else
	NEXT_VERSION=$(echo ${_KERNV[0]} + 0.1 | bc)
fi

if $SNAP; then
	URL=${MIRROR}/snapshots/${ARCH}/
else
	URL=${MIRROR}/${NEXT_VERSION}/${ARCH}/
fi

if [[ -e ${SETSDIR} ]]; then
	eval $(stat -s ${SETSDIR})
	[[ $st_uid -eq 0 ]] ||
		 ug_err "${SETSDIR} needs to be owned by root:wheel"
	[[ $st_gid -eq 0 ]] ||
		 ug_err "${SETSDIR} needs to be owned by root:wheel"
	[[ $st_mode -eq 040755 ]] || 
		ug_err "${SETSDIR} is not a directory with permissions 0755"
else
	mkdir -p ${SETSDIR}
fi

cd ${SETSDIR}

unpriv -f SHA256.sig ftp -N sysupgrade -Vmo SHA256.sig ${URL}SHA256.sig

_KEY=openbsd-${_KERNV[0]%.*}${_KERNV[0]#*.}-base.pub
_NEXTKEY=openbsd-${NEXT_VERSION%.*}${NEXT_VERSION#*.}-base.pub

read _LINE <SHA256.sig
case ${_LINE} in
*\ ${_KEY})	SIGNIFY_KEY=/etc/signify/${_KEY} ;;
*\ ${_NEXTKEY})	SIGNIFY_KEY=/etc/signify/${_NEXTKEY} ;;
*)		ug_err "invalid signing key" ;;
esac

[[ -f ${SIGNIFY_KEY} ]] || ug_err "cannot find ${SIGNIFY_KEY}"

unpriv -f SHA256 signify -Ve -p "${SIGNIFY_KEY}" -x SHA256.sig -m SHA256
rm SHA256.sig

if cmp -s /var/db/installed.SHA256 SHA256 && ! $FORCE; then
	echo "Already on latest snapshot."
	exit 0
fi

# INSTALL.*, bsd*, *.tgz
SETS=$(sed -n -e 's/^SHA256 (\(.*\)) .*/\1/' \
    -e '/^INSTALL\./p;/^bsd/p;/\.tgz$/p' SHA256)

OLD_FILES=$(ls)
OLD_FILES=$(rmel SHA256 $OLD_FILES)
DL=$SETS

[[ -n ${OLD_FILES} ]] && echo Verifying old sets.
for f in ${OLD_FILES}; do
	if cksum -C SHA256 $f >/dev/null 2>&1; then
		DL=$(rmel $f ${DL})
		OLD_FILES=$(rmel $f ${OLD_FILES})
	fi
done

[[ -n ${OLD_FILES} ]] && rm ${OLD_FILES}
for f in ${DL}; do
	unpriv -f $f ftp -N sysupgrade -Vmo ${f} ${URL}${f}
done

if [[ -n ${DL} ]]; then
	echo Verifying sets.
	unpriv cksum -qC SHA256 ${DL}
fi

${KEEP} && > keep

cat <<__EOT >/auto_upgrade.conf
Location of sets = disk
Pathname to the sets = /home/_sysupgrade/
Set name(s) = done
Directory does not contain SHA256.sig. Continue without verification = yes
__EOT

if ! ${KEEP}; then
	CLEAN=$(echo SHA256 ${SETS} | sed -e 's/ /,/g')
	cat <<__EOT > /etc/rc.firsttime
rm -f /home/_sysupgrade/{${CLEAN}}
__EOT
fi

install -F -m 700 bsd.rd /bsd.upgrade
sync

if ${REBOOT}; then
	echo Upgrading.
	exec reboot
else
	echo "Will upgrade on next reboot"
fi
