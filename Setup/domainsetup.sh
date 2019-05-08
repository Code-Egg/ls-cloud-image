#!/bin/bash
# /********************************************************************
# LiteSpeed domain setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0.2
# *********************************************************************/
MY_DOMAIN=''
MY_DOMAIN2=''
DOCHM='/var/www/html'
LSWSHM='/usr/local/lsws'
WEBCF="${LSWSHM}/conf/httpd_config.conf"
WEBVHCF="${LSWSHM}/conf/vhosts/wordpress/vhconf.conf"
UPDATELIST='/var/lib/update-notifier/updates-available'
WWW='FALSE'
UPDATE='TRUE'
OSNAME=''

echoY() {
    echo -e "\033[38;5;148m${1}\033[39m"
}
echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}

check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}
check_os
providerck()
{
  if [ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ] && [ -d /home/ubuntu ]; then 
    PROVIDER='aws'
  elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
    PROVIDER='google'      
  elif [ "$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
    PROVIDER='do'
  else
    PROVIDER='undefined'  
  fi
}
providerck

ipget()
{
  if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then 
    MY_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) 
  elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then 
    MY_IP=$(curl -s -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)    
  else
    MY_IP=$(ifconfig eth0 | grep 'inet '| awk '{printf $2}')
    #MY_IP=$(ip -4 route get 8.8.8.8 | awk {'print $7'} | tr -d '\n')
  fi    
}
ipget

domainhelp(){
    echo -e "\nIn order for WordPress to work properly, please enter a valid domain."
    echo -e "If you don't have one yet, you may cancel this process by pressing CTRL+C and continuing to SSH."
    echo -e "This prompt will open again the next time you log in, and will continue to do so until you finish the setup."
    echo -e "Please make sure the domain's DNS record has been properly pointed to this server."
    echo -e "\n(If you are using top level (root) domain, please include it with \033[38;5;71mwww.\033[39m so both www and root domain will be added)"
    echo -e "(ex. www.domain.com or sub.domain.com). Do not include http/s.\n"
}
domaininput(){
    printf "%s" "Your domain: "
    read MY_DOMAIN
    if [ -z "${MY_DOMAIN}" ] ; then
    echo -e "\nPlease input a valid domain\n"
    exit
    fi
    echo -e "The domain you put is: \e[31m${MY_DOMAIN}\e[39m"
    printf "%s"  "Please verify it is correct. [y/N]"
}

duplicateck(){
    grep "${1}" ${2} >/dev/null 2>&1
}

domainadd(){
    CHECK_WWW=$(echo ${MY_DOMAIN} | cut -c1-4)
    if [[ ${CHECK_WWW} == www. ]] ; then
        WWW='TRUE'
        #check if domain starts with www.
        MY_DOMAIN2=$(echo ${MY_DOMAIN} | cut -c 5-)

        duplicateck ${MY_DOMAIN2} ${WEBCF}
        if [ ${?} = 1 ]; then 
            #my_domain is domain wih www, and my_domain2 is domain without www, both added into listener.
            sed -i 's|wordpress '${MY_IP}'|wordpress '${MY_IP}', '${MY_DOMAIN}', '${MY_DOMAIN2}' |g' ${WEBCF}
        fi
    else
        duplicateck ${MY_DOMAIN} ${WEBCF}
        if [ ${?} = 1 ]; then
            #and if domain is not started with www. consider it as sub-domain
            sed -i 's|wordpress '${MY_IP}'|wordpress '${MY_IP}', '${MY_DOMAIN}'|g' ${WEBCF}
        fi    
    fi
    ${LSWSHM}/bin/lswsctrl restart > /dev/null
    echoG "\nDomain has been added into OpenLiteSpeed listener.\n"
}

domainverify(){
    echo "test" > ${DOCHM}/script-check.html
    if curl -s http://${MY_DOMAIN}/script-check.html | grep -q 'test'; then
        echoG "${MY_DOMAIN} check pass..."
    else
        echo "${MY_DOMAIN} inaccessible, please verify."; exit 1    
    fi
    if [ ${WWW} = 'TRUE' ]; then
        if curl -s http://${MY_DOMAIN2}/script-check.html | grep -q 'test'; then    
            echoG "${MY_DOMAIN2} check pass..."   
        else
            echo "${MY_DOMAIN2} inaccessible, please verify."; exit 1    
        fi    
    fi
    rm -f ${DOCHM}/script-check.html
}

emailinput(){
    #ask user e-mail for LE
    printf "%s" "Please enter your E-mail:"
    read EMAIL
    if echo "${EMAIL}" | grep '^[a-zA-Z0-9]*@[a-zA-Z0-9]*\.[a-zA-Z0-9]*$' >/dev/null; then
      echo -e "The E-mail you entered is: \e[31m${EMAIL}\e[39m"
      printf "%s"  "Please verify it is correct: [y/N]"
    else
      echo -e "\nPlease enter a valid E-mail, exit setup\n"; exit 1
    fi  
}

lecertapply(){
    if [ ${WWW} = 'TRUE' ]; then
        certbot certonly --non-interactive --agree-tos -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN} -d ${MY_DOMAIN2}
    else
        certbot certonly --non-interactive --agree-tos -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN}
    fi    
    if [ $? -eq 0 ]; then
        echo "vhssl  {
            keyFile                 /etc/letsencrypt/live/${MY_DOMAIN}/privkey.pem
            certFile                /etc/letsencrypt/live/${MY_DOMAIN}/fullchain.pem
            certChain               1
        }" >> ${WEBVHCF}

        echoG "\ncertificate has been successfully installed..."
    else
        echo "Oops, something went wrong..."
        exit 1
    fi
}

force_https() {
    duplicateck "RewriteCond %{HTTPS} on" "${DOCHM}/.htaccess"
    if [ ${?} = 1 ]; then 
        echo "$(echo '
### Forcing HTTPS rule start       
RewriteEngine On
RewriteCond %{SERVER_PORT} 80
RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
### Forcing HTTPS rule end
        ' | cat - ${DOCHM}/.htaccess)" > ${DOCHM}/.htaccess
        echoG "Force HTTPS rules has been added..."
    fi
}

endsetup(){
    sed -i '/domainsetup.sh/d' /etc/profile
}

aptupgradelist() {
    PACKAGE=$(cat ${UPDATELIST} | awk '{print $1}' | sed -n 2p)
    SECURITY=$(cat ${UPDATELIST} | awk '{print $1}' | sed -n 3p)
    if [ "${PACKAGE}" = '0' ] && [ "${SECURITY}" = '0' ]; then 
        UPDATE='FALSE'    
    fi    
}

yumupgradelist(){
    PACKAGE=$(yum check-update | grep -v '*\|Load*\|excluded' | wc -l)
    if [ "${PACKAGE}" = '0' ]; then 
        UPDATE='FALSE'
    fi    
}


aptgetupgrade() {
    apt-get update > /dev/null 2>&1
    echo -ne '#####                     (33%)\r'
    DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade > /dev/null 2>&1
    echo -ne '#############             (66%)\r'
    DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade > /dev/null 2>&1
    echo -ne '####################      (99%)\r'
    apt-get clean > /dev/null 2>&1
    apt-get autoclean > /dev/null 2>&1
    echo -ne '#######################   (100%)\r'
}

yumupgrade(){
    echo -ne '#                         (5%)\r'
    yum update -y > /dev/null 2>&1
    echo -ne '#######################   (100%)\r'
}

main(){
    if [ -d ${DOCHM}/wp-admin ]; then
        domainhelp
        i=1
        while [ ${i} -eq 1 ]; do
            domaininput
            read TMP_YN
            if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                domainadd
                i=$(($i-1))
            fi
        done    
        printf "%s"   "Do you wish to issue a Let's encrypt certificate for this domain? [y/N]"
        read TMP_YN
        if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
        #in case www domain , check both root domain and www domain accessibility.
            domainverify
            i=1
            while [ ${i} -eq 1 ]; do 
                emailinput
                read TMP_YN
                if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                    lecertapply
                    i=$(($i-1))
                fi
            done    
            printf "%s"   "Do you wish to force HTTPS rewrite rule for this domain? [y/N]"
            read TMP_YN
            if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                force_https
            fi
            ${LSWSHM}/bin/lswsctrl restart > /dev/null
        fi    
        echoG "\nEnjoy your accelarated WordPress with OpenLiteSpeed."
    fi   
    if [ "${OSNAME}" = 'ubuntu' ]; then 
        aptupgradelist
    else
        yumupgradelist
    fi    
    if [ "${UPDATE}" = 'TRUE' ]; then
        printf "%s"   "Do you wish to update the system which include the web server? [Y/n]"
        read TMP_YN
        if [[ ! "${TMP_YN}" =~ ^(n|N) ]]; then
            START_TIME="$(date -u +%s)"
            echoG "Update Starting..." 
            if [ "${OSNAME}" = 'ubuntu' ]; then 
                aptgetupgrade
            else
                yumupgrade
            fi    
            echoG "\nUpdate complete" 
            END_TIME="$(date -u +%s)"
            ELAPSED="$((${END_TIME}-${START_TIME}))"
            echoY "***Total of ${ELAPSED} seconds to finish process***"
        fi    
    fi 
    echoG 'Your system is up to date'
    endsetup
}
main
rm -- "$0"
exit 0
