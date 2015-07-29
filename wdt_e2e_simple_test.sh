#! /bin/bash

#
# Smaller/minimal version of wdt_e2e_simple_test.sh
#

echo "Run from the cmake build dir (or ~/fbcode - or fbmake runtests)"

# Set DO_VERIFY:
# to 1 : slow/expensive but checks correctness
# to 0 : fast for repeated benchmarking not for correctness
DO_VERIFY=1

# Verbose / to debug failure:
#WDTBIN="_bin/wdt/wdt -minloglevel 0 -v 99"
# Normal:
WDTBIN_OPTS="-minloglevel=0 -sleep_millis 1 -max_retries 999 -full_reporting "\
"-avg_mbytes_per_sec=3000 -max_mbytes_per_sec=3500 "\
"-num_ports=4 -throttler_log_time_millis=200 -enable_checksum=true"
WDTBIN="_bin/wdt/wdt $WDTBIN_OPTS"

if [ -z "$HOSTNAME" ] ; then
    echo "HOSTNAME not set, will try with 'localhost'"
    HOSTNAME=localhost
else
    echo "Will self connect to HOSTNAME=$HOSTNAME"
fi

BASEDIR=/tmp/wdtTest
mkdir -p $BASEDIR
DIR=`mktemp -d $BASEDIR/XXXXXX`
echo "Testing in $DIR"

#pkill -x wdt

mkdir $DIR/src
mkdir $DIR/extsrc

#cp -R wdt folly /usr/bin /usr/lib /usr/lib64 /usr/libexec /usr/share $DIR/src
#cp -R wdt folly /usr/bin /usr/lib /usr/lib64 /usr/libexec $DIR/src
#cp -R wdt $DIR/src

#for size in 1k 64K 512K 1M 16M 256M 512M 1G
#for size in 512K 1M 16M 256M 512M 1G
# Mac's dd doesn't understand K,M,G...
for size in 1024 65536 524288 1232896 19726336
do
    base=inp$size
    echo dd if=/dev/... of=$DIR/src/$base.1 bs=$size count=1
    dd if=/dev/urandom of=$DIR/src/$base.1 bs=$size count=1
#    dd if=/dev/zero of=$DIR/src/$base.1 bs=$size count=1
    for i in {2..8}
    do
        cp $DIR/src/$base.1 $DIR/src/$base.$i
    done
done
echo "done with setup"

# test symlink issues
(cd $DIR/src ; touch a; ln -s doesntexist badlink; dd if=/dev/zero of=c bs=1024 count=1; mkdir d; ln -s ../d d/e; ln -s ../c d/a)
(cd $DIR/extsrc; mkdir TestDir; mkdir TestDir/test; cd TestDir; echo "Text1" >> file1; cd test; echo "Text2" >> file1; ln -s $DIR/extsrc/TestDir; cp -R $DIR/extsrc/TestDir $DIR/src)


CMD="$WDTBIN -minloglevel=1 -directory $DIR/dst 2> $DIR/server.log | head -1 | \
    xargs -I URL time $WDTBIN -directory $DIR/src -connection_url URL 2>&1 | \
    tee $DIR/client.log"
echo "First transfer: $CMD"
eval $CMD
STATUS=$?
# TODO check for $? / crash... though diff will indirectly find that case

CMD="$WDTBIN -minloglevel=1 -directory $DIR/dst_symlinks 2>> $DIR/server.log |\
    head -1 | xargs -I URL time $WDTBIN -follow_symlinks -directory $DIR/src \
    -connection_url URL 2>&1 | tee $DIR/client.log"
echo "Second transfer: $CMD"
eval $CMD
# TODO check for $? / crash... though diff will indirectly find that case


if [ $DO_VERIFY -eq 1 ] ; then
    echo "Verifying for run without follow_symlinks"
    echo "Checking for difference `date`"

    NUM_FILES=`(cd $DIR/dst && ( find . -type f | wc -l))`
    echo "Transfered `du -ks $DIR/dst` kbytes across $NUM_FILES files"

    (cd $DIR/src ; ( find . -type f -print0 | xargs -0 md5sum | sort ) \
        > ../src.md5s )
    (cd $DIR/dst ; ( find . -type f -print0 | xargs -0 md5sum | sort ) \
        > ../dst.md5s )

    echo "Should be no diff"
    (cd $DIR; diff -u src.md5s dst.md5s)
    STATUS=$?


    echo "Verifying for run with follow_symlinks"
    echo "Checking for difference `date`"

    NUM_FILES=`(cd $DIR/dst_symlinks && ( find . -type f | wc -l))`
    echo "Transfered `du -ks $DIR/dst_symlinks` kbytes across $NUM_FILES files"

    (cd $DIR/src ; ( find -L . -type f -print0 | xargs -0 md5sum | sort ) \
        > ../src_symlinks.md5s )
    (cd $DIR/dst_symlinks ; ( find . -type f -print0 | xargs -0 md5sum \
        | sort ) > ../dst_symlinks.md5s )

    echo "Should be no diff"
    (cd $DIR; diff -u src_symlinks.md5s dst_symlinks.md5s)
    SYMLINK_STATUS=$?
    if [ $STATUS -eq 0 ] ; then
      STATUS=$SYMLINK_STATUS
    fi
else
    echo "Skipping independant verification"
fi


echo "Server logs:"
cat $DIR/server.log

if [ $STATUS -eq 0 ] ; then
  echo "Good run, deleting logs in $DIR"
  find $DIR -type d | xargs chmod 755 # cp -r can make some unreadable dir
  rm -rf $DIR
else
  echo "Bad run ($STATUS) - keeping full logs and partial transfer in $DIR"
fi

exit $STATUS