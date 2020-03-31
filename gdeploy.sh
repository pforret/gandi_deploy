#!/bin/bash
# https://github.com/pforret/gandi_deploy
# program by: Peter Forret <peter@forret.com>
PROGNAME=$(basename $0)

if [[ "$1" == "" ]] ; then
	#usage
	echo "$PROGNAME [init|commit|push|deploy|all|login|serve|domains]"
	echo "   domains: get all hosted Gandi sites"
	echo "   init: initialize the Gandi Paas settings"
	echo "   all: commit, push and deploy this website"
	echo "   commit: git commit all local changes"
	echo "   push: git push to Gandi git server"
	echo "   deploy: ssh deploy from git to live website"
	echo "   login: do ssh login to the Gandi host for this website"
	echo "   serve: do ssh login to the Gandi host for this website"
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
		gandi vhost info $DOMAIN >>	$DOMINFO
		git remote add gandi git+ssh://$USERNAME@$GITHOST/$DOMAIN.git
		echo $PROGNAME >> .gitignore
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

case "$1" in
	commit|1)
		echo "## git commit (local)"
		git commit -a
		;;

	push|2)
		echo "## git push -> $GITHOST"
		git push gandi master
		;;

	deploy|3)
		echo "## git deploy -> $FTPHOST"
		ssh $USERNAME@$GITHOST deploy $DOMAIN.git
		;;

	full|all)
		git commit -a \
		&& git push gandi master \
		&& ssh $USERNAME@$GITHOST deploy $DOMAIN.git
		;;

	login)
		echo "## login as $USERNAME"
		echo "## get your password from your password manager!"
		gandi paas console $WEBHOST
		;;

	serve|8000|http)
		PORT=8000
		echo "## served as http://localhost:$PORT!"
		php -S localhost:$PORT -t htdocs/
		;;

	serve2|random|rnd)
		PORT=$(( 8000 + $RANDOM % 100 ))
		echo "## served as http://localhost:$PORT!"
		## following only works on MacOS
		bash -c "sleep 1; open http://localhost:$PORT/"
		php -S localhost:$PORT -t htdocs/
		;;

	domains)
		gandi paas list \
		| grep vhost \
		| cut -d: -f2 \
		| sed 's/ //g' \
		| sort
		;;

	check)
		echo "============="
		echo "## git status"
		git status
		echo "## git remote"
		git remote -v show

esac
