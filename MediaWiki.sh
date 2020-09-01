#!/bin/bash

# upload the script to server `cp MediaWiki.sh root@12.34.56.78:/root`
# Run the script as root with `bash Mediawiki.sh`
##### TODOs
## Letsencrypt check domain name is registered to ip address being used.
## Make sure stapling off for selfsigned
## Checks for input data - undo redo.
## Incase reboot required - start script when boot back into server and rm when finished!
## Edit/Create LocalSettings.php file so no need for webadmin.

# 1 Check ubuntu 20.04 and give warning if not!
########### give warning before running script - ask for 'yes' to continue!

CHECK_UBUNTU=$(lsb_release -i | awk '{print $3}')
CHECK_UBUNTU2004=$(lsb_release -r | awk '{print $2}')
if [ $CHECK_UBUNTU == "Ubuntu" ]
    then
        if [ $CHECK_UBUNTU2004 == "20.04" ]
            then
                printf "You are running $CHECK_UBUNTU $CHECK_UBUNTU2004\n\n"
            else
                echo "are you sure your running ubuntu 20.04?"
                echo $CHECK_UBUNTU $CHECK_UBUNTU2004
                printf "This script is intended for Ubuntu 20.04\nExiting script\n"
                exit 1
        fi
     else
         printf "This script is intended for ubuntu 20.04!\nScript exiting\n"  
         exit 1
fi

printf "\nThis is a script in development!\n"
printf "For quickly installing the basic's of mediawiki on a ubuntu 20.04 server\n"
printf "This script is expecting a clean install of a server to run on.\n"
printf "Enter \"yes\" to continue with script or press anykey to exit!\n"

printf "\n
What this script will do:\n
\n\t1. Setup basic firewall with ufw and allow port 22 for ssh
\n\t2. Update system and check if reboot required.
\n\t3. Install software packages:
\t\t apache2 
\t\t mysql-server 
\t\t php 
\t\t php-mysql 
\t\t libapache2-mod-php 
\t\t php-xml 
\t\t php-mbstring
\t\t mediawiki-1.34.2
\n\t4. Take Domain-name info - used for renaming files
\n\t 5a. Download, checksum, extract to path: \'MediaWiki-1.34.2\'
\t 5b. Download, checksum and move to path file \'apache.conf.backup\' - template for configuring apache
\t 5c. Download, checksum and move to path file \'ssl-params.conf\' - contains are ssl parameters
\n\t6. Create self signed ssl keys
\n\t7. Create Database for mediawiki
\n\t8. Configure Apache
\n\t9. Allow ports 80 and 443 pass firewall
\n\t10. Will echo/display details required for finishing media setup on web browser
\n\n\tPlease type \"yes\" case sensitive to continue!\n
\tJust Press Enter to Exit Script!\n
\tEnter anwser here :"

read anypress

if [ -z "$anypress" ]
    then
        printf "Exiting Script!"
        sleep 1
        exit 1
    else
        if [ $anypress == "yes" ]
        then 
            printf "starting script ....."
            sleep 1
        else
            printf "Exiting Script!"
            sleep 1
            exit 1
        fi
fi


# 1. setup basic firewall
########### Setup Basic Firewall allow port 22 for ssh
# for reboot may want to check if UFW enabled or not, before running again.
# Maybe for later - add check to make sure sshd is listening on port 22

UFW_CHECK=$(ufw status | head -n 1 | awk '{print $2}')
if [ $UFW_CHECK == "inactive" ]; then
        ufw allow 22/tcp
        ufw enable << EOF 
`#Command may disrupt existing ssh connections. Proceed with operation (y|n)?`y 
EOF
fi

# 2. update system and check if reboot required.
########### check system up to date 
apt update && apt upgrade -y && apt autoremove -y

# reboot if reboot required
# will test to see if file "/var/run/reboot-required" exists
if [ -f /var/run/reboot-required ]
    then 
        reboot
    else
        continue
fi



# 3
########### Install packages
# checksum of mediawiki download.
# add patch and check sig
# when downloading from github add(?raw=true) at the end or you will download a html page.

# Install main packages from ubuntu repos
apt install apache2 mysql-server php php-mysql libapache2-mod-php php-xml php-mbstring -y

#delete defaults
rm /etc/apache2/sites-available/*

# 4
####### take domain name - after reboot section - for renaming files
printf "What domain name are you planning to give your wiki?\nEnter Domain name here:"
read DOMAIN_NAME_WIKI
printf "Your selected domain name is (example:greenhat.info) :$DOMAIN_NAME_WIKI"

# 5a
# download and checksums of media wiki
MediaWiki_Sum="f2c3c3380a2d60baeb619784cb5a20ce"
wget https://releases.wikimedia.org/mediawiki/1.34/mediawiki-1.34.2.tar.gz -P /tmp/
# Check md5sum of download and extract to directory
MediaWiki_Sum_CHECK="$(md5sum /tmp/mediawiki-1.34.2.tar.gz | awk '{print $1}')"

if [ $MediaWiki_Sum == $MediaWiki_Sum_CHECK ] ;
    then 
        echo "checksum checks out:"
        tar -zxvf /tmp/mediawiki-1.34.2.tar.gz -C /var/www/html/
        mv /var/www/html/mediawiki-1.34.2 /var/www/html/mediawiki
        rm /tmp/mediawiki-1.34.2.tar.gz
    else
        echo "Checksum not checking out"
        printf "looking for $MediaWiki_Sum but found $MediaWiki_Sum_CHECK"
        read -r -p $" Press Enter to Exit Script"
        exit 1
fi

# Download and checksum of mediawiki patch
MediaWiki_Patch_Sum="8dd76233188bab7b4698175552e695ee"
wget https://releases.wikimedia.org/mediawiki/1.34/mediawiki-1.34.2.patch.gz -P /tmp/
MediaWiki_Patch_Sum_CHECK="$(md5sum /tmp/mediawiki-1.34.2.patch.gz | awk '{print $1}')"
if [ $MediaWiki_Patch_Sum == $MediaWiki_Patch_Sum_CHECK ] ;
    then 
        echo "checksum checks out:"
        gunzip -c mediawiki-1.34.2.patch.gz > /var/www/html/mediawiki/mediawiki.patch
    else
        echo "Checksum not checking out"
        printf "looking for $MediaWiki_Patch_Sum but found $MediaWiki_Patch_Sum_CHECK"
        read -r -p $" Press Enter to Exit Script"
        exit 1
fi

# 5b
# Checksums for apache.conf.backup
# md5sum:   "7b2f82ee8aecd40ae23194ff500f28db" apache.conf.backup
# sha256sum: "464603f11b89250fa01f84fcb79b9249dd544eda58a72646edeec891f0f67e2e"  apache.conf.backup
APACHE_CONF_MD5_SUM="7b2f82ee8aecd40ae23194ff500f28db"

# Get files and check checksums - and change names and directorys
# Download /etc/apache2/sites-available/greenhat.info.conf 
wget https://github.com/greenhatmonkey/MediaWiki_configs_4_script/blob/master/apache.conf.backup?raw=true

APACHE_CHECK="$(md5sum apache.conf.backup?raw=true | awk '{print $1}')"

if [ $APACHE_CHECK == $APACHE_CONF_MD5_SUM ] ;
    then 
        echo "checksum checks out:"
        mv apache.conf.backup?raw=true /etc/apache2/sites-available/$DOMAIN_NAME_WIKI.conf
    else
        echo "Checksum not checking out"
        printf "looking for $APACHE_CONF_MD5_SUM but found $APACHE_CHECK"
        read -r -p $" Press Enter to Exit Script"
        exit 1
fi

# 5c
# Checksums for ssl-params.conf
# md5sum: "a35f64f92e457cdea2f7a98564b0700f"  ssl-params.conf
# sha256sum "748a5036509cc855396fb73bda36b6c057658fb97cc34e9c52330314a1424c54"  ssl-params.conf
SSL_PARAMS_MD5_SUM="a35f64f92e457cdea2f7a98564b0700f"

# /etc/apache2/conf-available/ssl-params.conf can be downloaded and checksum checked.
wget https://github.com/greenhatmonkey/MediaWiki_configs_4_script/blob/master/ssl-params.conf?raw=true

SSLPARAM_CHECK="$(md5sum ssl-params.conf?raw=true | awk '{print $1}')"

if [ $SSLPARAM_CHECK == $SSL_PARAMS_MD5_SUM ] ;
    then 
        echo "checksum checks out:"
        mv ssl-params.conf?raw=true /etc/apache2/conf-available/ssl-params.conf
    else
        echo "Checksum not checking out"
        printf "looking for $SSLPARAM_CHECK but found $SSL_PARAMS_MD5_SUM"
        read -r -p $" Press Enter to Exit Script"
        exit 1
fi




# 6
############ Database setup
# Save data for later to give to user for final setup from web
printf "Data needed to setup database for mediawiki"
printf "Data will be displayed in clear print at end of script\n to be used with web portal final mediawiki setup.\n"
echo "Select a username for database: "
read USERBASE
printf "Select a password for user $USERBASE: "
read DATAPASS
printf "Select a database name: (wikimedia)"
read DATANAME

mysql -u root <<MYSQL_SCRIPT
CREATE USER '$USERBASE'@'localhost' IDENTIFIED BY '$DATAPASS';
CREATE DATABASE $DATANAME;
use $DATANAME;
GRANT ALL ON $DATANAME.* TO '$USERBASE'@'localhost';
MYSQL_SCRIPT



# 7
############## Creating keys and certs - selfsigned
# to keep tidy making directory for work
mkdir /root/tmp && cd /root/tmp

openssl genrsa -des3 -passout pass:hellopasswd -out server.pass.key 4096

openssl rsa -passin pass:hellopasswd -in server.pass.key -out server.key

openssl req -new -key server.key -out server.csr

openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

# move and rename keys 
mv /root/tmp/server.crt /etc/ssl/certs/$DOMAIN_NAME_WIKI.crt
mv /root/tmp/server.key /etc/ssl/private/$DOMAIN_NAME_WIKI.key







# 8
####### Configure and restart apache2 server

# ServerName = SERVER_NAME # greenhat.info
# ServerAdmin = SERVER_ADMIN # email address
# Redirect = SERVER_IP #
# ErrorLog Custom = ELCUSTOM #
# CustomLog access = ALCUSTOM #
# SSLCertificateFile = CERT.CRT # after path: /etc/ssl/certs/
# SSLCertificateKeyFile = CERT.KEY # after path: /etc/ssl/private/

# need to fix this if we add domain-name entrie:
PFILE=/etc/apache2/sites-available/$DOMAIN_NAME_WIKI.conf

# ServerAdmin = SERVER_ADMIN # email address
printf "\nEnter admin Email: "
read SERVER_ADMIN_VAR
# sed email address
sed -i "s/SERVER_ADMIN/$SERVER_ADMIN_VAR/g" $PFILE

# Redirect = SERVER_IP #
SERVER_IP_VAR=$(curl ifconfig.me)

# add domain name as server name
sed -i "s/SERVER_NAME/$DOMAIN_NAME_WIKI/g" $PFILE

# server ip for redirect to https
sed -i "s/SERVER_IP/$SERVER_IP_VAR/g" $PFILE

# error log named after domainname
sed -i "s/ELCUSTOM/$DOMAIN_NAME_WIKI/g" $PFILE
# error log named after domainname
sed -i "s/ALCUSTOM/$DOMAIN_NAME_WIKI/g" $PFILE
# cert named after domain
sed -i "s/CERT.CRT/$DOMAIN_NAME_WIKI.crt/g" $PFILE
# key named after domain
sed -i "s/CERT.KEY/$DOMAIN_NAME_WIKI.key/g" $PFILE


# basics
a2enmod ssl

a2enmod headers

a2ensite $DOMAIN_NAME_WIKI

a2enconf ssl-params

# need check 'configtest' did not return error.
apache2ctl configtest

systemctl restart apache2

# 9
##### allow pass firewall
ufw allow 80/tcp
ufw allow 443/tcp

# 10 
# Message with database details and ip for website

printf "Please visit on a web browser the site $SERVER_IP_VAR to Complete your mediawiki install.\n"
printf '\e[1;31m%s\e[0m\n' "\tVisit $SERVER_IP_VAR on browser"
printf "\tYour Database name = $DATANAME\n"
printf "\tYour Database username = $USERBASE\n"
printf "\tYour Database PassWord for $USERBASE = $DATAPASS\n"




## 11 - this idea may not be the best idea right now!
#wget https://github.com/greenhatmonkey/MediaWiki_configs_4_script/blob/master/Sed.LocalSettings.php?raw=true
#
### Configuring LocalSettings.php
## "36689a3068d1f336626591d3f8278d8e" Sed.LocalSettings.php
## sha256sum "748a5036509cc855396fb73bda36b6c057658fb97cc34e9c52330314a1424c54"  ssl-params.conf
#LOCALSET_MD5_SUM="36689a3068d1f336626591d3f8278d8e"
#
#
#wget https://github.com/greenhatmonkey/MediaWiki_configs_4_script/blob/master/ssl-params.conf?raw=true
#
#LOCALSET_CHECK="$(md5sum Sed.LocalSettings.php?raw=true | awk '{print $1}')"
#
#if [ $LOCALSET_CHECK == $LOCALSET_MD5_SUM ] ;
#    then 
#        echo "checksum checks out:"
#        mv Sed.LocalSettings.php?raw=true /var/www/html/mediawiki/LocalSettings.php
#    else
#        echo "Checksum not checking out"
#        printf "looking for $LOCALSET_CHECK but found $LOCALSET_MD5_SUM"
#        read -r -p $" Press Enter to Exit Script"
#        exit 1
#fi
#
## file to edit path
#CFILE="/var/www/html/mediawiki/LocalSettings.php"
#
## add domain name as server name
#sed -i "s/SITENAME/$DOMAIN_NAME_WIKI/g" $CFILE
#
#sed -i "s/SITENAMESPACE/$DOMAIN_NAME_WIKI/g" $CFILE
#
#sed -i "s/MWSERVER/$SERVER_IP_VAR/g" $CFILE
#
#sed -i "s/DATABASENAME/$DATANAME/g" $CFILE
#
#sed -i "s/DATABASEUSER/$USERBASE/g" $CFILE
#
#sed -i "s/DATABASEPASSWD/$DATAPASS/g" $CFILE
#
## make 64 bit randon key
#RAN64=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 64 | head -n 1)
#sed -i "s/SECRETKEY/$RAN64/g" $CFILE
## make 16bit randon key
#RAN16=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)
#sed -i "s/UPGRADEKEY/$RAN16/g" $CFILE
## set skin
#sed -i "s/SKIN/timeless/g" $CFILE
#
### Must change Holders
##$wgSitename = "SITENAME";
##$wgMetaNamespace = "SITENAMESPACE";
### The protocol and server name to use in fully-qualified URLs
##$wgServer = "https://MWSERVER";
##$wgDBname = "DATABASENAME";
##$wgDBuser = "DATABASEUSER";
##$wgDBpassword = "DATABASEPASSWD";
## bash Generate random 64bit string (cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 64 | head -n 1)
##$wgSecretKey = "SECRETKEY";
## bash Generate random 16bit string (cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)
##$wgUpgradeKey = "UPGRADEKEY";
### names, ie 'vector', 'monobook', 'timeless':
##$wgDefaultSkin = "SKIN";
#
#
## Patch notes
## patch -p1 --dry-run -i mediawiki.patch
## patch -p1  -i mediawiki.patch
#











