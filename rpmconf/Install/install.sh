#!/bin/bash
#
# ***** BEGIN LICENSE BLOCK *****
# Zimbra Collaboration Suite Server
# Copyright (C) 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016 Synacor, Inc.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software Foundation,
# version 2 of the License.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program.
# If not, see <https://www.gnu.org/licenses/>.
# ***** END LICENSE BLOCK *****
#

ID=`id -u`

if [ "x$ID" != "x0" ]; then
  echo "Run as root!"
  exit 1
fi

if [ ! -x "/usr/bin/perl" ]; then
  echo "ERROR: System perl at /usr/bin/perl must be present before installation."
  exit 1
fi

MYDIR="$(cd "$(dirname "$0")" && pwd)"

. ./util/utilfunc.sh

for i in ./util/modules/*sh; do
	. $i
done

UNINSTALL="no"
SOFTWAREONLY="no"
SKIP_ACTIVATION_CHECK="no"
SKIP_UPGRADE_CHECK="no"
SKIP_NG_CHECK="no"
ALLOW_PLATFORM_OVERRIDE="no"
FORCE_UPGRADE="no"

usage() {
  echo "$0 [-r <dir> -l <licensekey> -u -s -c type -x -h] [defaultsfile]"
  echo ""
  echo "-h|--help               Usage"
  echo "-l|--licensekey         License key to install."
  echo "-r|--restore <dir>      Restore contents of <dir> to localconfig"
  echo "-s|--softwareonly       Software only installation."
  echo "-u|--uninstall          Uninstall ZCS"
  echo "-x|--skipspacecheck     Skip filesystem capacity checks."
  echo "--beta-support          Allows installer to upgrade Network Edition Betas."
  echo "--platform-override     Allows installer to continue on an unknown OS."
  echo "--skip-activation-check Allows installer to continue if license activation checks fail."
  echo "--skip-upgrade-check    Allows installer to skip upgrade validation checks."
  echo "--skip-ng-check         Allows installer to upgrade by removing NG modules and related data."
  echo "--force-upgrade         Force upgrade to be set to YES. Used if there is package installation failure for remote packages."
  echo "[defaultsfile]          File containing default install values."
  echo ""
  exit
}

validateLicensekey() {
    local new="$1"
    if [[ ! "$new" =~ ^[A-Za-z0-9]+$ ]] || (( ${#new} < 18 )) || (( ${#new} > 24 )) || [[ -z "$new" ]]; then
	echo "Invalid license key entered. The license key should be a non-blank alphanumeric string of 18-24 characters without any special characters!"
        usage
    fi
}

checkSkipActivation() {
	if [ x"$SKIP_ACTIVATION_CHECK" = "xyes" ]; then
		if [ ! -d "/opt/zimbra/conf" ]; then
			mkdir -p /opt/zimbra/conf
		fi
		echo "$SKIP_ACTIVATION_CHECK" > /opt/zimbra/conf/skip_activation_check
		chown zimbra:zimbra /opt/zimbra/conf/skip_activation_check
		chmod 644 /opt/zimbra/conf/skip_activation_check
	fi
}


while [ $# -ne 0 ]; do
  case $1 in
    -r|--restore|--config)
      shift
      RESTORECONFIG=$1
      ;;
    -l|--licensekey)
      shift
      LICENSEKEY=$1
      validateLicensekey $LICENSEKEY
      ;;
    -u|--uninstall)
      UNINSTALL="yes"
      ;;
    -s|--softwareonly)
      SOFTWAREONLY="yes"
      ;;
    -x|--skipspacecheck)
      SKIPSPACECHECK="yes"
      ;;
    -platform-override|--platform-override)
      ALLOW_PLATFORM_OVERRIDE="yes"
      ;;
    -beta-support|--beta-support)
      BETA_SUPPORT="yes"
      ;;
    -skip-activation-check|--skip-activation-check)
      SKIP_ACTIVATION_CHECK="yes"
      ;;
    -skip-upgrade-check|--skip-upgrade-check)
      SKIP_UPGRADE_CHECK="yes"
      ;;
    -skip-ng-check|--skip-ng-check)
      SKIP_NG_CHECK="yes"
      ;;
    -force-upgrade|--force-upgrade)
      FORCE_UPGRADE="yes"
      UPGRADE="yes"
      ;;
    -h|-help|--help)
      usage
      ;;
    *)
      DEFAULTFILE=$1
      if [ ! -f "$DEFAULTFILE" ]; then
        echo "ERROR: Unknown option $DEFAULTFILE"
        usage
      fi
      ;;
  esac
  shift
done

. ./util/globals.sh

getPlatformVars

mkdir -p $SAVEDIR
chown zimbra:zimbra $SAVEDIR 2> /dev/null
chmod 750 $SAVEDIR

echo ""
echo "Operations logged to $LOGFILE"

licensefiles=(
    "/opt/zimbra/conf/ZCSLicense-activated.xml"
    "/opt/zimbra/conf/ZCSLicensekey"
    "/opt/zimbra/conf/skip_activation_check"
)

for file in "${licensefiles[@]}"; do
    if [[ -e "$file" ]]; then
        rm -f "$file"
    fi
done

if [ "x$DEFAULTFILE" != "x" ]; then
	AUTOINSTALL="yes"
else
	AUTOINSTALL="no"
fi

if [ "x$LICENSEKEY" != "x" ] ; then
  if [ ! -d "/opt/zimbra/conf" ]; then
    mkdir -p /opt/zimbra/conf
  fi
  echo "$LICENSEKEY" > /opt/zimbra/conf/ZCSLicensekey
  chown zimbra:zimbra /opt/zimbra/conf/ZCSLicensekey
  chmod 644 /opt/zimbra/conf/ZCSLicensekey
fi

checkSkipActivation
checkExistingInstall

if [ x$UNINSTALL = "xyes" ]; then
	askYN "Completely remove existing installation?" "N"
	if [ $response = "yes" ]; then
		REMOVE="yes"
		findUbuntuExternalPackageDependencies
		saveExistingConfig
		removeExistingInstall
	fi
	exit 1
fi

displayLicense

checkUser root

if [ $AUTOINSTALL = "yes" ]; then
	loadConfig $DEFAULTFILE
fi

checkRequired

installable_platform=$(cat ${MYDIR}/.BUILD_PLATFORM)

if [ x"$PLATFORM" = x"$installable_platform" -a x"${ALLOW_PLATFORM_OVERRIDE}" = "xyes" ]; then
  ALLOW_PLATFORM_OVERRIDE="no"
fi

if [ x"${ALLOW_PLATFORM_OVERRIDE}" = "xno" ]; then
  configurePackageServer
fi

checkPackages

if [ $AUTOINSTALL = "no" ]; then
  setRemove

  getInstallPackages

  if [ x"$PLATFORM" != x"$installable_platform" ]; then
    echo ""
    echo "You appear to be installing packages on a platform different"
    echo "than the platform for which they were built."
    echo ""
    echo "This platform is $PLATFORM"
    echo "Packages found: $installable_platform"
    echo "This may or may not work."
    echo ""

    if [ x"${ALLOW_PLATFORM_OVERRIDE}" = "xyes" ]; then

    	echo "Using packages for a platform in which they were not designed for"
    	echo "may result in an installation that is NOT usable. Your support"
    	echo "options may be limited if you choose to continue."
        echo "You will also be responsible for configuring the system to point"
        echo "at an appropriate package repository for third party."
    	echo ""
    	askYN "Install anyway?" "N"
    	if [ $response = "no" ]; then
    		echo "Exiting..."
    		exit 1
    	fi
    else
    	echo "Installation can not continue without manual override."
    	echo "You can override this safety check with $0 --platform-override"
    	echo ""
    	echo "WARNING: Bypassing this check may result in an install or"
    	echo "upgrade that is NOT usable."
    	echo ""
    	exit 1
    fi
  fi

  verifyExecute

else
  checkVersionMatches
  if [ $VERSIONMATCH = "no" ]; then
    if [ $UPGRADE = "yes" ]; then
      echo ""
      echo "###ERROR###"
      echo ""
      echo "There is a mismatch in the versions of the installed schema"
      echo "or index and the version included in this package"
      echo ""
      echo "Automatic upgrade cancelled"
      echo ""
      exit 1
    fi
  fi
fi


D=`date +%s`
echo "${D}: INSTALL SESSION START" >> /opt/zimbra/.install_history
installPackages

D=`date +%s`
echo "${D}: INSTALL SESSION COMPLETE" >> /opt/zimbra/.install_history

if [ x$RESTORECONFIG != "x" ]; then
	SAVEDIR=$RESTORECONFIG
fi

if [ x$SAVEDIR != "x" -a x$REMOVE = "xno" ]; then
    setDefaultsFromExistingConfig
fi

if [ $UPGRADE = "yes" ]; then
	restoreExistingConfig
	restoreCerts
  # deprecated by move of zimlets to /opt/zimbra/zimlets-deployed which isn't removed on upgrade
  #restoreZimlets
fi

if [ "x$LICENSEKEY" != "x" ] ; then
  if [ ! -d "/opt/zimbra/conf" ]; then
    mkdir -p /opt/zimbra/conf
  fi
  echo "$LICENSEKEY" > /opt/zimbra/conf/ZCSLicensekey
  chown zimbra:zimbra /opt/zimbra/conf/ZCSLicensekey
  chmod 644 /opt/zimbra/conf/ZCSLicensekey
fi

checkSkipActivation
if [ $SOFTWAREONLY = "yes" ]; then

	echo ""
	echo "Software Installation complete!"
	echo ""
	echo "Operations logged to $LOGFILE"
	echo ""

	exit 0
fi

if [ -e "$LOGFILE" ]; then
	LOG_DIR="/opt/zimbra/log"
	if [ ! -d "$LOG_DIR" ]; then
		mkdir -p "$LOG_DIR"
		chown zimbra:zimbra "$LOG_DIR"
	fi
	echo "Copying $LOGFILE to $LOG_DIR"
	cp -f $LOGFILE $LOG_DIR/
	chown zimbra:zimbra "$LOG_DIR/$(basename "$LOGFILE")"
fi
#
# Installation complete, now configure
#
if [ "x$DEFAULTFILE" != "x" ]; then
	/opt/zimbra/libexec/zmsetup.pl -c $DEFAULTFILE
else
	/opt/zimbra/libexec/zmsetup.pl
fi
RC=$?
if [ $RC -ne 0 ]; then
	exit $RC
fi
