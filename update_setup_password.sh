#!/bin/bash

sed -i "s/^\$CONF\['setup_password'\] = 'changeme';/\$CONF['setup_password'] = '$1';/g" /var/www/html/postfixadmin/config.inc.php

