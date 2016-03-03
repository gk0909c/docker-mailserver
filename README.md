# docker mail server  #
+ postfix
+ dovecot
+ postfixadmin

this image support only postgresql.  
And not support ssl, this image's purpose is used inside local network.
(e.g. local system notification)

## mail ##
To run,
```
# prepare db. e.g. host=postgresql, user=postfixadmin, password=adminpass, db-name=postfix

docker run -d --name mailserver \
    -e DB_HOST=postgresql -e DB_USER=postfixadmin \
    -e DB_PASS=adminpass -e DB_NAME=postfix \
    -p 50080:80 -p 50025:25 -p 50110:110 \
    --link db:postgresql \
    mailserver:latest
```

after run, access to http://localhost:50080/postfixadmin/setup.php.  
set admin password, update /var/www/html/postfixadmin/config.inc.php.  
it's enable by do bellow command.
```
docker exec [container] /opt/update_setup_password.sh [generated setup password]
```

