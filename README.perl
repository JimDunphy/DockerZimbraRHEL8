#!/bin/sh

{
    echo "====== $(date) ======"
    echo "PID: $$ | PPID: $PPID | Called as: $0 $*"
    echo "--- Arguments ($#) ---"
    printf '  "%s"\n' "$@"
    echo "--- Environment ---"
    env | sort | sed 's/^/  /'
    echo "--- Process Tree ---"
    pstree -p $$ | sed 's/^/  /'
    echo
} >> /tmp/perl-debug.log

exec /bin/perl.real "$@"

#
# Trying to understand how many ways zimbra calls perl
#
# mv /bin/perl /bin/perl.real
# mv $0 /bin/perl
# chmod 755 /bin/perl
# tail -f /tmp/perl-debug.log
