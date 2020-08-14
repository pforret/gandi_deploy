#!/bin/bash
script_fname=$(basename "$0")
script_author="Peter Forret <peter@forret.com>"
script_url="https://github.com/pforret/gandi_deploy"
if [[ -z $(dirname "$0") ]]; then
  # script called without path ; must be in $PATH somewhere
  # shellcheck disable=SC2230
  script_install_path=$(which "$0")
else
  # script called with relative/absolute path
  script_install_path="$0"
fi
script_install_path=$(readlink "$script_install_path") # when script was installed with e.g. basher
script_install_folder=$(dirname "$script_install_path")
script_version="?.?.?"
[[ -f "$script_install_folder/VERSION.md" ]] && script_version=$(cat "$script_install_folder/VERSION.md")


if [[ "$1" == "" ]] ; then
	#usage
	echo "# $script_fname $script_version"
	echo "# author: $script_author"
	echo "# website: $script_url"
	echo "> usage: $script_fname [init|commit|push|deploy|all|login|serve|domains] (target)"
	echo "  init     : initialize the Gandi Paas settings"
	echo "  all [remote]: commit, push and deploy this website"
	echo "  commit   : git commit all local changes"
	echo "  push [remote]: git push to Gandi git server"
	echo "  deploy [remote|domain]: ssh deploy from git to live website"
	echo "  login    : do ssh login to the Gandi host for this website"
	echo "  serve    : run local devl website on localhost:8000"
	echo "  rnd      : run local devl website on random port localhost:8000-8099"
	echo "  consoles : get 'gandi paas console ...' command for every domain"
	echo "  domains  : get all hosted Gandi sites"
	exit 0
fi

# shellcheck disable=SC2230
if [[ -z $(which gandi) ]] ; then
	# Gandi CLI not yet installed
	gandicli_version=$(curl -s https://raw.githubusercontent.com/Gandi/gandi.cli/master/gandi/cli/__init__.py | grep version | cut -d'=' -f2 | sed "s/'//g")
	echo "Install Gandi CLI in order to use this script (current version: $gandicli_version)"
	echo "https://github.com/gandi/gandi.cli#installation"
	exit 0
fi

die(){
	echo "! $*"
	exit 1
}

# all files created go in a special folder
cache_folder=.gandi
if [[ ! -d $cache_folder ]] ;  then
	mkdir $cache_folder
	if [[ ! -d $cache_folder ]] ; then
		die "Cannot create folder [$cache_folder] - probably no write permissions"
	fi
fi

get_value(){
	local key=$1
	local default=$2
	local value
	value=$(grep -E "^$key" \
					| cut -d: -f2 \
					| sed 's/ //g')
	if [[ -z "$value" ]] ; then
		echo "$default"
	else
		echo "$value"
	fi
}

get_value_from_file(){
	#local file=$1
	#local key=$2
	#local def=$3
	if [[ -f "$1" ]] ; then
		found=$(< "$1" awk -F: -v key="$2" '$1 == key {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
		if [[ -z "$found" ]] ; then
			echo "$3"
		else
			echo "$found"
		fi
	else 
		echo "$3"
	fi 
}

LIST_SERVERS=$cache_folder/list.servers.txt
list_servers(){
	if [[ -z "$1" ]] && [[ -s "$LIST_SERVERS" ]] ; then
		# cache exists and no forced update
		cat $LIST_SERVERS
	else
		  gandi paas list \
		| grep -E "^name" \
		| cut -d ':' -f2 \
		| sed 's/ //g' \
		| sort \
		| tee $LIST_SERVERS
	fi

}

show_progress(){
	local counter_id=$1
	local fallback=$2
	local file_output="$cache_folder/$counter_id.deploy.log"
	local file_stats="$cache_folder/$counter_id.deploy.txt"
	local lines_output
	local lines_per_second
	local time_finished
	local time_passed
	local time_started
	local total_lines
	local total_seconds
	local update_every

	total_lines=$(get_value_from_file "$file_stats" lines "$fallback")
	total_seconds=$(get_value_from_file "$file_stats" secs "$fallback")
	echo "$counter_id: $total_seconds seconds (estimated)"
	update_every=$((total_lines / 500))
	[[ update_every -lt 2 ]] && update_every=2
	time_started=$(date '+%s')
	  tee "$file_output" \
	| awk -v total_lines="$total_lines" -v update_every="$update_every" '
		BEGIN { 
			fullbar="================================================================================"
			maxlen=length(fullbar) 
		} 
		(NR % update_every) == 1 {
			#print NR, $0
			percent=100*NR/total_lines;
			width=maxlen*NR/total_lines;
			if(width>maxlen)	width=maxlen
			if(width<1)			width=1
			partial=substr(fullbar,1,width)
			printf("\r[%s] %d%% " , partial , percent)
			fflush()
		}
		END {
			printf "\n"
		}
		'
	time_finished=$(date '+%s')
	lines_output=$(< "$file_output" wc -l | sed 's/ //g')
	time_passed=$(( time_finished - time_started))
	lines_per_second=$((lines_output / time_passed))
	echo "lines:$lines_output" > "$file_stats"
	echo "secs:$time_passed"	>> "$file_stats"
	echo "$counter_id: $time_passed seconds (real)"
	echo "$counter_id: $lines_output lines @ $lines_per_second lines/second "
	echo -------------------------------
	tail -4 "$file_output"
	echo -------------------------------

}

get_cache_server(){
	server=$1
	local cache_server="$cache_folder/server.$server.info.txt"
	if [[ -z "$2" ]] && [[ -s "$cache_server" ]] ; then
		# cache exists and no forced update
		cat "$cache_server"
	else
		  gandi paas info "$server" \
		| tee "$cache_server"
	fi
}

cache_domains(){
	server=$1
	local cache_domains="$cache_folder/server.$server.domains.txt"
	if [[ -z "$2" ]] && [[ -s "$cache_domains" ]] ; then
		# cache exists and no forced update
		cat "$cache_domains"
	else
		  get_cache_server "$server" \
		| grep vhost \
		| cut -d: -f2 \
		| sed 's/ //g' \
		| sort \
		| tee "$cache_domains"
	fi
}

list_remotes(){
	# no need to cache, very fast
	  git remote -v \
	| awk '/(fetch)/ {print $1,$2}'
}

add_to_ignore(){
	path=$1
	if ! grep -q "$path" .gitignore ; then
		echo "$path" >> .gitignore
	fi
}

get_remote_info(){
	if [[ -z "$1" ]] ; then
		REMOTE=gandi
	else
		REMOTE=$1
	fi

	local cache_remote="$cache_folder/remote.$REMOTE.info.txt"
	if [[ -z "$2" ]] && [[ -s "$cache_remote" ]] ; then
		# cache exists and no forced update
		cat "$cache_remote"
	else
		GIT_URL=$(list_remotes | grep -E "^$REMOTE" | cut -d' ' -f2)
		if [[ -n "$GIT_URL" ]] ; then
			echo "remote : $REMOTE" > "$cache_remote"
			echo "generated : $(date)" >> "$cache_remote"
			echo "git : $GIT_URL" >> "$cache_remote"
			DOMAIN=$(basename "$GIT_URL" .git)
			if [[ "$DOMAIN" == *"."* ]] ; then
				# probably a domain
				echo "domain : $DOMAIN" >> "$cache_remote"
				IPADR=$(nslookup "$DOMAIN" 8.8.8.8 | grep -v 8.8.8.8 | grep Address | cut -d: -f2 | sed 's/ //g')
				if [[ -n "$IPADR" ]] ; then
					echo "IP : $IPADR" >> "$cache_remote"
					REVERSE=$(nslookup "$IPADR" 8.8.8.8 | grep -v 8.8.8.8 | grep name | cut -d= -f2 | sed 's/ //g')
					echo "reverse : $REVERSE" >> "$cache_remote"
				else
					echo "no IP/nslookup info"
				fi
				gandi vhost info "$DOMAIN" >> "$cache_remote"
			else
				# not a domain
				echo "[$DOMAIN] is not a domain"
			fi
		else
			echo "Current remotes = $(list_remotes)"
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
	echo "## $script_fname init"
	add_to_ignore "$script_fname"
	add_to_ignore "$cache_folder"
	for server in $(list_servers force); do
		echo "# server $server"
		get_cache_server "$server" force > /dev/null
		cache_domains "$server" force  > /dev/null
	done
	for remote in $(list_remotes | cut -d' ' -f1); do
		echo "# remote $remote"
		get_remote_info "$remote" force
	done
	exit 0
fi

if [[ ! -s $LIST_SERVERS ]] ; then
	echo "  run [$0 init] first to enable the other functions"
	exit 0
fi

DOMAIN=$(get_remote_info "$REMOTE" | get_value domain)
#echo "#DOMAIN: $DOMAIN"
WEBHOST=$(get_remote_info "$REMOTE" | get_value paas_name)
if [[ "$WEBHOST" == "" ]] ; then
	die "WARNING: cannot find the Gandi Paas host for this domain [$DOMAIN] "
fi

GITHOST=$(get_cache_server "$WEBHOST" | get_value git_server)
FTPHOST=$(get_cache_server "$WEBHOST" | get_value sftp_server)
SSHLOGIN=$(get_cache_server "$WEBHOST" | get_value console)
USERNAME=$(echo "$SSHLOGIN" | cut -d@ -f1)
#SSHHOST=$(echo "$SSHLOGIN" | cut -d@ -f2)
#echo "#USER: $USERNAME"


git_deploy(){
	local TOTAL_LINES
	TOTAL_LINES=$(find . -type f | wc -l | sed 's/ //g')
	# shellcheck disable=SC2029
	ssh "$USERNAME@$GITHOST" deploy "$DOMAIN.git" 2>&1 \
	| show_progress git_deploy "$TOTAL_LINES"
}

git_push(){
	local TOTAL_LINES
	TOTAL_LINES=$(git status | wc -l | sed 's/ //g')
	git push --verbose "$REMOTE" master 2>&1 \
	| show_progress git_push "$TOTAL_LINES"
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
		echo "Check http://$DOMAIN/"
		;;

	full|all)
		git commit -a \
		&& git_push \
		&& git_deploy
		echo "Check http://$DOMAIN/"
		;;

	login|ssh)
		echo "## login as $USERNAME"
		echo "## get your password from your password manager!"
		gandi paas console "$WEBHOST"
		;;

	serve|8000|http)
		PORT=8000
		if [[ -d htdocs ]] ; then
			echo "## served as http://localhost:$PORT!"
			php -S "localhost:$PORT" -t htdocs/
		else
			echo "!! there is no htdocs folder!"
			echo "## (maybe you need to do 'ln -s public htdocs')"
		fi
		;;

	serve2|random|rnd)
		PORT=$(( 8000 + RANDOM % 100 ))
		if [[ -d htdocs ]] ; then
			echo "## served as http://localhost:$PORT!"
			## following only works on MacOS
			bash -c "sleep 3; open http://localhost:$PORT/"
			php -S localhost:$PORT -t htdocs/
		else
			echo "!! there is no htdocs folder!"
			echo "## (maybe you need to to 'ln -s public htdocs')"
		fi
		;;

	domains)
		for server in $(list_servers force); do
			echo "# server $server"
			cache_domains "$server" \
			| grep -E -v "testmyurl.ws|testing-url.ws" \
			| awk '{split($0,a,"."); print a[3] a[2] a[1] "     |"  $0}' \
			| sort \
			| cut -d'|' -f2
			echo " "
		done
		;;

	consoles)
		for server in $(list_servers force); do
			cache_domains "$server" \
			| grep -E -v "testmyurl.ws|testing-url.ws" \
			| awk -v server="$server" '{ printf "%-30s : gandi paas console %s\n", $0, server }'
		done \
		| sort
		;;

	check)
		echo "============="
		echo "## git status"
		git status
		echo "## git remote"
		git remote -v show
		;;

	test)
		ping -c 40 www.google.com | show_progress test_ping 29
		;;

	*)
		die "Unknown $script_fname command [$1]"

esac
