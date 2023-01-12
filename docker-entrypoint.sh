if [ "$MONGODB_USER" ] && [ "$MONGODB_PASS" ]; then
                "${mongo[@]}" "$MONGODB_DATABASE" <<-EOJS
                db.createUser({
                    user: $(_js_escape "$MONGODB_USER"),
                    pwd: $(_js_escape "$MONGODB_PASS"),
                    roles: [ "readWrite", "dbAdmin" ]
                })
            EOJS
fi