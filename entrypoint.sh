#!/usr/bin/env sh
CMD=$1

case "$CMD" in

	"server" )
	exec ./agent
	;;

	"migrations" )
	exec go run initDatabase.go
	;;

	"test" )
	exec /bin/bash -c "trap : TERM INT; sleep infinity & wait"
	;;

	* )
	exec $CMD ${@:2}
	;;
esac