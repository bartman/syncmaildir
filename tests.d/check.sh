#!/bin/sh

check_bin() {
	if which $1 >/dev/null; then
		return
	else
		echo $1 not installed
		exit 1
	fi
}

check_bin combine
check_bin grep
check_bin cut
check_bin sed
check_bin awk
check_bin sort

PATHS=`grep TRACE test.[0-9]*/log.client* | cut -d '|' -f 1 | cut -d : -f 2- | sort -u | wc -l`

echo
echo "Tested $PATHS paths"
echo

grep TRACE test.[0-9]*/log.client* | sort -u

echo
echo "Surely missing leaves (there may be more paths for the same leaf):"
echo

tmpa=`mktemp`
tmpb=`mktemp`

grep -n 'return *( *trace' smd-client | cut -d : -f 1 | sed 's/ //g' > $tmpa
grep TRACE test.[0-9]*/log.client* | sort -u | cut -d : -f 4 |\
	cut -d \| -f 1 | sed 's/ //g' > $tmpb
for N in `combine $tmpa not $tmpb`; do
	awk \
	"{L++} L==$N {\$1=\$2=\$3=\"\";print \"smd-client: \" L \":\" \$0 }" \
	smd-client
done
rm $tmpa $tmpb

echo
echo "Generated tags:"
echo
grep ^TAG test.[0-9]*/log.client* | cut -d : -f 2- | cut -d \( -f 1 | sort -u
