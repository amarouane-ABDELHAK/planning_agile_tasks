#! /bin/bash
sleep 5
mongosh --host mongodb --eval  "db.getSiblingDB('${database_name}').createUser({user:'${database_user}', pwd:'${database_password}', roles:[{role:'readWrite',db:'${database_name}'}]});"