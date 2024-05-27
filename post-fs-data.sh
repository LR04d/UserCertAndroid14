#!/system/bin/sh
set -x

MODDIR=${0%/*}

set_context() {
    [ "$(getenforce)" = "Enforcing" ] || return 0

    default_selinux_context=u:object_r:system_file:s0
    selinux_context=$(ls -Zd $1 | awk '{print $1}')

    if [ -n "$selinux_context" ] && [ "$selinux_context" != "?" ]; then
        chcon -R $selinux_context $2
    else
        chcon -R $default_selinux_context $2
    fi
}

# Get list user certs
CERT_FILE_LIST=$(ls /data/misc/user/*/cacerts-added/* | (IFS=.; while read -r left right; do echo $left.$right; done))

# HASH_CERT_FILE_LIST=$(ls -1 /data/misc/user/*/cacerts-added/* | xargs basename | (IFS=.; while read -r left right; do echo $left.$right; done))

# Moving and remove user certs

for CERT_FILE in $CERT_FILE_LIST; do
    if ! [ -e "${CERT_FILE}" ]; then
        exit 0
    fi

    HASH_CERT=$(echo $CERT_FILE | sed 's:.*/::')

    rm -f /data/misc/user/*/cacerts-removed/${HASH_CERT}
    cp -f ${CERT_FILE} ${MODDIR}/system/etc/security/cacerts/${HASH_CERT}
done


chown -R 0:0 ${MODDIR}/system/etc/security/cacerts
set_context /system/etc/security/cacerts ${MODDIR}/system/etc/security/cacerts

# Android 14 support
# Since Magisk ignore /apex for module file injections, use non-Magisk way
if [ -d /apex/com.android.conscrypt/cacerts ]; then
    # Clone directory into tmpfs
    rm -f /data/local/tmp/tmp-ca-copy
    mkdir -p /data/local/tmp/tmp-ca-copy
    mount -t tmpfs tmpfs /data/local/tmp/tmp-ca-copy
    cp -f /apex/com.android.conscrypt/cacerts/* /data/local/tmp/tmp-ca-copy/

    # Do the same as in Magisk module
    for CERT_FILE in $CERT_FILE_LIST; do
        HASH_CERT=$(echo $CERT_FILE | sed 's:.*/::')
        cp -f ${CERT_FILE} /data/local/tmp/tmp-ca-copy/${HASH_CERT}
    done

    chown -R 0:0 /data/local/tmp/tmp-ca-copy
    set_context /apex/com.android.conscrypt/cacerts /data/local/tmp/tmp-ca-copy

    CERTS_NUM="$(ls -1 /data/local/tmp/tmp-ca-copy | wc -l)"
    if [ "$CERTS_NUM" -gt 10 ]; then
        mount --bind /data/local/tmp/tmp-ca-copy /apex/com.android.conscrypt/cacerts
        for pid in 1 $(pgrep zygote) $(pgrep zygote64); do
            nsenter --mount=/proc/${pid}/ns/mnt -- \
                /bin/mount --bind /data/local/tmp/tmp-ca-copy /apex/com.android.conscrypt/cacerts
        done
    fi

    umount /data/local/tmp/tmp-ca-copy
    rmdir /data/local/tmp/tmp-ca-copy
fi