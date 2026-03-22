#!/bin/bash

# 1. Paket & Verktyg (Adresserar DEB-0280, PKGS-7394)
apt-get update
apt-get install -y ufw fail2ban unattended-upgrades libpam-tmpdir apt-show-versions

# 2. SSH-härdning (Adresserar SSH-7408 - flera punkter)
sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding no/' /etc/ssh/sshd_config
sed -i 's/#AllowAgentForwarding yes/AllowAgentForwarding no/' /etc/ssh/sshd_config
echo "LogLevel VERBOSE" >> /etc/ssh/sshd_config
systemctl restart ssh

# 3. Fail2ban fix (Adresserar DEB-0880)
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
systemctl restart fail2ban

# 4. Systemhärdning & Umask (Adresserar AUTH-9328, KRNL-5820)
echo "umask 027" >> /etc/profile
echo "* hard core 0" >> /etc/security/limits.conf

# 5. Inaktivera protokoll som inte används (Adresserar NETW-3200)
echo "install dccp /bin/true" >> /etc/modprobe.d/disable-protocols.conf
echo "install sctp /bin/true" >> /etc/modprobe.d/disable-protocols.conf

# Enable firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw --force enable

# Enable automatic security updates
dpkg-reconfigure -plow unattended-upgrades

# Installera Lynis (DEB-baserat)
apt-get install -y lynis

# Kör en audit och spara rapporten på en säker plats
# --quick för att köra utan användarinteraktion
lynis audit system --quick > /var/log/lynis-report.txt

# Skapa en enkel check-fil för att bekräfta att skriptet gått klart
echo "SUCCESS" > /var/tmp/startup-status

echo "Hardened startup script completed at $(date)" > /var/log/startup-complete.log