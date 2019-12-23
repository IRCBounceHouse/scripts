#!/bin/bash
################################################## Script Setup ####################################################
# This script needs to be run as root
if (( $EUID != 0 )); then
  echo "This script needs to be run as root."
  exit
fi
# Check that a few important packages are installed
while [ $(dpkg-query -W -f='${Status}' dnsutils 2>/dev/null | grep -c "ok installed") -eq 0 ]; do
      read -p "The package 'dnsutils' is missing and required to run this script. Would you like this script to install it? [Y/N] " yn
      case $yn in
          [Yy]* ) printf "Installing..."
                  apt install -y dnsutils >/dev/null 2>&1
                  printf "Done.\n\n"
                  break;;
          [Nn]* ) echo "This script cannot run without dnsutils. Exiting..."
                  exit 1;;
          * ) echo "Please answer Y(es) or N(o).";;
      esac
done
while [ $(dpkg-query -W -f='${Status}' sed 2>/dev/null | grep -c "ok installed") -eq 0  ]; do
      read -p "The package 'sed' is missing and required to run this script. Would you like this script to install it? [Y/N] " yn
      case $yn in
          [Yy]* ) printf "Installing..."
                  apt install -y sed >/dev/null 2>&1
                  printf "Done.\n\n"
                  break;;
          [Nn]* ) echo "This script cannot run without sed. Exiting..."
                  exit 1;;
          * ) echo "Please answer Y(es) or N(o).";;
      esac
done
while [ $(dpkg-query -W -f='${Status}' iptables-persistent 2>/dev/null | grep -c "ok installed") -eq 0  ]; do
      read -p "The package 'iptables-persistent' is missing and required to run this script. Would you like this script to install it? [Y/N] " yn
      case $yn in
          [Yy]* ) printf "Installing..."
                  echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" >> debconf-preseed-settings
                  echo "iptables-persistent iptables-persistent/autosave_v4 boolean false" >> debconf-preseed-settings
                  cat debconf-preseed-settings | debconf-set-selections
                  rm debconf-preseed-settings
                  apt install -y iptables-persistent >/dev/null 2>&1
                  printf "Done.\n\n"
                  break;;
          [Nn]* ) echo "This script cannot run without iptables-persistent. Exiting..."; exit 1;;
          * ) echo "Please answer Y(es) or N(o).";;
      esac
done

# Set up variables and default configuration options we'll use later
# Checks the file '/etc/os-release' and returns the debian OS version
OS_VERSION=$(cat /etc/os-release | grep PRETTY_NAME | cut -d '"' -f 2)
# Does the same thing as above only shortens the output to release name
OS_VERSION_SHORT=$(echo $OS_VERSION | sed -e s/\).*// -e s?.*\(??)
# /etc/ssh/sshd_config can have different wording across versions, even if the useage is the same. Use this line to find what the wording is.
SSHD_CONFIG_ROOT_LOGIN_STRING=$(cat /etc/ssh/sshd_config | grep "#PermitRootLogin" | cut -d ' ' -f 2)

# Get public IP and old hostname and store it as a variable for later
wanip=$(curl -s v4.ident.me;printf "\n")
wanipv6=$(curl -s v6.ident.me;printf "\n")
old_hostname=$(hostname -f)

# Check if the system this script is running on is debian 8, 9 or 10.
if [ "$OS_VERSION" == "Debian GNU/Linux 8 (jessie)" ]; then
  :
elif [ "$OS_VERSION" == "Debian GNU/Linux 9 (stretch)" ]; then
  :
elif [ "$OS_VERSION" == "Debian GNU/Linux 10 (buster)" ]; then
  :
else
  echo "It appears that this is not a debian system. Exiting..."
  exit 1
fi

# Create a file temporarily and set defaults for some apt installing we'll be doing later
echo "krb5-config	krb5-config/default_realm	string	default.realm.string" >> debconf-preseed-settings
echo "krb5-configkrb5-config/add_servers_realm	default.admin.realm.test.com	string" >> debconf-preseed-settings
echo "krb5-config	krb5-config/add_servers	boolean	true" >> debconf-preseed-settings
echo "krb5-config	krb5-config/add_servers_realm	string	server.realm.string" >> debconf-preseed-settings
echo "krb5-config	krb5-config/read_conf	boolean	true" >> debconf-preseed-settings
echo "krb5-config	krb5-config/kerberos_servers	string" >> debconf-preseed-settings
echo "krb5-config	krb5-config/admin_server	string" >> debconf-preseed-settings
echo "krb5-configkrb5-config/default_realm	default.realm.test.com	string" >> debconf-preseed-settings
cat debconf-preseed-settings | debconf-set-selections
rm debconf-preseed-settings

################################################ End Script Setup ##################################################

echo "Welcome to the IRCBounce House Debian Configuration Script!";printf "\n"
echo "This script will configure a new debian host the following ways:"
echo "  Part 1) Configure a fresh debian OS with default IBH settings (security settings, etc)."
echo "  Part 2) Install IPA-client and configure it to IBH configuration."
read -rsn1 -p "Press any key to start. Or CTRL+C to stop the script.";printf "\n";printf "\n"

read -p "What would you like the hostname of this client to be? (Note: It has to be a FQDN) " client_hostname
client_FQDN_checkv4=$(dig @1.1.1.1 A $client_hostname +short)
client_FQDN_checkv6=$(dig @1.1.1.1 AAAA $client_hostname +short)
# If the public IP of this client and the $client_hostname the user input are the same, continue on.
if [ "$wanip" == "$client_FQDN_checkv4" ] && [ "$wanipv6" == "$client_FQDN_checkv6" ]; then
  :
else
  echo "It appears that the hostname you selected does not resolve to the public IP of this server."
  echo "Note that IPv4 AND IPv6 need to resolve for FreeIPA to work correctly."
  echo "Please make sure this is the case and try again."
  exit 1
fi
# Get the domain name by cutting it out of the FQDN $client_hostname
domain=$(echo $client_hostname | sed 's/[^.]*[.]//')
read -p "What is the FQDN to the FreeIPA server? " server_hostname
# If the IPv4 or v6 address for the server's hostname is blank, something is wrong
if [ -z "$(dig @1.1.1.1 A $server_hostname +short)" ] || [ -z "$(dig @1.1.1.1 AAAA $server_hostname +short)" ]; then
  echo "It appears the server's hostname is missing an IPv4 or IPv6 record. Note that the server must have both."
  echo "Please correct this error and run this script again."
  exit 1
fi
read -p "What is the FreeIPA realm? " realm
realm=${realm^^};printf "\n"
echo "Now you must provide credentials of an admin user authorized to enroll hosts."
read -p "Please enter the FreeIPA admin username that will be used to enroll this host: " username_cred
read -sp "Your input will not be visible for this answer. Enter the password for the above user: " password_cred
printf "\n"
while true; do
    read -p "Is the above information correct? [Y/N] " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) echo "Exiting..."; exit 1;;
        * ) echo "Please answer Y(es) or N(o).";;
    esac
done

printf "\nNow configuring this host\n"
read -rsn1 -p "These actions may take a while. Press any key to start..."
# Pesky CDROM line
sed -e '/cdrom/ s/^#*/# /' -i /etc/apt/sources.list
# Add the FreeIPA repo and update apt
wget -qO - http://apt.numeezy.fr/numeezy.asc | apt-key add - >/dev/null 2>&1
echo "" >> /etc/apt/sources.list
echo "# Repo for FreeIPA" >> /etc/apt/sources.list
echo "deb http://apt.numeezy.fr $OS_VERSION_SHORT main" >> /etc/apt/sources.list
apt-get update >/dev/null 2>&1
apt-get -y upgrade >/dev/null 2>&1
apt-get -y install fail2ban >/dev/null 2>&1
# Allow established incoming/outgoing connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
# Open ports required by FreeIPA
# TCP 464 IN
iptables -A INPUT -p tcp --dport 464 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# UDP 464 IN
iptables -A INPUT -p udp --dport 464 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# UDP 123 IN
iptables -A INPUT -p udp --dport 123 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
systemctl enable fail2ban >/dev/null 2>&1

# Since we did the dpkg preseeding earlier we can make it noninteractive
DEBIAN_FRONTEND=noninteractive apt install -y freeipa-client >/dev/null 2>&1
# Use sed to search for any lines containing 'localhost' and $old_hostname and add '# ' to the front of that line.
sed -e '/localhost/ s/^#*/# /' -i /etc/hosts
sed -e "/$old_hostname/ s/^#*/# /" -i /etc/hosts
# Prepend the following lines to /etc/hosts
sed -i "1s;^;# The following lines are here for FreeIPA to work.\n$wanip      $client_hostname\n$wanipv6      $client_hostname\n;" /etc/hosts
# Change the hostname
hostname $client_hostname
invoke-rc.d hostname.sh start
echo "Done.";printf "\n"

echo "Next, this script will install and configure FreeIPA. It will be unresponsive until it's completed."
read -rsn1 -p "Press any key to start..."
ipa-client-install --unattended --enable-dns-updates --hostname=$client_hostname --mkhomedir --server=$server_hostname --domain=$domain --realm=$realm --principal=$username_cred --password=$password_cred >/dev/null 2>&1

# Configure SSH correctly. FreeIPA changes the configuration so we change it back after it runs.
# Use the check we did earlier about the sshd_config wording and change the configuration file
sed -i "s/#PermitRootLogin $SSHD_CONFIG_ROOT_LOGIN_STRING/PermitRootLogin without-password/g" /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
# Configure SSH to work with FreeIPA and SSSD
sed -i 's/#UsePAM yes/UsePAM yes/g' /etc/ssh/sshd_config
systemctl restart ssh >/dev/null 2>&1
echo "session required pam_mkhomedir.so" >> /etc/pam.d/common-session
printf "Done.\n"
