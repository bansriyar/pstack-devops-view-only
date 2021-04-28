#!/bin/bash

cd /var/www/somedomain/blog_somedomain_com
sudo npm install -g ghost-cli
sudo ghost install --db=mysql --dbhost='cust-auth-mysql.awsmum.somedomain-internal.com' --dbuser=pstack --dbpass="PstacK1010$" --dbname=pstack_ghost --process=systemd --dir=./ --url='http://blog.somedomain.com' --sslstaging=false --no-setup-nginx --prompt=false --ip=0.0.0.0 --port=10004 --enable --start
sudo systemctl start ghost_blog-somedomain-com.service