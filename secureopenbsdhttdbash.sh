#!/bin/sh
# Script to setup a secure httpd webserver on OpenBSD with security enhancements.
#https://github.com/GenerativePaleopithecene/secure-openbsd-webserver-deploy
#gpl3

# Variables
DOMAIN="yourcleverdomainname.xyz"
DOCROOT="/var/www/htdocs/$DOMAIN"
SSLDIR="/etc/ssl/$DOMAIN"
CONFIG="/etc/httpd.conf"
USERNAME="yourusername"
PASSWORD="yourpassword"

# Update the system
pkg_add -Uu

# Make directories for the website
mkdir -p $DOCROOT
mkdir -p $SSLDIR

# Set appropriate permissions and ownership for web root and SSL directories
chown -R www:www $DOCROOT
chmod -R 755 $DOCROOT
chmod 700 $SSLDIR

# Create a simple index.html
echo "<h1>Hello, World!</h1>" > $DOCROOT/index.html

# Generate SSL certificates
acme-client $DOMAIN

# Backup configuration files
cp /etc/httpd.conf /etc/httpd.conf.backup
cp /etc/pf.conf /etc/pf.conf.backup
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
cp /etc/sysctl.conf /etc/sysctl.conf.backup

# Create the httpd configuration
echo "
server \"$DOMAIN\" {
    listen on * tls port 443
    root \"$DOCROOT\"
    tls {
        certificate \"/etc/ssl/acme/$DOMAIN/cert.pem\"
        key \"/etc/ssl/acme/private/$DOMAIN/privkey.pem\"
    }
}

server \"$DOMAIN\" {
    listen on * port 80
    block return 301 \"https://$DOMAIN\$REQUEST_URI\"
}" > $CONFIG

# Enable and start the httpd service
rcctl enable httpd
rcctl restart httpd

# Configure the firewall
echo "
set skip on lo

# Default deny everything
block all

# Allow incoming SSH, HTTP, and HTTPS
pass in on egress proto tcp to port {22 80 443}

# Allow all outgoing traffic
pass out on egress
" > /etc/pf.conf

# Enable and start the firewall
rcctl enable pf
rcctl restart pf

# Ensure OpenSSH server is installed (it should be by default in OpenBSD)
pkg_info -Q openssh || pkg_add openssh

# Ensure the SSH service is enabled
rcctl enable sshd
rcctl start sshd

# Harden SSH
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
rcctl restart sshd

# Harden sysctl.conf
echo "
# Disable ICMP redirects
net.inet.ip.redirect=0
# Enable random IP ID field
net.inet.ip.random_id=1
# Enable TCP syncookies
net.inet.tcp.syncookies=1
# Log suspicious packets
net.inet.ip.log=1
# Randomize PIDs
kern.randompid=1
" >> /etc/sysctl.conf

# Secure user account creation
useradd -m -s /bin/ksh -G wheel $USERNAME
echo $PASSWORD | passwd $USERNAME

# Limit su to users in the wheel group
echo "auth        required    pam_wheel.so" >> /etc/pam.d/su

# Logging
syslogd_flags="-a /var/www/logs/*.log"

# Install and configure fail2ban
pkg_add fail2ban
cp /etc/fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.local
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
rcctl enable fail2ban
rcctl start fail2ban

# Review and harden permissions of other directories and files
chmod 700 /root
chmod 600 /etc/master.passwd

# Install and setup Lynis for security auditing
pkg_add lynis

# Add to cron jobs for regular updates and security checks
echo "0 3 * * * /usr/bin/syspatch" >> /etc/crontab
echo "0 4 * * 0 /usr/local/bin/lynis audit system >> /var/log/lynis.log" >> /etc/crontab

# Enable automatic security updates
echo "Upgrading packages" >> /etc/daily.local
echo "pkg_add -Uu" >> /etc/daily.local
chmod +x /etc/daily.local

# ClamAV installation and setup
pkg_add clamav
rcctl enable clamd
rcctl enable freshclam

# Regular updates to ClamAV
echo "15 1 * * * /usr/local/bin/freshclam --quiet" > /etc/crontab

# Regular malware scanning
echo "30 2 * * * /usr/local/bin/clamscan -i -r /" >> /etc/crontab
