#!/bin/bash
# A script to open MySQL and show databases

# Set MySQL user and password
MYSQL_USER="root"  # You can replace "root" with your MySQL username
MYSQL_PASS=""  # Replace with your MySQL password, or leave empty if no password

# Connect to MySQL and show databases
mysql -u $MYSQL_USER -p$MYSQL_PASS -e "SHOW DATABASES;"
