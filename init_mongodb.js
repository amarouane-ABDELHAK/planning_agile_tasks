db.createUser(
    {
      user: process.env.database_user,
      pwd: process.env.database_password,
      roles: [ "readWrite", "dbAdmin" ]
    }
 )