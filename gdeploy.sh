#!/bin/bash
# https://github.com/pforret/gandi_deploy
# program by: Peter Forret <peter@forret.com>
PROGNAME=$(basename $0)
PREFIX=$(basename $0 .sh)
PROGVERSION="1.1"
PROGAUTHOR="Peter Forret <peter@forret.com>"
if [[ "$1" == "" ]] ; then
	#usage
	echo "#	$PROGNAME $PROGVERSION"
	echo "#	author: $PROGAUTHOR"
	echo "#	link: https://github.com/pforret/gandi_deploy"
	echo "$PROGNAME [init|commit|push|deploy|all|login|serve|domains]"
	echo "   init: initialize the Gandi Paas settings"
	echo " "
	echo "   all [renote]: commit, push and deploy this website"
	echo "   commit: git commit all local changes"
	echo "   push [remote]: git push to Gandi git server"
	echo "   deploy [remote|domain]: ssh deploy from git to live website"
	echo "   login: do ssh login to the Gandi host for this website"
	echo " "
	echo "   serve: run local devl website on localhost:8000"
	echo "   rnd: run local devl website on random port localhost:8000-8099"
	echo " "
	echo "   domains: get all hosted Gandi sites"
	exit 0
fi

if [[ -z $(which gandi) ]] ; then
	# Gandi CLI not yet installed
	CURRVERSION=$(curl -s https://raw.githubusercontent.com/Gandi/gandi.cli/master/gandi/cli/__init__.py | grep version | cut -d'=' -f2 | sed "s/'//g")
	echo "Install Gandi CLI in order to use this script (current version: $CURRVERSION)"
	echo "https://github.com/gandi/gandi.cli#installation"
	exit 0
fi

die(){
	echo "! $*"
	exit 1
}

# all files created go in a special folder
GTEMP=.gandi
if [[ ! -d $GTEMP ]] ;  then
	mkdir $GTEMP
	if [[ ! -d $GTEMP ]] ; then
		die "Cannot create folder [$GTEMP] - probably no write permissions"
	fi
fi

get_value(){
	local key=$1
	local default=$2
	local value=$(egrep "^$key" \
	| cut -d: -f2 \
	| sed 's/ //g')
	if [[ -z "$value" ]] ; then
		echo $default
	else
		echo $value
	fi
}

LIST_SERVERS=$GTEMP/list.servers.txt
list_servers(){
	if [[ -z "$1" ]] && [[ -s "$LIST_SERVERS" ]] ; then
		# cache exists and no forced update
		cat $LIST_SERVERS
	else
		  gandi paas list \
		| egrep "^name" \
		| cut -d ':' -f2 \
		| sed 's/ //g' \
		| sort \
		| tee $LIST_SERVERS
	fi

}

show_progress(){
	total_lines=$1
	update_lines=$(($total_lines / 500))
	lineno=0
	fullbar="================================================================================"
	barlength=${#fullbar}
	while read -r line; do 
		lineno=$(($lineno + 1))
		# for long log files, just update every $update_lines lines
		[[ $total_lines -gt 500 ]] && [[ $(($lineno % $update_lines)) -ne 1 ]] && continue
		percent=$(( 100 * $lineno / $total_lines))
		width=$(( $barlength * $lineno / $total_lines))
		if [[ $width -gt $barlength ]] ; then
			width=$barlength
		fi
		if [[ $width -lt 1 ]] ; then
			width=1
		fi
		barpart=$(echo $fullbar | cut -c1-$width)
		printf "[%${width}s] $percent%%\r" $barpart
	done
}

get_server_info(){
	server=$1
	SERVER_INFO=$GTEMP/server.$server.info.txt
	if [[ -z "$2" ]] && [[ -s "$SERVER_INFO" ]] ; then
		# cache exists and no forced update
		cat $SERVER_INFO
	else
		  gandi paas info $server \
		| tee $SERVER_INFO
	fi
}

list_server_domains(){
	server=$1
	LIST_SERVER_DOMAINS=$GTEMP/server.$server.domains.txt
	if [[ -z "$2" ]] && [[ -s "$LIST_SERVER_DOMAINS" ]] ; then
		# cache exists and no forced update
		cat $LIST_SERVER_DOMAINS
	else
		  get_server_info $server \
		| grep vhost \
		| cut -d: -f2 \
		| sed 's/ //g' \
		| sort \
		| tee $LIST_SERVER_DOMAINS
	fi
}

list_remotes(){
	# no need to cahe, very fast
	  git remote -v \
	| awk '/(fetch)/ {print $1,$2}'
}

add_to_ignore(){
	path=$1
	if [[ -z $(grep $path .gitignore) ]] ; then
		echo $path >> .gitignore
	fi
}

get_remote_info(){
	if [[ -z "$1" ]] ; then
		REMOTE=gandi
	else
		REMOTE=$1
	fi

	INFO_REMOTE=$GTEMP/remote.$REMOTE.info.txt
	if [[ -z "$2" ]] && [[ -s "$INFO_REMOTE" ]] ; then
		# cache exists and no forced update
		cat $INFO_REMOTE
	else
		GIT_URL=$(list_remotes | egrep "^$REMOTE" | cut -d' ' -f2)
		if [[ -n "$GIT_URL" ]] ; then
			echo "remote : $REMOTE" > $INFO_REMOTE
			echo "generated : $(date)" >> $INFO_REMOTE
			echo "git : $GIT_URL" >> $INFO_REMOTE
			DOMAIN=$(basename $GIT_URL .git)
			if [[ $DOMAIN == *"."* ]] ; then
				# probably a domain
				echo "domain : $DOMAIN" >> $INFO_REMOTE
				IPADR=$(nslookup $DOMAIN 8.8.8.8 | grep -v 8.8.8.8 | grep Address | cut -d: -f2 | sed 's/ //g')
				if [[ -n "$IPADR" ]] ; then
					echo "IP : $IPADR" >> $INFO_REMOTE
					REVERSE=$(nslookup $IPADR 8.8.8.8 | grep -v 8.8.8.8 | grep name | cut -d= -f2 | sed 's/ //g')
					echo "reverse : $REVERSE" >> $INFO_REMOTE
				else
					echo "no IP/nslookup info"
				fi
				gandi vhost info $DOMAIN >> $INFO_REMOTE
			else
				# not a domain
				echo "[$DOMAIN] is not a domain"
			fi
		else
			echo "Current remotes = " $(list_remotes)
			die "remote [$REMOTE] not found" 
		fi
	fi
}

# 2nd param is always  the git remote - default 'gandi'
if [[ -z "$2" ]] ; then
	REMOTE=gandi
else
	REMOTE=$2
fi

## INITIALIZE ALL THE DATA

if [[ "$1" == "init" ]] ; then
	echo "## $PROGNAME init"
	add_to_ignore $PROGNAME
	add_to_ignore $GTEMP
	for server in $(list_servers force); do
		echo "# server $server"
		get_server_info $server force > /dev/null
		list_server_domains $server force  > /dev/null
	done
	for remote in $(list_remotes | cut -d' ' -f1); do
		echo "# remote $remote"
		get_remote_info $remote force
	done
	exit 0
fi

if [[ ! -s $LIST_SERVERS ]] ; then
	echo "  run [$0 init] first to enable the other functions"
	exit 0
fi

DOMAIN=$(get_remote_info $REMOTE | get_value domain)
#echo "#DOMAIN: $DOMAIN"
WEBHOST=$(get_remote_info $REMOTE | get_value paas_name)
if [[ "$WEBHOST" == "" ]] ; then
	die "WARNING: cannot find the Gandi Paas host for this domain [$DOMAIN] "
fi

GITHOST=$(get_server_info $WEBHOST | get_value git_server)
FTPHOST=$(get_server_info $WEBHOST | get_value sftp_server)
SSHLOGIN=$(get_server_info $WEBHOST | get_value console)
USERNAME=$(echo $SSHLOGIN | cut -d@ -f1)
SSHHOST=$(echo $SSHLOGIN | cut -d@ -f2)
#echo "#USER: $USERNAME"


git_deploy(){
	local FLOG=$GTEMP/$DOMAIN.deploy.log
	local FTOT=$GTEMP/$DOMAIN.deploy.info.txt
	local TSTART=$(date '+%s')
	echo ... LOG in [$FLOG]
	if [[ ! -s $FTOT ]] ; then
		# estimate by counting # files
		local TOTAL_LINES=$(find . -type f | wc -l | sed 's/ //g')
	else
		# estimate by taking last count
		local TOTAL_LINES=$(cat $FTOT | get_value lines 1)
		if [[ $TOTAL_LINES -lt 10 ]] ; then
			local TOTAL_LINES=$(find . -type f | wc -l | sed 's/ //g')
		fi
	fi
	local ESTIM_SECS=$(cat $FTOT | get_value secs $((TOTAL_LINES / 100)) )
	local ESTIM_MINS=$(($ESTIM_SECS / 60))
	echo ... Estimated time: $ESTIM_SECS secs - $ESTIM_MINS min
	ssh $USERNAME@$GITHOST deploy $DOMAIN.git 2>&1 \
	| tee $FLOG \
	| show_progress $TOTAL_LINES
	printf "\n"

	local TSTOP=$(date '+%s')
	local NBLINES=$(< $FLOG wc -l | sed 's/ //g')
	local NBSECS=$(( $TSTOP - $TSTART)) 
	echo "lines : $NBLINES" > $FTOT
	echo "secs : $NBSECS"	>> $FTOT
	local LPS=$(($NBLINES / $NBSECS))
	echo $NBLINES lines in $NBSECS seconds - $LPS lines/second 
	echo -------------------------------
	tail -4 $FLOG
	echo -------------------------------
}

git_push(){
	local FLOG=$GTEMP/$DOMAIN.push.log
	local FTOT=$GTEMP/$DOMAIN.push.info.txt
	local TSTART=$(date '+%s')
	echo ... LOG in [$FLOG]
	local TOTAL_LINES=$(git status | wc -l | sed 's/ //g')
	local ESTIM_SECS=$((TOTAL_LINES / 2))
	echo ... Estimated time: $ESTIM_SECS secs
	git push $REMOTE master 2>&1 \
	| tee $FLOG \
	| show_progress $TOTAL_LINES
	printf "\n"

	local TSTOP=$(date '+%s')
	local NBLINES=$(< $FLOG wc -l | sed 's/ //g')
	local NBSECS=$(( $TSTOP - $TSTART)) 
	local LPS=$(($NBLINES / $NBSECS))
	echo "lines : $NBLINES" > $FTOT
	echo "secs : $NBSECS"	>> $FTOT
	echo "lines/sec : $LPS"	>> $FTOT
	echo $NBLINES lines in $NBSECS seconds - $LPS lines/second 
	echo -------------------------------
	tail -4 $FLOG
	echo -------------------------------

}

case "$1" in
	commit|1)
		echo "## git commit (local)"
		git commit -a
		;;

	push|2)
		echo "## git push -> $GITHOST ($REMOTE)"
		git_push
		;;

	deploy|3)
		echo "## git deploy -> $FTPHOST ($DOMAIN)"
		git_deploy
		echo Check http://$DOMAIN/
		;;

	full|all)
		git commit -a \
		&& git_push \
		&& git_deploy
		echo Check http://$DOMAIN/
		;;

	login|ssh)
		echo "## login as $USERNAME"
		echo "## get your password from your password manager!"
		gandi paas console $WEBHOST
		;;

	serve|8000|http)
		PORT=8000
		if [[ -d htdocs ]] ; then
			echo "## served as http://localhost:$PORT!"
			php -S localhost:$PORT -t htdocs/
		else
			echo "!! there is no htdocs folder!"
			echo "## (maybe you need to to 'ln -s public htdocs')"
		fi

		;;

	serve2|random|rnd)
		PORT=$(( 8000 + $RANDOM % 100 ))
		if [[ -d htdocs ]] ; then
			echo "## served as http://localhost:$PORT!"
			## following only works on MacOS
			bash -c "sleep 1; open http://localhost:$PORT/"
			php -S localhost:$PORT -t /htdocs
		else
			echo "!! there is no htdocs folder!"
			echo "## (maybe you need to to 'ln -s public htdocs')"
		fi

		;;

	domains)
	for server in $(list_servers force); do
		echo "# server $server"
		list_server_domains $server | egrep -v "testmyurl.ws|testing-url.ws" |  awk '{split($0,a,"."); print a[3] a[2] a[1] "     |"  $0}' | sort | cut -d'|' -f2
		echo " "
	done
		;;

	check)
		echo "============="
		echo "## git status"
		git status
		echo "## git remote"
		git remote -v show

esac
