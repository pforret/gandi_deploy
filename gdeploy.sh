#!/bin/bash
PROGNAME=$(basename $0)

if [[ "$1" == "" ]] ; then
	#usage
	echo "$PROGNAME [init|push|login]"
	echo "   init: initialize the Gandi Paas settings"
	echo "   push: commit, push and deploy this website"
	echo "   login: do ssh login to the Gandi host for this website"
	exit 0
fi

DOMINFO=.gandi.domain.info.txt
if [[ "$1" == "init" ]] ; then
	FOLDER=$(pwd)
	BNAME=$(basename $FOLDER)
	if [[ "$BNAME" =~ "." ]] ; then
		#contains . - could be domain name
		DEFDOMAIN=$BNAME
		echo "What is the domain name of the site you want to deploy? (empty = $DEFDOMAIN)" 
	else
		DEFDOMAIN= 
		echo "What is the domain name of the site you want to deploy?" 
	fi
	read DOMAIN
	if [[ -z "$DOMAIN" ]] ; then
		DOMAIN=$DEFDOMAIN
	fi
	if [[ "$DOMAIN" =~ "." ]] ; then
		#contains . - could be domain name
		echo "domain : $DOMAIN" > $DOMINFO
		gandi vhost info $DOMAIN >> $DOMINFO
	else
		echo "[$DOMAIN] doesn't look like a valid domain name - we need something like www.example.com" 
		exit 1
	fi
fi

if [[ ! -f $DOMINFO ]] ; then
	echo "  run [$0 init] first to enable the other functions"
	exit 0
fi

DOMAIN=$(grep domain $DOMINFO | cut -d: -f2 | sed 's/ //g')
echo "#SITE: $DOMAIN"
 
WEBHOST=$(grep paas_name $DOMINFO | cut -d: -f2 | sed 's/ //g')
if [[ "$WEBHOST" == "" ]] ; then
	echo "WARNING: cannot find the Gandi Paas host for this domain [$DOMAIN] "
	exit 1
else
	echo "#PAAS: $WEBHOST"
fi

HOSTINFO=.gandi.$WEBHOST.info.txt
if [[ ! -f $HOSTINFO ]] ; then
	gandi paas info $WEBHOST > $HOSTINFO
fi

GITHOST=$(grep git_server $HOSTINFO | cut -d: -f2 | sed 's/ //g')
FTPHOST=$(grep sftp_server $HOSTINFO | cut -d: -f2 | sed 's/ //g')
SSHLOGIN=$(grep console $HOSTINFO | cut -d: -f2 | sed 's/ //g')
USERNAME=$(echo $SSHLOGIN | cut -d@ -f1)
SSHHOST=$(echo $SSHLOGIN | cut -d@ -f2)
echo "#USER: $USERNAME"


if [[ "$1" == "push" ]] ; then
	git commit -a \
	&& git push gandi \
	&& ssh $USERNAME@$GITHOST deploy $DOMAIN.git
fi

if [[ "$1" == "domains" ]] ; then
	gandi paas list \
	| grep vhost \
	| cut -d: -f2 \
	| sed 's/ //g' \
	| sort
fi

if [[ "$1" == "login" ]] ; then
	gandi paas info $WEBHOST | grep console
	gandi paas console $WEBHOST
fi

