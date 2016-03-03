FROM gk0909c/ubuntu
MAINTAINER gk0909c@gmail.com

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update 
RUN apt-get install -y supervisor postfix postfix-pgsql sasl2-bin libsasl2-modules dovecot-common dovecot-pop3d dovecot-pgsql
RUN apt-get install -y apache2 php5 php5-pgsql

RUN rm -rf /var/lib/apt/lists/*

COPY install.sh /opt/install.sh
COPY install.sh /opt/update_setup_password.sh
RUN chmod 755 /opt/install.sh /opt/update_setup_password.sh

EXPOSE 25 110

CMD /opt/install.sh;/usr/bin/supervisord -c /etc/supervisor/supervisord.conf

