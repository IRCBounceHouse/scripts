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
  echo "Debian 8 is End of Life. Consider updating."
  exit 1
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
echo "  Part 3) (Optional) Install ZNC"
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
# If this is a debian 10 system, we don't need to add a 3rd-party Freeipa repo
if [ $OS_VERSION_SHORT = 'buster' ]; then
  :
else
  # This is not debian 10. We'll need to use a 3rd-party repo
  # Add the FreeIPA repo apt key
  wget -qO - http://apt.numeezy.fr/numeezy.asc | apt-key add - >/dev/null 2>&1
  # Check if the FreeIPA repo is already in /etc/apt/sources.list, if it is, do nothing. If not, add it.
  if cat /etc/apt/sources.list | grep -q "http://apt.numeezy.fr"; then
    :
  else
    echo "" >> /etc/apt/sources.list
    echo "# Repo for FreeIPA" >> /etc/apt/sources.list
    echo "deb http://apt.numeezy.fr $OS_VERSION_SHORT main" >> /etc/apt/sources.list
  fi
fi
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
# Use the check we did earlier with $SSHD_CONFIG_ROOT_LOGIN_STRING and change the configuration file if necessary
# If $SSHD_CONFIG_ROOT_LOGIN_STRING is null, grep didn't find the commented string, so it's already set how we want it.
sed -i "s/#PermitRootLogin $SSHD_CONFIG_ROOT_LOGIN_STRING/PermitRootLogin without-password/g" /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# Configure SSH to work with FreeIPA and SSSD
sed -i 's/#UsePAM yes/UsePAM yes/g' /etc/ssh/sshd_config
systemctl restart ssh >/dev/null 2>&1
echo "session required pam_mkhomedir.so" >> /etc/pam.d/common-session
printf "FreeIPA is sucessfully installed and configured for use.\n\n"

read -p "Would you like this script to install znc? [Y/N] " yn
      case $yn in
          [Yy]* ) ;;
          [Nn]* ) exit;;
          * ) echo "Please answer Y(es) or N(o).";;
      esac
printf "\nThis script will do the following:\n"
echo "  1) Download ZNC 1.7.5 from tarball"
echo "  2) Install the following packages if they aren't already installed (this may take a while): "
echo "    build-essential, libssl-dev, libperl-dev, pkg-config, libicu-dev, libsasl2-dev"
echo "  3) Install ZNC in $HOME/.znc/ with the following configurations:"
echo "    a) Disabled modules: awaynick, awaystore, bouncedcc, dcc, log, savebuff"
echo "    b) Enable python, perl, cyrusauth"
read -rsn1 -p "Now installing ZNC 1.7.5. This will take a long time. Press CTRL+C to stop or any key to continue..."
apt install -y build-essential libssl-dev libperl-dev pkg-config libicu-dev libsasl2-dev >/dev/null 2>&1
wget https://znc.in/releases/znc-1.7.5.tar.gz >/dev/null 2>&1
tar -xzvf znc-1.7.5.tar.gz >/dev/null 2>&1
mv $PWD/znc-1.7.5/modules/awaynick.cpp awaynick.cpp.bak
mv $PWD/znc-1.7.5/modules/awaystore.cpp awaystore.cpp.bak
mv $PWD/znc-1.7.5/modules/bouncedcc.cpp bouncedcc.cpp.bak
mv $PWD/znc-1.7.5/modules/dcc.cpp dcc.cpp.bak
mv $PWD/znc-1.7.5/modules/log.cpp log.cpp.bak
mv $PWD/znc-1.7.5/modules/savebuff.cpp savebuff.cpp.bak
$PWD/znc-1.7.5/./configure --prefix="$HOME/.znc" --enable-cyrus >/dev/null 2>&1
make >/dev/null 2>&1
make install >/dev/null 2>&1