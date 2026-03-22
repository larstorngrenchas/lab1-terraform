#!/bin/bash
set -x
set -e
export DEBIAN_FRONTEND=noninteractive

# Tillfällig fix om apt behöver köra saker från /tmp under installationen
#export TMPDIR=/var/tmp

# 1. Paket & Verktyg (Adresserar DEB-0280, PKGS-7394)
apt-get update
apt-get install -y --no-install-recommends \
    ufw \
    fail2ban \
    unattended-upgrades \
    auditd \
    acct \
    libpam-tmpdir \
    apt-show-versions

apt-get install -y lynis rkhunter
#apt-get install -y lynis

# 2. SSH-härdning (Adresserar SSH-7408 - flera punkter)
sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding no/' /etc/ssh/sshd_config
sed -i 's/#AllowAgentForwarding yes/AllowAgentForwarding no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#MaxSessions 10/MaxSessions 2/' /etc/ssh/sshd_config
sed -i 's/#ClientAliveCountMax 3/ClientAliveCountMax 2/' /etc/ssh/sshd_config
echo "LogLevel VERBOSE" >> /etc/ssh/sshd_config
sed -i 's/#Compression yes/Compression no/' /etc/ssh/sshd_config
sed -i 's/#TCPKeepAlive yes/TCPKeepAlive no/' /etc/ssh/sshd_config
echo "AllowAgentForwarding no" >> /etc/ssh/sshd_config
systemctl restart ssh

# 3. Fail2ban fix (Adresserar DEB-0880)
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
systemctl restart fail2ban

# 4. Systemhärdning & Umask (Adresserar AUTH-9328, KRNL-5820)
echo "umask 027" >> /etc/profile
echo "* hard core 0" >> /etc/security/limits.conf

# Sätt restriktioner på kritiska verktyg (Adresserar PKGS-7394)
chmod 700 /usr/bin/gcc /usr/bin/make 2>/dev/null || true

# 5. Inaktivera protokoll som inte används (Adresserar NETW-3200)
echo "install dccp /bin/true" >> /etc/modprobe.d/disable-protocols.conf
echo "install sctp /bin/true" >> /etc/modprobe.d/disable-protocols.conf

# 6. Kernel parameters (Adresserar KRNL-5820)
#echo "net.ipv4.conf.all.rp_filter=1" >> /etc/sysctl.conf
#echo "net.ipv4.conf.default.rp_filter=1" >> /etc/sysctl.conf
#echo "net.ipv4.tcp_syncookies=1" >> /etc/sysctl.conf

cat <<EOF > /etc/sysctl.d/99-hardening.conf
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
EOF
#sysctl -p /etc/sysctl.d/99-hardening.conf

# Shadow-härdning (Adresserar AUTH-9328)
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
chmod 600 /etc/shadow
chmod 600 /etc/gshadow

# Öka antal rundor för lösenordshashing (SHA512 är bra, men 5000+ rundor är bättre)
sed -i 's/^SHA_CRYPT_MIN_ROUNDS.*/SHA_CRYPT_MIN_ROUNDS 5000/' /etc/login.defs
sed -i 's/^SHA_CRYPT_MAX_ROUNDS.*/SHA_CRYPT_MAX_ROUNDS 5000/' /etc/login.defs
# Öka säkerheten för lösenordshashing
sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' /etc/login.defs

# Tvinga umask 027 för alla nya användare i login.defs (AUTH-9328)
#sed -i 's/^UMASK.*/UMASK 027/' /etc/login.defs
# Härda inloggningskonfiguration (AUTH-9230, 9328)
# Sätt striktare umask för hela systemet
sed -i 's/UMASK\s*022/UMASK 027/' /etc/login.defs

# Ta bort onödiga tjänster (Adresserar DEB-0280)
systemctl stop snapd.service || true
systemctl disable snapd.service || true

# Enable firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw --force enable

# Enable automatic security updates
#dpkg-reconfigure -plow unattended-upgrades
echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

# Auditd & Lynis (Adresserar AUDT-9400, AUDT-9401)
#apt-get install -y acct
systemctl enable --now acct

# Ladda standardregler för auditd (övervakar t.ex. ändringar i /etc/passwd + Adresserar AUDT-9402)
#apt-get install -y auditd
systemctl enable --now auditd
cat <<EOF > /etc/audit/rules.d/audit.rules
-D
-b 8192
-f 1
--backlog_wait_time 60000
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/gshadow -p wa -k gshadow_changes
EOF
echo "-a always,exit -F arch=b64 -S execve -k exec" >> /etc/audit/rules.d/audit.rules
echo "-a always,exit -F arch=b32 -S execve -k exec" >> /etc/audit/rules.d/audit.rules
systemctl restart auditd

chmod 700 /usr/bin/as

# Inaktivera USB-lagring och andra fysiska portar (KRNL-5820 / USB-1000)
echo "install usb-storage /bin/true" >> /etc/modprobe.d/disable-usb.conf
echo "install firewire-core /bin/true" >> /etc/modprobe.d/disable-usb.conf
echo "install thunderbolt /bin/true" >> /etc/modprobe.d/disable-usb.conf

# Installera Lynis (DEB-baserat)
#apt-get install -y lynis

# Sätt en banner för att avskräcka obehöriga (Adresserar AUTH-9328)
#echo "Authorized access only!" > /etc/issue.net
# Sätt samma banner för lokala inloggningar
#echo "VARNING: Endast auktoriserad åtkomst. All aktivitet loggas." | tee /etc/issue /etc/issue.net
# Utökade banners och juridiska texter (BANN-7126, 7130)
# Lynis vill se varningar på flera ställen
MESSAGE="AUKTORISERAD ÅTKOMST ENDAST. All aktivitet övervakas och loggas."
echo "$MESSAGE" > /etc/issue
echo "$MESSAGE" > /etc/issue.net
echo "$MESSAGE" > /etc/motd

# Installera AIDE (File Integrity) - Ger ofta 3-5 poäng direkt
#apt-get install -y aide aideinit --no-install-recommends
#aideinit --quiet --force
#cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# Begränsa kärn-information (KRNL-6000)
# Hindra vanliga användare från att se dmesg (loggar från kärnan)
echo "kernel.dmesg_restrict = 1" >> /etc/sysctl.d/99-hardening.conf
# Göra det svårare att se adresser i kärnan (skydd mot exploits)
echo "kernel.kptr_restrict = 2" >> /etc/sysctl.d/99-hardening.conf
sysctl -p /etc/sysctl.d/99-hardening.conf

# Städa upp gamla paket (PKGS-7392)
apt-get autoremove -y
apt-get clean

# Kör en audit och spara rapporten på en säker plats
# --quick för att köra utan användarinteraktion
lynis audit system --quick --no-colors > /var/log/lynis-report.txt

# Skapa en enkel check-fil för att bekräfta att skriptet gått klart
echo "SUCCESS" > /var/tmp/startup-status

echo "Hardened startup script completed at $(date)" > /var/log/startup-complete.log

# Installera rkhunter (Rootkit Hunter)
#apt-get install -y rkhunter
# Uppdatera databasen men kör inte scan under startup (tar för lång tid)
rkhunter --propupd