#!/bin/bash

if [[ -a /etc/supervisor/conf.d/supervisord.conf ]]; then
  exit 0
fi

POSTFIX_SHELL=/opt/postfix.sh

# supervisor conf #########################################################################################
cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true

[program:postfix]
command=$POSTFIX_SHELL
autostart=true

[program:dovecot]
command=/usr/sbin/dovecot -c /etc/dovecot/dovecot.conf -F
autostart=true

[program:apache2]
command=/usr/sbin/apache2ctl -DFOREGROUND
autostart=true

[program:rsyslog]
command=/usr/sbin/rsyslogd -n -c3
autostart=true
EOF

# create postfix shell #################################################################################
cat >> $POSTFIX_SHELL <<EOF
#!/bin/bash
# call "postfix stop" when exiting
trap "{ echo Stopping postfix; /usr/sbin/postfix stop; exit 0; }" EXIT

# start postfix
/usr/sbin/postfix -c /etc/postfix start
# avoid exiting
sleep infinity   
EOF
chmod 755 $POSTFIX_SHELL

# prepare user #########################################################################################
V_GID=600
V_UID=600

groupadd -g $V_GID vmailuser
useradd  -u $V_UID -g vmailuser -m -d /home/vmailbox -s /sbin/nologin vmailuser

# Postfix #########################################################################################
# /etc/postfix/main.cf
postconf -F '*/*/chroot = n'

postconf -e smtpd_sasl_auth_enable=yes
postconf -e smtpd_sasl_type=dovecot
postconf -e smtpd_sasl_path=private/auth
postconf -e smtpd_sasl_security_options=noanonymous
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination

postconf -e local_transport=virtual
postconf -e virtual_transport=virtual
postconf -e virtual_mailbox_base=/home/vmailbox
postconf -e virtual_alias_maps=pgsql:/etc/postfix/pgsql_virtual_alias_maps.cf
postconf -e virtual_alias_domains='$virtual_alias_maps'
postconf -e virtual_mailbox_domains=pgsql:/etc/postfix/pgsql_virtual_domains_maps.cf
postconf -e virtual_mailbox_maps=pgsql:/etc/postfix/pgsql_virtual_mailbox_maps.cf
postconf -e virtual_minimum_uid=$V_UID
postconf -e virtual_uid_maps=static:$V_UID
postconf -e virtual_gid_maps=static:$V_GID

# postgres conf
cat >> /etc/postfix/pgsql_virtual_alias_maps.cf <<EOF
user = $DB_USER
password = $DB_PASS
hosts = $DB_HOST
dbname = $DB_NAME
query = SELECT goto FROM alias WHERE address='%s' AND active = true
EOF

cat >> /etc/postfix/pgsql_virtual_domains_maps.cf <<EOF
user = $DB_USER
password = $DB_PASS
hosts = $DB_HOST
dbname = $DB_NAME
query = SELECT domain FROM domain WHERE domain='%s' and backupmx = false and active = true
EOF

cat >> /etc/postfix/pgsql_virtual_mailbox_maps.cf <<EOF
user = $DB_USER
password = $DB_PASS
hosts = $DB_HOST
dbname = $DB_NAME
query = SELECT maildir||'Maildir/' FROM mailbox WHERE username='%s'
EOF

chown root:postfix /etc/postfix/pgsql_virtual_*
chmod 640 /etc/postfix/pgsql_virtual_*

# Dovecot ##########################################################################################

# /etc/dovecot/conf.d/auth-sql.conf
cp /etc/dovecot/conf.d/auth-sql.conf.ext /etc/dovecot/conf.d/auth-sql.conf
sed -i 's/dovecot-sql\.conf\.ext$/dovecot-sql.conf/g' /etc/dovecot/conf.d/auth-sql.conf

# /etc/dovecot/dovecot-sql.conf
cat >> /etc/dovecot/dovecot-sql.conf <<EOF
driver = pgsql
connect = host=$DB_HOST dbname=$DB_NAME user=$DB_USER password=$DB_PASS
default_pass_scheme = MD5-CRYPT
password_query = SELECT password FROM mailbox WHERE username = '%u' AND active = '1'
user_query = SELECT concat('/home/vmailbox/', maildir) as home, $V_UID as uid, $V_GID as gid FROM mailbox WHERE username = '%u' AND active = '1'
EOF

# /etc/dovecot/dovecot.conf
sed -i 's/^#listen =.*/listen = */g' /etc/dovecot/dovecot.conf

# /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#disable_plaintext_auth =.*/disable_plaintext_auth = no/g' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^auth_mechanisms =.*/auth_mechanisms = plain login cram-md5/g' /etc/dovecot/conf.d/10-auth.conf

# /etc/dovecot/conf.d/10-mail.conf
sed -i 's#^mail_location =.*#mail_location = maildir:/home/vmailbox/%d/%n/Maildir#g' /etc/dovecot/conf.d/10-mail.conf

# /etc/dovecot/conf.d/10-master.conf
# （コマンドの都合で逆順に追加してく）
start_num=$(grep -e "/var/spool/postfix/private/auth" -n /etc/dovecot/conf.d/10-master.conf | sed -e 's/:.*//g')
end_num=$(expr $start_num + 2)
sed -i "${start_num},${end_num}d" /etc/dovecot/conf.d/10-master.conf
sed -i "${start_num}i \ \ }" /etc/dovecot/conf.d/10-master.conf
sed -i "${start_num}i \ \ \ \ group = postfix" /etc/dovecot/conf.d/10-master.conf
sed -i "${start_num}i \ \ \ \ user = postfix" /etc/dovecot/conf.d/10-master.conf
sed -i "${start_num}i \ \ \ \ mode = 666" /etc/dovecot/conf.d/10-master.conf
sed -i "${start_num}i \ \ unix_listener /var/spool/postfix/private/auth {" /etc/dovecot/conf.d/10-master.conf

# /etc/dovecot/conf.d/10-ssl.conf
sed -i 's/^#ssl =.*/ssl = no/g' /etc/dovecot/conf.d/10-ssl.conf
sed -i 's,^ssl_cert = </etc/dovecot/dovecot.pem,#ssl_cert = </etc/dovecot/dovecot.pem,g' /etc/dovecot/conf.d/10-ssl.conf
sed -i 's,^ssl_key = </etc/dovecot/private/dovecot.pem,#ssl_key = </etc/dovecot/private/dovecot.pem,g' /etc/dovecot/conf.d/10-ssl.conf

# vi /etc/dovecot/dovecot.conf
echo 'protocols = pop3' >> /etc/dovecot/dovecot.conf

# Postfixamdin ##########################################################################################
cd /var/www/html
wget http://sourceforge.net/projects/postfixadmin/files/postfixadmin/postfixadmin-2.93/postfixadmin-2.93.tar.gz
tar xzf postfixadmin-2.93.tar.gz
mv postfixadmin-2.93 postfixadmin
rm postfixadmin-2.93.tar.gz
cd postfixadmin

sed -i "s/^\$CONF\['configured'\] =.*/\$CONF['configured'] = true;/g" config.inc.php
sed -i "s/^\$CONF\['emailcheck_resolve_domain'\]=.*/\$CONF['emailcheck_resolve_domain']='NO';/g" config.inc.php
sed -i "s/^\$CONF\['database_type'\] =.*/\$CONF['database_type'] = 'pgsql';/g" config.inc.php
sed -i "s/^\$CONF\['database_host'\] =.*/\$CONF['database_host'] = '$DB_HOST';/g" config.inc.php
sed -i "s/^\$CONF\['database_user'\] =.*/\$CONF['database_user'] = '$DB_USER';/g" config.inc.php
sed -i "s/^\$CONF\['database_password'\] =.*/\$CONF['database_password'] = '$DB_PASS';/g" config.inc.php
sed -i "s/^\$CONF\['database_name'\] =.*/\$CONF['database_name'] = '$DB_NAME';/g" config.inc.php
sed -i "s/^\$CONF\['encrypt'\] =.*/\$CONF['encrypt'] = 'dovecot:CRAM-MD5';/g" config.inc.php
sed -i "s,^\$CONF\['dovecotpw'\] =.*,\$CONF['dovecotpw'] = '/usr/bin/doveadm pw';,g" config.inc.php

chmod 777 /var/www/html/postfixadmin/templates_c/

