# gandi_deploy

script to work easily with gandi.net paas git deployment (bash)

## Installation

* make sure [https://cli.gandi.net/][Gandi CLI] is installed correctly

	`gandi account info` (should not give an error)

* clone this repository somewhere on your machine

	`git clone https://github.com/pforret/gandi_deploy.git`

* from any of your Gandi git-managed project, add a symbolic link to gdeploy.sh

	`ln -s /path/to/gandi_deploy/gdeploy.sh .`

* run gdeploy.sh init, type the domain name of your site if it cannot be guessed from the folder name

	`./gdeploy.sh init`

* to preview your site on your local server

	`./gdeploy.sh serve` (on port 8000)
	
	`./gdeploy.sh rnd` (on a random port between 8000 and 8099)

* to publish your site, run this to commit, push and deploy

	`./gdeploy.sh all`

## Usage 
    gdeploy.sh [init|commit|push|deploy|all|login|serve|domains]
      domains: get all hosted Gandi sites
      init: initialize the Gandi Paas settings
      all: commit, push and deploy this website
      commit: git commit all local changes
      push: git push to Gandi git server
      deploy: ssh deploy from git to live website
      login: do ssh login to the Gandi host for this website
      serve: do ssh login to the Gandi host for this website


[Gandi CLI]: https://cli.gandi.net/