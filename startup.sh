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

# Auditd & Lynis (Adresserar AUDT-9400, AUDT-9401)
apt-get install -y auditd

# Skapa en enkel audit-policy (Adresserar AUDT-9402)
echo "-a always,exit -F arch=b64 -S execve -k exec" >> /etc/audit/rules.d/audit.rules
echo "-a always,exit -F arch=b32 -S execve -k exec" >> /etc/audit/rules.d/audit.rules
systemctl restart auditd
chmod 700 /usr/bin/as

# Installera Lynis (DEB-baserat)
apt-get install -y lynis

# Sätt en banner för att avskräcka obehöriga (Adresserar AUTH-9328)
echo "Authorized access only!" > /etc/issue.net



# Kör en audit och spara rapporten på en säker plats
# --quick för att köra utan användarinteraktion
lynis audit system --quick --no-colors > /var/log/lynis-report.txt

# Skapa en enkel check-fil för att bekräfta att skriptet gått klart
echo "SUCCESS" > /var/tmp/startup-status

echo "Hardened startup script completed at $(date)" > /var/log/startup-complete.log